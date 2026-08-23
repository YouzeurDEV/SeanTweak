#Requires -Version 5.1
<#
    TweakSean v2.0
    Optimisation Windows 10 / 11

    - Navigation clavier (fleches + espace), rendu ANSI 24 bits
    - Catalogue de tweaks pilote par donnees (plus de gros switch)
    - Journal des valeurs precedentes -> annulation possible
    - Point de restauration avant application
#>

[CmdletBinding()]
param(
    [switch]$NoElevate
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

if ($Host.Name -ne 'ConsoleHost') {
    Write-Warning "TweakSean doit etre lance depuis une console PowerShell classique"
    Write-Warning "(ni ISE, ni le terminal integre de VS Code) : la navigation clavier n'y fonctionne pas."
    Write-Warning "Utilise SeanTweak.bat."
    return
}

# ============================================================================
#  0. ELEVATION
# ============================================================================
$principal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent())

if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    if ($NoElevate) {
        Write-Host "Droits administrateur requis." -ForegroundColor Red
        exit 1
    }
    $me = $MyInvocation.MyCommand.Path
    Start-Process -FilePath (Get-Process -Id $PID).Path -Verb RunAs `
        -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$me`""
    exit
}

# ============================================================================
#  1. CONSOLE : VT, taille, theme
# ============================================================================
function Enable-VirtualTerminal {
    if ($PSVersionTable.PSVersion.Major -ge 7) { return $true }
    try {
        if (-not ('TS.Native' -as [type])) {
            Add-Type -Namespace TS -Name Native -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr GetStdHandle(int n);
[DllImport("kernel32.dll", SetLastError=true)] public static extern bool GetConsoleMode(IntPtr h, out uint m);
[DllImport("kernel32.dll", SetLastError=true)] public static extern bool SetConsoleMode(IntPtr h, uint m);
'@
        }
        $h = [TS.Native]::GetStdHandle(-11)
        [uint32]$mode = 0
        if (-not [TS.Native]::GetConsoleMode($h, [ref]$mode)) { return $false }
        return [TS.Native]::SetConsoleMode($h, $mode -bor 0x0004)
    } catch { return $false }
}

$script:VT = Enable-VirtualTerminal

function Fg([int]$r, [int]$g, [int]$b) {
    if ($script:VT) { ([char]27) + "[38;2;$r;$g;${b}m" } else { '' }
}
function Bg([int]$r, [int]$g, [int]$b) {
    if ($script:VT) { ([char]27) + "[48;2;$r;$g;${b}m" } else { '' }
}

$T = @{
    Reset  = if ($script:VT) { ([char]27) + '[0m' } else { '' }
    Bold   = if ($script:VT) { ([char]27) + '[1m' } else { '' }
    Text   = Fg 226 232 240
    Dim    = Fg 152 160 178
    Faint  = Fg 98  107 126
    Accent = Fg 139 124 246
    Cyan   = Fg 56  208 232
    Ok     = Fg 74  222 128
    Warn   = Fg 250 204 21
    Bad    = Fg 248 113 113
    SelBg  = Bg 35  39  56
}

function Set-ConsoleSize {
    try {
        $ui  = $Host.UI.RawUI
        $max = $ui.MaxPhysicalWindowSize
        $w   = [Math]::Min(112, $max.Width)
        $h   = [Math]::Min(44,  $max.Height)

        # On retrecit d'abord la fenetre, puis le buffer, sinon Windows refuse
        # un buffer plus petit que la fenetre courante.
        $win = $ui.WindowSize
        $win.Width  = [Math]::Min($win.Width,  $w)
        $win.Height = [Math]::Min($win.Height, $h)
        $ui.WindowSize = $win

        $buf = $ui.BufferSize
        $buf.Width  = $w
        $buf.Height = $h        # pas d'historique : evite tout decalage buffer/fenetre
        $ui.BufferSize = $buf

        $win = $ui.WindowSize
        $win.Width  = $w
        $win.Height = $h
        $ui.WindowSize = $win
    } catch { }
}
function Sync-ConsoleBuffer {
    try {
        $ui  = $Host.UI.RawUI
        $win = $ui.WindowSize
        $buf = $ui.BufferSize
        if ($buf.Width -ne $win.Width -or $buf.Height -ne $win.Height) {
            $buf.Width  = $win.Width
            $buf.Height = $win.Height
            $ui.BufferSize = $buf
        }
    } catch { }
}

Set-ConsoleSize

$script:EscRx = [regex]("$([char]27)\[[0-9;]*m")
$script:EscCh = [char]27
function Visible-Length([string]$s) {
    if ($s.IndexOf($script:EscCh) -lt 0) { return $s.Length }
    $script:EscRx.Replace($s, '').Length
}

function Pad-To([string]$s, [int]$width) {
    $len = Visible-Length $s
    if ($len -ge $width) { return $s }
    $s + (' ' * ($width - $len))
}

function Wrap-Text([string]$s, [int]$width) {
    if ([string]::IsNullOrWhiteSpace($s)) { return @('') }
    $out = @(); $line = ''
    foreach ($word in ($s -split '\s+')) {
        if ($line.Length -eq 0) { $line = $word }
        elseif (($line.Length + 1 + $word.Length) -le $width) { $line += ' ' + $word }
        else { $out += $line; $line = $word }
    }
    if ($line) { $out += $line }
    $out
}

# ============================================================================
#  2. JOURNAL / REGISTRE
# ============================================================================
$script:DataDir     = Join-Path $env:LOCALAPPDATA 'TweakSean'
$script:JournalPath = Join-Path $script:DataDir 'journal.json'
$script:LogPath     = Join-Path $script:DataDir 'tweaksean.log'
$script:Journal     = New-Object System.Collections.ArrayList
$script:StepErrors  = New-Object System.Collections.ArrayList

if (-not (Test-Path $script:DataDir)) {
    New-Item -Path $script:DataDir -ItemType Directory -Force | Out-Null
}

function Write-Log([string]$msg) {
    $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    Add-Content -Path $script:LogPath -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
}

function Set-Reg {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [ValidateSet('DWord', 'QWord', 'String', 'ExpandString', 'Binary', 'MultiString')]
        [string]$Type = 'DWord'
    )
    $existed = $false; $old = $null
    try {
        $old = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name
        $existed = $true
    } catch { }

    try {
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force -ErrorAction Stop | Out-Null }
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
    } catch {
        # on note et on continue : les autres cles du meme tweak doivent passer
        $short = ($Path -replace '^HK(LM|CU):\\SOFTWARE\\', '') + "\$Name"
        [void]$script:StepErrors.Add("$short : $($_.Exception.Message)")
        Write-Log "REFUS $Path\$Name : $($_.Exception.Message)"
        return
    }

    # journalise seulement ce qui a reellement ete ecrit, sinon l'annulation
    # tenterait de restaurer des valeurs jamais modifiees
    [void]$script:Journal.Add([pscustomobject]@{
        Kind = 'reg'; Path = $Path; Name = $Name
        Existed = $existed; Old = $old; New = $Value; Type = $Type
    })
    Write-Log "REG $Path\$Name = $Value (avant: $(if($existed){$old}else{'<absent>'}))"
}

function Set-Svc {
    param([Parameter(Mandatory)][string]$Name,
          [ValidateSet('Disabled', 'Manual', 'Automatic')][string]$StartupType = 'Disabled')

    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) { return }

    $old = (Get-CimInstance Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue).StartMode

    try {
        if ($svc.Status -eq 'Running' -and $StartupType -eq 'Disabled') {
            Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
        }
        Set-Service -Name $Name -StartupType $StartupType -ErrorAction Stop
    } catch {
        [void]$script:StepErrors.Add("service $Name : $($_.Exception.Message)")
        Write-Log "REFUS SVC $Name : $($_.Exception.Message)"
        return
    }

    [void]$script:Journal.Add([pscustomobject]@{
        Kind = 'svc'; Name = $Name; Old = $old; New = $StartupType
    })
    Write-Log "SVC $Name -> $StartupType (avant: $old)"
}

function Save-Journal {
    if ($script:Journal.Count -eq 0) { return }
    $existing = @()
    if (Test-Path $script:JournalPath) {
        try { $existing = @(Get-Content $script:JournalPath -Raw | ConvertFrom-Json) } catch { }
    }
    $all = @($existing) + @($script:Journal)
    $all | ConvertTo-Json -Depth 5 | Set-Content -Path $script:JournalPath -Encoding UTF8
}

# ============================================================================
#  3. CATALOGUE DES TWEAKS
# ============================================================================
$EXPLORER_ADV = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$CDM          = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'

$script:Tweaks = @(

    # ---- Confidentialite -----------------------------------------------
    @{ Cat = 'Confidentialité & télémétrie'; Risk = 0
       Label = "Désactiver les notifications"
       Desc  = "Coupe les toasts du centre de notifications (Windows et applis)."
       Do = { Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications' 'ToastEnabled' 0 } }

    @{ Cat = 'Confidentialité & télémétrie'; Risk = 0
       Label = "Désactiver les suggestions et conseils Windows"
       Desc  = "Supprime les 'astuces', apps suggérées dans le menu Démarrer et pubs dans les Paramètres."
       Do = {
            foreach ($n in 'SubscribedContent-338389Enabled','SubscribedContent-338393Enabled',
                           'SubscribedContent-353694Enabled','SubscribedContent-353696Enabled',
                           'SubscribedContent-310093Enabled','SystemPaneSuggestionsEnabled',
                           'SilentInstalledAppsEnabled','PreInstalledAppsEnabled',
                           'OemPreInstalledAppsEnabled','SoftLandingEnabled') {
                Set-Reg $CDM $n 0
            }
            Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1
       } }

    @{ Cat = 'Confidentialité & télémétrie'; Risk = 1
       Label = "Désactiver l'Assistant Stockage (Storage Sense)"
       Desc  = "Windows ne supprimera plus automatiquement les fichiers temporaires. Pense à un nettoyage planifié en compensation."
       Do = { Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\StorageSense' 'AllowStorageSenseGlobal' 0 } }

    @{ Cat = 'Confidentialité & télémétrie'; Risk = 0
       Label = "Réduire la télémétrie au minimum"
       Desc  = "AllowTelemetry=0 (Sécurité) + arrêt des services DiagTrack et dmwappushservice."
       Do = {
            Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 0
            Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' 'AllowTelemetry' 0
            Set-Svc 'DiagTrack' 'Disabled'
            Set-Svc 'dmwappushservice' 'Disabled'
       } }

    @{ Cat = 'Confidentialité & télémétrie'; Risk = 0
       Label = "Désactiver l'identifiant publicitaire"
       Desc  = "Empêche les applis de te suivre entre elles via l'Advertising ID."
       Do = {
            Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0
            Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo' 'DisabledByGroupPolicy' 1
       } }

    @{ Cat = 'Confidentialité & télémétrie'; Risk = 0
       Label = "Désactiver l'historique d'activité"
       Desc  = "Plus de collecte de la Timeline ni d'envoi d'activité au compte Microsoft."
       Do = {
            $p = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
            Set-Reg $p 'EnableActivityFeed' 0
            Set-Reg $p 'PublishUserActivities' 0
            Set-Reg $p 'UploadUserActivities' 0
       } }

    @{ Cat = 'Confidentialité & télémétrie'; Risk = 0
       Label = "Désactiver Copilot et Recall"
       Desc  = "Retire Windows Copilot et bloque l'analyse d'écran de Recall (Windows 11 24H2+)."
       Do = {
            Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
            Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
            Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1
       } }

    @{ Cat = 'Confidentialité & télémétrie'; Risk = 0
       Label = "Retirer la recherche web (Bing) du menu Démarrer"
       Desc  = "La recherche Démarrer ne renvoie plus que des résultats locaux. Nettement plus rapide."
       Do = {
            Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
            Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0
            Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'CortanaConsent' 0
       } }

    @{ Cat = 'Confidentialité & télémétrie'; Risk = 0
       Label = "Nettoyer l'écran de verrouillage (Spotlight, pubs)"
       Desc  = "Supprime les 'faits amusants', suggestions et publicités de l'écran de verrouillage."
       Do = {
            Set-Reg $CDM 'RotatingLockScreenOverlayEnabled' 0
            Set-Reg $CDM 'SubscribedContent-338387Enabled' 0
            Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0
       } }

    # ---- Interface -------------------------------------------------------
    @{ Cat = 'Interface & Explorateur'; Risk = 0
       Label = "Afficher les vignettes au lieu des icônes"
       Desc  = "Aperçu des images/vidéos dans l'Explorateur au lieu de l'icône générique."
       Do = { Set-Reg $EXPLORER_ADV 'IconsOnly' 0 } }

    @{ Cat = 'Interface & Explorateur'; Risk = 0
       Label = "Afficher les extensions de fichiers"
       Desc  = "Indispensable : permet de repérer un 'photo.jpg.exe'. Sécurité de base."
       Do = { Set-Reg $EXPLORER_ADV 'HideFileExt' 0 } }

    @{ Cat = 'Interface & Explorateur'; Risk = 0
       Label = "Afficher les fichiers et dossiers cachés"
       Desc  = "Rend visibles les éléments masqués (pas les fichiers système protégés)."
       Do = { Set-Reg $EXPLORER_ADV 'Hidden' 1 } }

    @{ Cat = 'Interface & Explorateur'; Risk = 0
       Label = "Ouvrir l'Explorateur sur « Ce PC »"
       Desc  = "Au lieu de l'accès rapide, souvent encombré."
       Do = { Set-Reg $EXPLORER_ADV 'LaunchTo' 1 } }

    @{ Cat = 'Interface & Explorateur'; Risk = 0
       Label = "Supprimer le suffixe « - Raccourci »"
       Desc  = "Les nouveaux raccourcis gardent le nom d'origine."
       Do = {
            Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer' 'link' `
                    ([byte[]](0,0,0,0)) 'Binary'
       } }

    @{ Cat = 'Interface & Explorateur'; Risk = 1
       Label = "Menu contextuel classique (Windows 11)"
       Desc  = "Restaure le clic droit complet sans passer par « Afficher plus d'options ». Redémarre l'Explorateur."
       Do = {
            $k = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'
            New-Item -Path $k -Force | Out-Null
            Set-Item -Path $k -Value '' -Force
            [void]$script:Journal.Add([pscustomobject]@{
                Kind = 'ctxmenu'; Path = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}' })
       } }

    @{ Cat = 'Interface & Explorateur'; Risk = 0
       Label = "Désactiver les widgets / actualités de la barre des tâches"
       Desc  = "Retire le panneau Widgets (Windows 11) ou Actualités et champs d'intérêt (Windows 10)."
       Do = {
            Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0
            Set-Reg $EXPLORER_ADV 'TaskbarDa' 0
            Set-Reg $EXPLORER_ADV 'TaskbarMn' 0
       } }

    @{ Cat = 'Interface & Explorateur'; Risk = 0
       Label = "Désactiver l'accélération / précision du pointeur"
       Desc  = "Mouvement souris 1:1. Fortement recommandé pour les FPS."
       Do = {
            Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseSpeed'      '0' 'String'
            Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseThreshold1' '0' 'String'
            Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseThreshold2' '0' 'String'
       } }

    @{ Cat = 'Interface & Explorateur'; Risk = 0
       Label = "Effets visuels : ajuster pour les performances"
       Desc  = "Coupe animations et ombres, mais garde le lissage des polices (sinon le texte devient illisible)."
       Do = {
            Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 3
            Set-Reg 'HKCU:\Control Panel\Desktop' 'UserPreferencesMask' `
                    ([byte[]](0x90,0x12,0x03,0x80,0x10,0x00,0x00,0x00)) 'Binary'
            Set-Reg 'HKCU:\Control Panel\Desktop' 'FontSmoothing' '2' 'String'
            Set-Reg 'HKCU:\Control Panel\Desktop' 'MenuShowDelay' '0' 'String'
            Set-Reg 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate' '0' 'String'
       } }

    # ---- Jeux ------------------------------------------------------------
    @{ Cat = 'Jeux'; Risk = 0
       Label = "Désactiver la barre de jeu Xbox et le DVR"
       Desc  = "Supprime l'overlay et l'enregistrement en arrière-plan : quelques FPS gagnés."
       Do = {
            Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0
            Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
            Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 0
            Set-Reg 'HKCU:\Software\Microsoft\GameBar' 'UseNexusForGameBarEnabled' 0
       } }

    @{ Cat = 'Jeux'; Risk = 0
       Label = "Activer le Mode Jeu"
       Desc  = "Priorise le jeu au premier plan et repousse les mises à jour pendant les sessions."
       Do = {
            Set-Reg 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled'  1
            Set-Reg 'HKCU:\Software\Microsoft\GameBar' 'AllowAutoGameMode'    1
       } }

    @{ Cat = 'Jeux'; Risk = 1
       Label = "Activer la planification GPU accélérée (HAGS)"
       Desc  = "Réduit la latence sur GPU récents. Nécessite un redémarrage. À désactiver si tu vois des micro-freezes."
       Do = {
            Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2
       } }

    # ---- Alimentation ----------------------------------------------------
    @{ Cat = 'Alimentation'; Risk = 0; Group = 'power'
       Label = "Mode d'alimentation : Performances élevées"
       Desc  = "Le CPU ne descend plus en fréquence au repos. Consommation en hausse."
       Do = { & powercfg.exe /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c | Out-Null } }

    @{ Cat = 'Alimentation'; Risk = 0; Group = 'power'
       Label = "Mode d'alimentation : Équilibré"
       Desc  = "Le réglage par défaut de Windows, le meilleur compromis sur portable."
       Do = { & powercfg.exe /setactive 381b4222-f694-41f0-9685-ff5bb260df2e | Out-Null } }

    @{ Cat = 'Alimentation'; Risk = 1; Group = 'power'
       Label = "Mode d'alimentation : Performances ultimes"
       Desc  = "Plan caché de Windows. À réserver aux tours de bureau branchées sur secteur."
       Do = {
            & powercfg.exe -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 | Out-Null
            & powercfg.exe /setactive e9a42b02-d5df-448d-aa00-03f14749eb61 | Out-Null
       } }

    @{ Cat = 'Alimentation'; Risk = 1
       Label = "Désactiver la mise en veille prolongée"
       Desc  = "Libère plusieurs Go (hiberfil.sys). Attention : supprime aussi le démarrage rapide."
       Do = { & powercfg.exe /hibernate off | Out-Null } }

    @{ Cat = 'Alimentation'; Risk = 1
       Label = "Désactiver le démarrage rapide"
       Desc  = "Recommandé en dual-boot et pour éviter les états système corrompus. Le démarrage sera un peu plus long."
       Do = {
            Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 0
       } }

    # ---- Nettoyage -------------------------------------------------------
    @{ Cat = 'Nettoyage & maintenance'; Risk = 0
       Label = "Nettoyer maintenant les fichiers temporaires"
       Desc  = "Vide %TEMP%, C:\Windows\Temp, le cache Windows Update et les vieux logs CBS."
       Do = { Invoke-Cleanup } }

    @{ Cat = 'Nettoyage & maintenance'; Risk = 0
       Label = "Planifier un nettoyage hebdomadaire silencieux"
       Desc  = "Crée une tâche planifiée (dimanche 12h, sans fenêtre). Bien meilleur choix qu'un nettoyage à chaque démarrage."
       Do = { Register-CleanupTask } }

    @{ Cat = 'Nettoyage & maintenance'; Risk = 1
       Label = "Désactiver la réserve de stockage"
       Desc  = "Récupère ~7 Go réservés aux mises à jour. Celles-ci demanderont de l'espace libre au moment venu."
       Do = { & dism.exe /Online /Set-ReservedStorageState /State:Disabled /Quiet | Out-Null } }

    @{ Cat = 'Nettoyage & maintenance'; Risk = 0
       Label = "Vérifier l'intégrité du système (SFC + DISM)"
       Desc  = "Répare les fichiers système corrompus. Compte 5 à 15 minutes."
       Do = {
            & dism.exe /Online /Cleanup-Image /RestoreHealth | Out-Null
            & sfc.exe /scannow | Out-Null
       } }
)

# ============================================================================
#  4. FONCTIONS DE NETTOYAGE
# ============================================================================
$script:CleanupBody = @'
$ErrorActionPreference   = 'SilentlyContinue'
$WarningPreference       = 'SilentlyContinue'
$ProgressPreference      = 'SilentlyContinue'
$InformationPreference   = 'SilentlyContinue'
$freedBefore = (Get-PSDrive C).Free

Get-ChildItem $env:TEMP -Force | Remove-Item -Recurse -Force
Get-ChildItem "$env:SystemRoot\Temp" -Force | Remove-Item -Recurse -Force
Get-ChildItem "$env:SystemRoot\Logs\CBS" -Filter *.log -Force |
    Where-Object LastWriteTime -lt (Get-Date).AddDays(-7) | Remove-Item -Force
Get-ChildItem "$env:SystemRoot\Minidump" -Force |
    Where-Object LastWriteTime -lt (Get-Date).AddDays(-30) | Remove-Item -Force

Stop-Service wuauserv, bits -Force -WarningAction SilentlyContinue
Get-ChildItem "$env:SystemRoot\SoftwareDistribution\Download" -Force |
    Remove-Item -Recurse -Force
Start-Service wuauserv, bits -WarningAction SilentlyContinue

Delete-DeliveryOptimizationCache -Force *>$null

$freed = [math]::Round((((Get-PSDrive C).Free - $freedBefore) / 1GB), 2)
"$(Get-Date -f 'yyyy-MM-dd HH:mm')  nettoyage termine, $freed Go liberes" |
    Add-Content "$env:LOCALAPPDATA\TweakSean\cleanup.log"
'@

function Invoke-Cleanup {
    $script = Join-Path $script:DataDir 'cleanup.ps1'
    Set-Content -Path $script -Value $script:CleanupBody -Encoding UTF8
    $p = Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -Wait -PassThru `
        -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$script`""
    if ($p.ExitCode -ne 0) {
        [void]$script:StepErrors.Add("nettoyage : code de sortie $($p.ExitCode)")
    }
}

function Register-CleanupTask {
    $script = Join-Path $script:DataDir 'cleanup.ps1'
    Set-Content -Path $script -Value $script:CleanupBody -Encoding UTF8

    $name = 'TweakSean - Nettoyage hebdomadaire'
    Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue

    $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script`""
    $trigger   = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At '12:00'
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable `
                    -DontStopIfGoingOnBatteries -AllowStartIfOnBatteries `
                    -ExecutionTimeLimit (New-TimeSpan -Minutes 30)

    Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger `
        -Principal $principal -Settings $settings `
        -Description 'Nettoyage des fichiers temporaires (TweakSean)' | Out-Null

    [void]$script:Journal.Add([pscustomobject]@{ Kind = 'task'; Name = $name })
}

# ============================================================================
#  5. MOTEUR D'INTERFACE
# ============================================================================
# --- Logotype ------------------------------------------------------------
# Fonte 2 lignes en demi-blocs. Chaque lettre a la MEME largeur sur les deux
# lignes, sinon le mot se decale. S=2  E=3  A=3  N=4  T=3  W=5  K=3
$script:LogoLines = @(
    '█▀ █▀▀ ▄▀█ █▄ █   ▀█▀ █ █ █ █▀▀ ▄▀█ █▄▀',
    '▄█ ██▄ █▀█ █ ▀█    █  ▀▄▀▄▀ ██▄ █▀█ █ █'
)
$script:LogoWidth = $script:LogoLines[0].Length

# --- Reglages de l'animation (les seuls a toucher pour changer la vitesse) ---
$script:LogoStep  = 1                                  # colonnes gagnees par image
$script:LogoEvery = 5                                  # 1 image toutes les N x 12 ms
$script:LogoPause = 60                                 # colonnes de pause entre 2 balayages
# -> reflet a 1 colonne / 60 ms, balayage en ~3,4 s, puis ~2,6 s d'immobilite

$script:LogoCycle = $script:LogoWidth + $script:LogoPause
$script:LogoPhase = 0
$script:LogoCache = @{}                                # phase -> chaine prete a ecrire
$script:LastBlit  = $null                              # derniere image reellement ecrite

<#
    Build-Logo : degrade cyan -> violet avec un reflet clair qui balaie le mot.

    Deux optimisations importantes, car cette fonction produit des milliers de
    caracteres : on n'emet une sequence de couleur que lorsqu'elle change
    reellement (couleurs quantifiees sur 8 niveaux) et jamais sur un espace,
    qui n'a pas d'avant-plan visible. On passe ainsi de 39 sequences par ligne
    a une douzaine.
#>
function Build-Logo {
    param([int]$Phase = -1, [int]$Reveal = -1)

    if (-not $script:VT) { return $script:LogoLines }

    $band = $Phase - 12
    $out  = @()
    foreach ($l in $script:LogoLines) {
        $sb   = New-Object System.Text.StringBuilder 256
        $n    = $l.Length
        $last = if ($Reveal -ge 0) { [Math]::Min($Reveal, $n - 1) } else { $n - 1 }
        $prev = -1

        for ($i = 0; $i -le $last; $i++) {
            $ch = $l[$i]
            if ($ch -eq ' ') { [void]$sb.Append(' '); continue }

            $t = $i / ($n - 1)
            $r = 56  + 83  * $t
            $g = 208 - 84  * $t
            $b = 232 + 14  * $t

            if ($Phase -ge 0) {
                $d = [Math]::Abs($i - $band)
                if ($d -lt 7) {
                    $k = (1 - $d / 7) * 0.85
                    $r = $r + (255 - $r) * $k
                    $g = $g + (255 - $g) * $k
                    $b = $b + (255 - $b) * $k
                }
            }

            $ri = ([int]$r) -band 0xF8
            $gi = ([int]$g) -band 0xF8
            $bi = ([int]$b) -band 0xF8
            $packed = ($ri -shl 16) -bor ($gi -shl 8) -bor $bi
            if ($packed -ne $prev) {
                [void]$sb.Append((Fg $ri $gi $bi))
                $prev = $packed
            }
            [void]$sb.Append($ch)
        }
        $out += $sb.ToString() + $T.Reset
    }
    $out
}

function Get-Logo {
    param([int]$Phase = -1, [int]$Reveal = -1)
    Build-Logo -Phase $Phase -Reveal $Reveal
}

<#
    Get-LogoBlit : chaine unique contenant le positionnement du curseur ET les
    deux lignes. Elle est calculee une seule fois par phase puis servie depuis
    le cache : une image d'animation ne coute plus qu'une lecture de table de
    hachage et un seul appel Console.Write.
#>
function Get-LogoBlit {
    param([int]$Phase)

    # Hors de la zone balayee, l'image est le degrade nu : toutes ces phases
    # partagent la meme entree de cache (cle -1), donc la meme instance de
    # chaine. L'appelant peut alors detecter qu'il n'y a rien a reecrire.
    $band = $Phase - 12
    $key  = if ($band -lt -8 -or $band -gt ($script:LogoWidth + 8)) { -1 } else { $Phase }

    $cached = $script:LogoCache[$key]
    if ($cached) { return $cached }

    $lg = Build-Logo -Phase $key
    $script:LogoCache[$key] = $lg
    $lg
}

function Write-LogoAt {
    param($Blit, [int]$Column)
    for ($i = 0; $i -lt $Blit.Count; $i++) {
        [Console]::SetCursorPosition($Column, 1 + $i)
        [Console]::Write($Blit[$i])
    }
}

function Show-Intro {
    if (-not $script:VT) { return }
    try { [Console]::CursorVisible = $false } catch { }
    Clear-Host

    for ($i = 0; $i -lt $script:LogoWidth; $i += 3) {
        Write-LogoAt (Build-Logo -Reveal $i) 4
        [System.Threading.Thread]::Sleep(10)
    }
    for ($p = 0; $p -le ($script:LogoWidth + 14); $p += 2) {
        Write-LogoAt (Get-LogoBlit $p) 4
        [System.Threading.Thread]::Sleep(22)
    }
}

function Get-RiskDot([int]$risk) {
    switch ($risk) {
        0 { "$($T.Ok)•$($T.Reset)" }
        1 { "$($T.Warn)•$($T.Reset)" }
        default { "$($T.Bad)•$($T.Reset)" }
    }
}

function Get-VisibleIndexes {
    param($Rows)
    $vis = New-Object System.Collections.ArrayList
    $hdr = $null
    for ($i = 0; $i -lt $Rows.Count; $i++) {
        if ($Rows[$i].Type -eq 'Header') { $hdr = $Rows[$i]; [void]$vis.Add($i) }
        elseif (-not ($hdr -and $hdr.Collapsed)) { [void]$vis.Add($i) }
    }
    , $vis
}

function Get-SectionStats {
    param($Rows, [int]$HeaderIndex)
    $total = 0; $checked = 0
    for ($i = $HeaderIndex + 1; $i -lt $Rows.Count; $i++) {
        if ($Rows[$i].Type -eq 'Header') { break }
        $total++
        if ($Rows[$i].Action)  { continue }
        if ($Rows[$i].Checked) { $checked++ }
    }
    @{ Total = $total; Checked = $checked }
}

function Join-Sides {
    param([string]$Left, [string]$Right, [int]$Width)
    $gap = $Width - (Visible-Length $Left) - (Visible-Length $Right)
    if ($gap -lt 1) { return $Left }
    $Left + (' ' * $gap) + $Right
}

<#
    Show-CheckList : moteur d'affichage reutilise par le menu principal
    et par tous les sous-menus.

    Rows = objets { Type = 'Header'|'Item'; Text; Desc; Checked; Risk; Group;
                    Action; Tag; Collapsed }
    Retourne @{ Action = 'apply'|'quit'; Rows = ... }
#>
function Show-CheckList {
    param(
        [Parameter(Mandatory)][System.Collections.IList]$Rows,
        [string]$Title      = '',
        [string]$Subtitle   = '',
        [string]$ApplyLabel = 'appliquer',
        [switch]$NoLogo
    )

    $MARGIN = 4

    # les Header crees ailleurs n'ont pas forcement la propriete Collapsed :
    # sur un PSCustomObject, ecrire une propriete absente leve une exception.
    foreach ($r in $Rows) {
        if ($r.Type -eq 'Header' -and $r.PSObject.Properties.Name -notcontains 'Collapsed') {
            Add-Member -InputObject $r -NotePropertyName Collapsed -NotePropertyValue $false -Force
        }
    }

    # selection initiale : premier element reel
    $sel = 0
    while ($sel -lt $Rows.Count -and $Rows[$sel].Type -ne 'Item') { $sel++ }
    if ($sel -ge $Rows.Count) { $sel = 0 }

    $top = 0
    $prevCursor = $true
    try { $prevCursor = [Console]::CursorVisible } catch { }
    [Console]::CursorVisible = $false
    Clear-Host

    try {
        while ($true) {
            $rawW = [Console]::WindowWidth
            $rawH = [Console]::WindowHeight
            $H  = $rawH

            if ($rawW -lt 56 -or $rawH -lt 16) {
                Clear-Host
                Write-Host ''
                Write-Host "  Fenetre trop petite ($rawW x $rawH)." -ForegroundColor Yellow
                Write-Host "  Agrandis-la : il faut au moins 56 colonnes sur 16 lignes." -ForegroundColor DarkGray
                while ([Console]::WindowWidth -lt 56 -or [Console]::WindowHeight -lt 16) {
                    if ([Console]::KeyAvailable) {
                        if ([string][Console]::ReadKey($true).Key -in 'Q', 'Escape') { return @{ Action = 'quit' } }
                    }
                    [System.Threading.Thread]::Sleep(120)
                }
                Sync-ConsoleBuffer
                Clear-Host
                $script:LastBlit = $null
                continue
            }

            # plus de plancher a 64 : au-dela de la largeur reelle, les lignes
            # deborderaient et se replieraient, ce qui decale tout l'ecran
            $W = [Math]::Min($rawW - 1, 110)
            $CW = $W - (2 * $MARGIN)          # largeur utile du contenu
            $pad = ' ' * $MARGIN

            $vis = Get-VisibleIndexes $Rows
            if ($vis.IndexOf($sel) -lt 0 -and $vis.Count -gt 0) { $sel = $vis[0] }

            # ---------- en-tete ----------
            $head = New-Object System.Collections.ArrayList
            [void]$head.Add('')
            if (-not $NoLogo) {
                foreach ($l in (Get-Logo -Phase $script:LogoPhase)) { [void]$head.Add($pad + $l) }
                [void]$head.Add('')
                [void]$head.Add("$pad$($T.Faint)optimisation windows  ·  v2.0$($T.Reset)")
                [void]$head.Add('')
            }
            if ($Title)    { [void]$head.Add("$pad$($T.Bold)$($T.Text)$Title$($T.Reset)") }
            if ($Subtitle) { [void]$head.Add("$pad$($T.Faint)$Subtitle$($T.Reset)") }
            [void]$head.Add('')

            # ---------- corps : construction des lignes ----------
            $render = New-Object System.Collections.ArrayList   # @{ Text; Row = index|-1 }
            $first = $true
            foreach ($idx in $vis) {
                $r = $Rows[$idx]

                if ($r.Type -eq 'Header') {
                    if (-not $first) { [void]$render.Add(@{ Text = ''; Row = -1 }) }
                    $first = $false

                    $st    = Get-SectionStats $Rows $idx
                    $arrow = if ($r.Collapsed) { '►' } else { '▼' }
                    $isSel = ($idx -eq $sel)
                    $tint  = if ($isSel) { $T.Cyan } else { $T.Accent }

                    $left  = "$pad$tint$arrow  $($T.Bold)$($r.Text.ToUpper())$($T.Reset)"
                    $right = if ($st.Total -eq 0) { '' }
                             elseif ($st.Checked -gt 0) { "$($T.Cyan)$($st.Checked)$($T.Faint)/$($st.Total)$($T.Reset)" }
                             else { "$($T.Faint)$($st.Total)$($T.Reset)" }

                    $used = (Visible-Length $left) + (Visible-Length $right)
                    $rule = if ($right) { $CW + $MARGIN - $used - 2 } else { $CW + $MARGIN - $used }
                    if ($rule -lt 1) { $rule = 1 }
                    $line = $left + ' ' + "$($T.Faint)$('─' * ($rule - 1))$($T.Reset)" + ' ' + $right

                    [void]$render.Add(@{ Text = $line; Row = $idx })
                    continue
                }

                $first = $false
                $isSel = ($idx -eq $sel)
                $bar   = if ($isSel) { "$($T.Accent)▌$($T.Reset)" } else { ' ' }

                if ($r.Action)      { $box = "$($T.Cyan)►$($T.Reset)" }
                elseif ($r.Checked) { $box = "$($T.Cyan)■$($T.Reset)" }
                else                { $box = "$($T.Faint)·$($T.Reset)" }

                $txt = if ($isSel) { $T.Bold + $T.Text }
                       elseif ($r.Checked -or $r.Action) { $T.Text }
                       else { $T.Dim }

                $left  = "$pad$bar  $box  $txt$($r.Text)$($T.Reset)"
                $right = if ($null -ne $r.Risk -and $r.Risk -gt 0) { (Get-RiskDot $r.Risk) + ' ' } else { '' }
                $line  = Join-Sides $left $right ($W - 2)

                if ($isSel) { $line = $T.SelBg + (Pad-To $line ($W - 2)) + $T.Reset }
                [void]$render.Add(@{ Text = $line; Row = $idx })
            }

            # ---------- pied ----------
            $cur  = if ($sel -lt $Rows.Count) { $Rows[$sel] } else { $null }
            $desc = if ($cur -and $cur.Type -eq 'Header') {
                        $st = Get-SectionStats $Rows $sel
                        "Rubrique de $($st.Total) option(s). Espace ou ← → pour la replier."
                    } elseif ($cur -and $cur.Desc) { $cur.Desc } else { '' }

            $checked = @($Rows | Where-Object { $_.Type -eq 'Item' -and $_.Checked }).Count
            $dl = @(Wrap-Text $desc $CW)

            $foot = New-Object System.Collections.ArrayList
            [void]$foot.Add('')
            [void]$foot.Add("$pad$($T.Faint)$('─' * $CW)$($T.Reset)")
            [void]$foot.Add('')
            [void]$foot.Add("$pad$($T.Text)$($dl[0])$($T.Reset)")
            [void]$foot.Add("$pad$($T.Text)$(if ($dl.Count -gt 1) { $dl[1] } else { '' })$($T.Reset)")
            [void]$foot.Add('')
            $keys = "$pad$($T.Faint)↑↓$($T.Reset) naviguer    " +
                    "$($T.Faint)espace$($T.Reset) cocher    " +
                    "$($T.Faint)←→$($T.Reset) replier    " +
                    "$($T.Faint)T$($T.Reset) tout    " +
                    "$($T.Faint)A$($T.Reset) $ApplyLabel    " +
                    "$($T.Faint)Q$($T.Reset) quitter"
            $count = if ($checked -gt 0) { "$($T.Cyan)$checked sélection(s)$($T.Reset)" } else { "$($T.Faint)aucune sélection$($T.Reset)" }
            [void]$foot.Add((Join-Sides $keys $count ($W - 2)))
            [void]$foot.Add('')

            # ---------- fenetre de defilement ----------
            $viewport = [Math]::Max(6, $H - $head.Count - $foot.Count - 1)
            $viewport = [Math]::Min($viewport, $render.Count)

            $selLine = 0
            for ($i = 0; $i -lt $render.Count; $i++) { if ($render[$i].Row -eq $sel) { $selLine = $i; break } }

            if ($selLine -lt $top + 1)             { $top = $selLine - 1 }
            if ($selLine -gt $top + $viewport - 2) { $top = $selLine - $viewport + 2 }
            if ($top -gt $render.Count - $viewport) { $top = $render.Count - $viewport }
            if ($top -lt 0) { $top = 0 }

            $scrollable = $render.Count -gt $viewport
            $thumbSize  = if ($scrollable) { [Math]::Max(1, [int]($viewport * $viewport / $render.Count)) } else { 0 }
            $thumbPos   = if ($scrollable -and ($render.Count - $viewport) -gt 0) {
                              [int](($viewport - $thumbSize) * $top / ($render.Count - $viewport))
                          } else { 0 }

            $body = New-Object System.Collections.ArrayList
            for ($i = 0; $i -lt $viewport; $i++) {
                $line = $render[$top + $i].Text
                if ($scrollable) {
                    $mark = if ($i -ge $thumbPos -and $i -lt $thumbPos + $thumbSize) {
                                "$($T.Accent)│$($T.Reset)"
                            } else { "$($T.Faint)│$($T.Reset)" }
                    $line = (Pad-To $line ($W - 2)) + $mark
                }
                [void]$body.Add($line)
            }

            # ---------- rendu ----------
            $frame = New-Object System.Text.StringBuilder
            foreach ($l in @($head) + @($body) + @($foot)) { [void]$frame.AppendLine((Pad-To $l $W)) }
            $used = $head.Count + $body.Count + $foot.Count
            for ($i = $used; $i -lt $H - 1; $i++) { [void]$frame.AppendLine((' ' * $W)) }

            [Console]::SetCursorPosition(0, 0)
            [Console]::Write($frame.ToString())
            $script:LastBlit = $null

            # ---------- clavier ----------
            # Attente non bloquante : tant qu'aucune touche n'arrive, on ne redessine
            # que les deux lignes du logo. Le reste de l'ecran ne bouge pas, donc
            # aucun scintillement et un cout CPU negligeable.
            # On sonde le clavier toutes les 12 ms pour rester reactif. La meme
            # boucle surveille un redimensionnement de la fenetre : si les
            # dimensions changent, on sort sans touche pour tout recalculer,
            # sinon on continuerait a ecrire a des coordonnees perimees.
            $key  = $null
            $tick = 0
            $animate = (-not $NoLogo) -and $script:VT
            while ($true) {
                if ([Console]::KeyAvailable) { $key = [Console]::ReadKey($true); break }
                if ([Console]::WindowWidth -ne $rawW -or [Console]::WindowHeight -ne $rawH) { break }

                if ($animate -and (($tick++ % $script:LogoEvery) -eq 0)) {
                    $script:LogoPhase = ($script:LogoPhase + $script:LogoStep) % $script:LogoCycle
                    $blit = Get-LogoBlit $script:LogoPhase
                    if (-not [object]::ReferenceEquals($blit, $script:LastBlit)) {
                        try { Write-LogoAt $blit $MARGIN } catch { }
                        $script:LastBlit = $blit
                    }
                }
                [System.Threading.Thread]::Sleep(12)
            }

            if ($null -eq $key) {
                # redimensionnement : on garde la taille choisie par l'utilisateur,
                # on realigne juste le buffer et on repart d'un ecran propre
                Sync-ConsoleBuffer
                Clear-Host
                $script:LastBlit = $null
                continue
            }
            $p   = $vis.IndexOf($sel)

            switch ([string]$key.Key) {
                'UpArrow'   { $sel = $vis[(($p - 1 + $vis.Count) % $vis.Count)] }
                'DownArrow' { $sel = $vis[(($p + 1) % $vis.Count)] }
                'PageUp'    { $sel = $vis[[Math]::Max(0, $p - 8)] }
                'PageDown'  { $sel = $vis[[Math]::Min($vis.Count - 1, $p + 8)] }
                'Home'      { $sel = $vis[0] }
                'End'       { $sel = $vis[$vis.Count - 1] }

                'LeftArrow' {
                    $r = $Rows[$sel]
                    if ($r.Type -eq 'Header') { $r.Collapsed = $true }
                    else {
                        for ($i = $sel; $i -ge 0; $i--) {
                            if ($Rows[$i].Type -eq 'Header') { $Rows[$i].Collapsed = $true; $sel = $i; break }
                        }
                    }
                }
                'RightArrow' {
                    if ($Rows[$sel].Type -eq 'Header') { $Rows[$sel].Collapsed = $false }
                }

                { $_ -in 'Spacebar', 'Enter' } {
                    $r = $Rows[$sel]
                    if ($r.Type -eq 'Header') {
                        $r.Collapsed = -not $r.Collapsed
                    } elseif ($r.Action) {
                        [Console]::CursorVisible = $true
                        Clear-Host
                        & $r.Action
                        Clear-Host
                        [Console]::CursorVisible = $false
                    } else {
                        $r.Checked = -not $r.Checked
                        if ($r.Checked -and $r.Group) {
                            foreach ($o in $Rows) {
                                if ($o -ne $r -and $o.Group -eq $r.Group) { $o.Checked = $false }
                            }
                        }
                    }
                }

                'C' { $st = -not ($Rows | Where-Object { $_.Type -eq 'Header' -and $_.Collapsed })
                      foreach ($r in $Rows) { if ($r.Type -eq 'Header') { $r.Collapsed = $st } } }

                'T' {
                    $any = @($Rows | Where-Object { $_.Type -eq 'Item' -and -not $_.Action -and $_.Checked }).Count -gt 0
                    foreach ($r in $Rows) {
                        if ($r.Type -eq 'Item' -and -not $r.Action -and -not $r.Group) { $r.Checked = -not $any }
                    }
                }

                'A'      { return @{ Action = 'apply'; Rows = $Rows } }
                'Q'      { return @{ Action = 'quit' } }
                'Escape' { return @{ Action = 'quit' } }
            }
        }
    } finally {
        try { [Console]::CursorVisible = $prevCursor } catch { }
    }
}


# ============================================================================
#  6. SOUS-MENUS
# ============================================================================
function Show-StartupManager {
    $rows = New-Object System.Collections.ArrayList
    $keys = @(
        @{ Run = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; Scope = 'Système' }
        @{ Run = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'; Scope = 'Utilisateur' }
    )

    [void]$rows.Add([pscustomobject]@{ Type = 'Header'; Text = 'Applications au démarrage' })
    foreach ($k in $keys) {
        if (-not (Test-Path $k.Run)) { continue }
        $props = Get-ItemProperty -Path $k.Run
        foreach ($p in $props.PSObject.Properties) {
            if ($p.Name -like 'PS*') { continue }
            [void]$rows.Add([pscustomobject]@{
                Type = 'Item'; Text = "$($p.Name)  $($T.Faint)($($k.Scope))$($T.Reset)"
                Desc = "$($p.Value)" ; Checked = $false; Risk = 0
                Tag  = @{ Path = $k.Run; Name = $p.Name }
            })
        }
    }

    if ($rows.Count -le 1) {
        Write-Host "`n  Aucune entrée de démarrage trouvée dans le registre." -ForegroundColor Yellow
        Read-Host "`n  Entrée pour revenir"
        return
    }

    $res = Show-CheckList -Rows $rows -NoLogo `
        -Title 'Démarrage automatique' `
        -Subtitle 'Coche les entrées à SUPPRIMER du démarrage, puis A.' `
        -ApplyLabel 'supprimer'

    if ($res.Action -ne 'apply') { return }
    foreach ($r in $res.Rows) {
        if ($r.Type -eq 'Item' -and $r.Checked) {
            try {
                [void]$script:Journal.Add([pscustomobject]@{
                    Kind = 'reg'; Path = $r.Tag.Path; Name = $r.Tag.Name
                    Existed = $true; Old = $r.Desc; New = $null; Type = 'String'
                })
                Remove-ItemProperty -Path $r.Tag.Path -Name $r.Tag.Name -Force
                Write-Log "STARTUP supprime: $($r.Tag.Name)"
            } catch { }
        }
    }
}

function Show-AppManager {
    Clear-Host
    Write-Host "`n  Lecture des applications installées..." -ForegroundColor DarkGray

    $rows = New-Object System.Collections.ArrayList
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $classic = Get-ItemProperty $paths -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -and -not $_.SystemComponent -and -not $_.ReleaseType } |
        Sort-Object DisplayName -Unique

    $appx = Get-AppxPackage | Where-Object {
        -not $_.IsFramework -and -not $_.NonRemovable -and $_.SignatureKind -ne 'System'
    } | Sort-Object Name

    [void]$rows.Add([pscustomobject]@{ Type = 'Header'; Text = 'Applications du Store' })
    foreach ($a in $appx) {
        [void]$rows.Add([pscustomobject]@{
            Type = 'Item'; Text = $a.Name; Checked = $false; Risk = 1
            Desc = "Paquet $($a.PackageFullName) — désinstallation directe."
            Tag  = @{ Kind = 'appx'; Obj = $a }
        })
    }

    [void]$rows.Add([pscustomobject]@{ Type = 'Header'; Text = 'Programmes classiques' })
    foreach ($a in $classic) {
        [void]$rows.Add([pscustomobject]@{
            Type = 'Item'; Text = $a.DisplayName; Checked = $false; Risk = 1
            Desc = "$($a.Publisher) — ouvre le désinstalleur du programme."
            Tag  = @{ Kind = 'classic'; Cmd = $a.UninstallString }
        })
    }

    $res = Show-CheckList -Rows $rows -NoLogo `
        -Title 'Applications installées' `
        -Subtitle 'Coche ce que tu veux désinstaller, puis A.' `
        -ApplyLabel 'désinstaller'

    if ($res.Action -ne 'apply') { return }
    Clear-Host
    foreach ($r in $res.Rows) {
        if ($r.Type -ne 'Item' -or -not $r.Checked) { continue }
        Write-Host (Format-Step $r.Text 'en cours' $T.Dim) -NoNewline
        try {
            if ($r.Tag.Kind -eq 'appx') {
                Remove-AppxPackage -Package $r.Tag.Obj.PackageFullName -ErrorAction Stop
            } else {
                $cmd = $r.Tag.Cmd
                if ($cmd -match '^\s*(msiexec.*)$') {
                    Start-Process 'cmd.exe' -ArgumentList '/c', $cmd -Wait
                } else {
                    Start-Process 'cmd.exe' -ArgumentList '/c', "`"$cmd`"" -Wait
                }
            }
            Write-Host ("`r" + (Format-Step $r.Text 'ok' $T.Ok))
        } catch {
            Write-Host ("`r" + (Format-Step $r.Text 'échec' $T.Bad))
            Write-Host ("      " + $T.Faint + $_.Exception.Message + $T.Reset)
        }
    }
    Read-Host "`n  Entrée pour revenir"
}

$script:ServiceCatalog = @(
    @{ N = 'DiagTrack';        L = 'Expériences des utilisateurs connectés'; D = 'Télémétrie principale de Windows.'; R = 0 }
    @{ N = 'dmwappushservice'; L = 'Routage de messages WAP Push';           D = 'Composant de télémétrie.'; R = 0 }
    @{ N = 'diagnosticshub.standardcollector.service'; L = 'Collecteur Diagnostics Hub'; D = 'Collecte de diagnostics.'; R = 0 }
    @{ N = 'WerSvc';           L = "Rapport d'erreurs Windows";              D = "Envoi des rapports de plantage à Microsoft."; R = 0 }
    @{ N = 'wisvc';            L = 'Service Windows Insider';                D = "Inutile hors programme Insider."; R = 0 }
    @{ N = 'RetailDemo';       L = 'Démo de magasin';                        D = 'Mode démo des PC en magasin.'; R = 0 }
    @{ N = 'WalletService';    L = 'Portefeuille';                           D = 'Portefeuille Microsoft, peu utilisé.'; R = 0 }
    @{ N = 'MapsBroker';       L = 'Cartes téléchargées';                    D = 'Uniquement si tu utilises les cartes hors ligne.'; R = 0 }
    @{ N = 'lfsvc';            L = 'Service de géolocalisation';             D = 'Coupe la localisation système.'; R = 1 }
    @{ N = 'Fax';              L = 'Télécopie';                              D = 'On est en 2026.'; R = 0 }
    @{ N = 'RemoteRegistry';   L = 'Registre à distance';                    D = 'Doit rester désactivé pour la sécurité.'; R = 0 }
    @{ N = 'SharedAccess';     L = 'Partage de connexion Internet';          D = 'Desactive si tu ne fais pas de point d''acces.'; R = 1 }
    @{ N = 'PcaSvc';           L = 'Assistant Compatibilité';                D = 'Peut casser les vieux installeurs.'; R = 1 }
    @{ N = 'DoSvc';            L = 'Optimisation de la distribution';        D = 'P2P des mises à jour. Économise de la bande passante.'; R = 1 }
    @{ N = 'XblAuthManager';   L = 'Xbox Live : authentification';           D = 'À garder si tu joues au Game Pass.'; R = 1 }
    @{ N = 'XblGameSave';      L = 'Xbox Live : sauvegardes';                D = 'À garder si tu joues au Game Pass.'; R = 1 }
    @{ N = 'XboxNetApiSvc';    L = 'Xbox Live : réseau';                     D = 'À garder si tu joues au Game Pass.'; R = 1 }
    @{ N = 'Spooler';          L = "Spouleur d'impression";                  D = "À désactiver UNIQUEMENT sans imprimante."; R = 2 }
    @{ N = 'WSearch';          L = 'Windows Search';                         D = "Casse la recherche de fichiers et Outlook. Déconseillé."; R = 2 }
    @{ N = 'SysMain';          L = 'SysMain (SuperFetch)';                   D = "Sur SSD l'impact est nul, sur HDD ça dégrade. Déconseillé."; R = 2 }
)

function Show-ServiceManager {
    $rows = New-Object System.Collections.ArrayList
    [void]$rows.Add([pscustomobject]@{ Type = 'Header'; Text = 'Services à désactiver' })

    foreach ($s in $script:ServiceCatalog) {
        $svc = Get-Service -Name $s.N -ErrorAction SilentlyContinue
        if (-not $svc) { continue }
        $mode = (Get-CimInstance Win32_Service -Filter "Name='$($s.N)'").StartMode
        if ($mode -eq 'Disabled') { continue }
        [void]$rows.Add([pscustomobject]@{
            Type = 'Item'; Text = $s.L; Checked = $false; Risk = $s.R
            Desc = "$($s.D)  [$($s.N)] — actuellement : $mode"
            Tag  = $s.N
        })
    }

    if ($rows.Count -le 1) {
        Write-Host "`n  Tous les services de la liste sont déjà désactivés." -ForegroundColor Green
        Read-Host "`n  Entrée pour revenir"
        return
    }

    $res = Show-CheckList -Rows $rows -NoLogo `
        -Title 'Services Windows' `
        -Subtitle ("pas de pastille = sans risque    $($T.Warn)•$($T.Faint) à évaluer    $($T.Bad)•$($T.Faint) déconseillé") `
        -ApplyLabel 'désactiver'

    if ($res.Action -ne 'apply') { return }
    foreach ($r in $res.Rows) {
        if ($r.Type -eq 'Item' -and $r.Checked) {
            try { Set-Svc $r.Tag 'Disabled' } catch { }
        }
    }
}

function Show-Restore {
    Clear-Host
    if (-not (Test-Path $script:JournalPath)) {
        Write-Host "`n  Aucune modification enregistrée." -ForegroundColor Yellow
        Read-Host "`n  Entrée pour revenir"; return
    }
    $entries = @(Get-Content $script:JournalPath -Raw | ConvertFrom-Json)
    Write-Host "`n  $($entries.Count) modification(s) enregistrée(s)." -ForegroundColor Cyan
    $ans = Read-Host "  Tout restaurer ? (o/N)"
    if ($ans -notmatch '^[oOyY]') { return }

    $ok = 0
    foreach ($e in $entries) {
        try {
            switch ($e.Kind) {
                'reg' {
                    if ($e.Existed) {
                        New-ItemProperty -Path $e.Path -Name $e.Name -Value $e.Old `
                            -PropertyType $e.Type -Force | Out-Null
                    } else {
                        Remove-ItemProperty -Path $e.Path -Name $e.Name -Force -ErrorAction SilentlyContinue
                    }
                }
                'svc'  { if ($e.Old) { Set-Service -Name $e.Name -StartupType ($e.Old -replace '^Auto$', 'Automatic') } }
                'ctxmenu' { Remove-Item -Path $e.Path -Recurse -Force -ErrorAction SilentlyContinue }
                'task' { Unregister-ScheduledTask -TaskName $e.Name -Confirm:$false -ErrorAction SilentlyContinue }
            }
            $ok++
        } catch { }
    }
    Remove-Item $script:JournalPath -Force -ErrorAction SilentlyContinue
    Write-Host "  $ok élément(s) restauré(s). Redémarre pour finaliser." -ForegroundColor Green
    Read-Host "`n  Entrée pour revenir"
}

# ============================================================================
#  7. APPLICATION
# ============================================================================
function New-RestorePoint {
    try {
        Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' `
                'SystemRestorePointCreationFrequency' 0
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description 'Avant TweakSean' -RestorePointType 'MODIFY_SETTINGS'
        return $true
    } catch { return $false }
}

# Largeur de la colonne "libelle" de l'ecran d'application
$script:StepWidth = 60

function Format-Step {
    param([string]$Label, [string]$Status, [string]$Color)
    $lbl = $Label
    if ($lbl.Length -gt $script:StepWidth - 4) {
        $lbl = $lbl.Substring(0, $script:StepWidth - 7) + '...'
    }
    $dots = $script:StepWidth - $lbl.Length - 1
    if ($dots -lt 1) { $dots = 1 }
    # le statut est complete a 12 caracteres pour effacer un statut precedent
    # plus long ("en cours") lors de la reecriture de la ligne
    '    ' + $T.Text + $lbl + ' ' + $T.Faint + ('.' * $dots) + $T.Reset + ' ' +
        $Color + $Status.PadRight(12) + $T.Reset
}

function Write-Rule {
    param([int]$Width = 72)
    Write-Host ('    ' + $T.Faint + ('─' * $Width) + $T.Reset)
}

function Invoke-Apply {
    param([System.Collections.IList]$Rows)

    $todo = @($Rows | Where-Object { $_.Type -eq 'Item' -and $_.Checked -and $_.Do })
    if ($todo.Count -eq 0) { return }

    Clear-Host
    Write-Host ''
    Write-Host ("    " + $T.Accent + '▌' + $T.Reset + ' ' + $T.Bold + $T.Text + 'APPLICATION' + $T.Reset)
    Write-Host ''
    Write-Host ("    " + $T.Dim + "$($todo.Count) optimisation(s) sélectionnée(s)" + $T.Reset)
    Write-Host ''
    Write-Rule
    Write-Host ''

    # ---- point de restauration ----
    Write-Host ("    " + $T.Text + "Créer un point de restauration d'abord ? " +
                $T.Faint + "[O/n] " + $T.Reset) -NoNewline
    $ans = Read-Host
    if ($ans -notmatch '^[nN]') {
        Write-Host (Format-Step 'Point de restauration' 'en cours' $T.Dim) -NoNewline
        if (New-RestorePoint) {
            Write-Host ("`r" + (Format-Step 'Point de restauration' 'créé' $T.Ok))
        } else {
            Write-Host ("`r" + (Format-Step 'Point de restauration' 'indisponible' $T.Warn))
            Write-Host ("      " + $T.Faint + 'la protection système est désactivée sur ce PC' + $T.Reset)
        }
    }
    Write-Host ''

    # ---- application ----
    $ok = 0; $partial = 0; $ko = 0
    $i  = 0

    foreach ($t in $todo) {
        $i++
        $script:StepErrors.Clear()

        # certains tweaks sont longs : on previent avant de lancer
        $long = $t.Text -match 'intégrité|temporaires|réserve'
        $hint = if ($long) { 'en cours...' } else { 'en cours' }
        Write-Host (Format-Step "$i. $($t.Text)" $hint $T.Dim) -NoNewline

        try {
            # toutes les sorties parasites des cmdlets appelees sont avalees :
            # sans ca, un Write-Host interne casse l'alignement des colonnes
            & $t.Do *>&1 | Out-Null

            if ($script:StepErrors.Count -gt 0) {
                Write-Host ("`r" + (Format-Step "$i. $($t.Text)" 'partiel' $T.Warn))
                foreach ($e in $script:StepErrors) {
                    Write-Host ("      " + $T.Faint + $e + $T.Reset)
                }
                $partial++
            } else {
                Write-Host ("`r" + (Format-Step "$i. $($t.Text)" 'ok' $T.Ok))
                $ok++
            }
        } catch {
            Write-Host ("`r" + (Format-Step "$i. $($t.Text)" 'échec' $T.Bad))
            Write-Host ("      " + $T.Faint + $_.Exception.Message + $T.Reset)
            Write-Log "ERREUR [$($t.Text)] $($_.Exception.Message)"
            $ko++
        }
    }

    Save-Journal

    # ---- resume ----
    Write-Host ''
    Write-Rule
    Write-Host ''
    $summary = "    $($T.Ok)$ok réussie(s)$($T.Reset)"
    if ($partial -gt 0) { $summary += "   $($T.Dim)·$($T.Reset)   $($T.Warn)$partial partielle(s)$($T.Reset)" }
    if ($ko -gt 0)      { $summary += "   $($T.Dim)·$($T.Reset)   $($T.Bad)$ko échec(s)$($T.Reset)" }
    Write-Host $summary
    Write-Host ("    " + $T.Faint + "journal : $($script:LogPath)" + $T.Reset)
    if ($partial -gt 0 -or $ko -gt 0) {
        Write-Host ("    " + $T.Faint +
                    "un réglage refusé vient presque toujours d'une protection antivirus" + $T.Reset)
    }
    Write-Host ''

    Write-Host ("    " + $T.Text + "Redémarrer l'Explorateur pour appliquer l'affichage ? " +
                $T.Faint + "[O/n] " + $T.Reset) -NoNewline
    $ans = Read-Host
    if ($ans -notmatch '^[nN]') {
        Write-Host (Format-Step 'Redémarrage de l''Explorateur' 'en cours' $T.Dim) -NoNewline
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 800
        if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) {
            Start-Process explorer.exe
        }
        Write-Host ("`r" + (Format-Step 'Redémarrage de l''Explorateur' 'ok' $T.Ok))
    }

    Write-Host ''
    Write-Host ("    " + $T.Faint + 'Entrée pour revenir au menu' + $T.Reset) -NoNewline
    [void][Console]::ReadLine()
}


# ============================================================================
#  8. MENU PRINCIPAL
# ============================================================================
function Build-MainRows {
    $rows = New-Object System.Collections.ArrayList
    $lastCat = $null
    foreach ($t in $script:Tweaks) {
        if ($t.Cat -ne $lastCat) {
            [void]$rows.Add([pscustomobject]@{ Type = 'Header'; Text = $t.Cat })
            $lastCat = $t.Cat
        }
        [void]$rows.Add([pscustomobject]@{
            Type = 'Item'; Text = $t.Label; Desc = $t.Desc
            Checked = $false; Risk = $t.Risk; Group = $t.Group; Do = $t.Do
        })
    }

    [void]$rows.Add([pscustomobject]@{ Type = 'Header'; Text = 'Outils interactifs' })
    [void]$rows.Add([pscustomobject]@{ Type = 'Item'; Text = 'Gérer les applications au démarrage'
        Desc = "Liste les programmes lancés au démarrage et permet d'en retirer."
        Action = { Show-StartupManager } })
    [void]$rows.Add([pscustomobject]@{ Type = 'Item'; Text = 'Désinstaller des applications'
        Desc = 'Programmes classiques et applications du Store, en sélection multiple.'
        Action = { Show-AppManager } })
    [void]$rows.Add([pscustomobject]@{ Type = 'Item'; Text = 'Désactiver des services Windows'
        Desc = 'Télémétrie, Xbox, Insider, Wallet... avec le niveau de risque de chacun.'
        Action = { Show-ServiceManager } })
    [void]$rows.Add([pscustomobject]@{ Type = 'Item'; Text = 'Annuler les modifications précédentes'
        Desc = "Restaure les valeurs enregistrées avant les tweaks appliqués par TweakSean."
        Action = { Show-Restore } })

    $rows
}

Show-Intro

$rows = Build-MainRows
while ($true) {
    $res = Show-CheckList -Rows $rows `
        -Title 'Sélectionne les optimisations à appliquer' `
        -Subtitle ("pas de pastille = sans risque    " +
                   "$($T.Warn)•$($T.Faint) à évaluer, lis la description    " +
                   "$($T.Bad)•$($T.Faint) déconseillé")

    if ($res.Action -eq 'quit') { break }
    if ($res.Action -eq 'apply') {
        Invoke-Apply -Rows $res.Rows
        foreach ($r in $rows) { if ($r.Type -eq 'Item') { $r.Checked = $false } }
    }
}

Clear-Host
Write-Host ''
$bye = Get-Logo
foreach ($l in $bye) { Write-Host "  $l" }
Write-Host ''
Write-Host "  $($T.Dim)À bientôt.$($T.Reset)"
Write-Host ''
