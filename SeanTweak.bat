@echo off
setlocal
chcp 65001 >nul
title Sean Tweak
cd /d "%~dp0"

rem  ASCII pur volontairement : les caracteres de dessin Unicode combines a
rem  "chcp 65001" desynchronisent l'analyseur de cmd, qui se met alors a
rem  executer les lignes du logo comme des commandes. La couleur passe par
rem  des sequences ANSI, pas par des caracteres speciaux.

rem  Recupere le caractere ESC (0x1B) pour les sequences ANSI
for /f %%a in ('echo prompt $E ^| cmd') do set "E=%%a"

rem  Meme palette que Optimisation-Windows.ps1
set "ACC=%E%[38;2;139;124;246m"
set "CYA=%E%[38;2;56;208;232m"
set "TXT=%E%[38;2;226;232;240m"
set "DIM=%E%[38;2;152;160;178m"
set "FNT=%E%[38;2;98;107;126m"
set "WRN=%E%[38;2;250;204;21m"
set "BAD=%E%[38;2;248;113;113m"
set "OKC=%E%[38;2;74;222;128m"
set "B=%E%[1m"
set "R=%E%[0m"
rem  masquage / retablissement du curseur clignotant
set "HID=%E%[?25l"
set "SHW=%E%[?25h"

if not exist "%~dp0Optimisation-Windows.ps1" (
    cls
    echo.
    echo   %BAD%%B%^|%R%  %TXT%FICHIER MANQUANT%R%
    echo.
    echo   %DIM%Optimisation-Windows.ps1 est introuvable dans ce dossier.%R%
    echo   %DIM%Garde SeanTweak.bat et Optimisation-Windows.ps1 cote a cote,%R%
    echo   %DIM%exactement comme dans l'archive téléchargée.%R%
    echo.
    echo   %FNT%Appuie sur une touche pour fermer.%R%%HID%
    pause >nul
    echo %SHW%
    exit /b 1
)

rem  Test d'elevation : fltmc echoue si on n'est pas administrateur
fltmc >nul 2>&1
if %errorlevel% equ 0 goto run

cls
echo.
echo   %ACC%%B%SEAN TWEAK%R%   %DIM%optimisation windows%R%                       %FNT%v2.0%R%
echo   %FNT%--------------------------------------------------------------------%R%
echo.
echo   %WRN%^|%R%  %TXT%Droits administrateur requis%R%
echo.
echo   %DIM%Sean Tweak écrit dans le registre et modifie des services :%R%
echo   %DIM%Windows n'autorise pas ces opérations à un compte standard.%R%
echo.
echo   %CYA%^>%R%  %TXT%Une confirmation Windows va s'ouvrir.%R%
echo   %FNT%   Accepte-la et Sean Tweak redémarre avec les droits nécessaires.%R%
echo.%HID%

rem  On eleve cmd.exe (signe par Microsoft) qui rappelle ce .bat, plutot que
rem  d'elever le .bat directement : ShellExecute sur un .bat telecharge
rem  declenche l'avertissement "L'editeur n'a pas pu etre verifie".
set "SELF=%~f0"
powershell -NoProfile -Command "$q=[char]34; try { Start-Process -FilePath cmd.exe -ArgumentList '/c', ($q+$env:SELF+$q) -Verb RunAs -ErrorAction Stop } catch { exit 1 }"

if %errorlevel% neq 0 (
    cls
    echo.
    echo   %ACC%%B%SEAN TWEAK%R%   %DIM%optimisation windows%R%                       %FNT%v2.0%R%
    echo   %FNT%--------------------------------------------------------------------%R%
    echo.
    echo   %WRN%^|%R%  %TXT%Élévation refusée%R%
    echo.
    echo   %OKC%   Aucune modification n'a été faite sur ton système.%R%
    echo.
    echo   %DIM%Relance SeanTweak.bat et accepte la confirmation Windows,%R%
    echo   %DIM%ou fais un clic droit ^> "Exécuter en tant qu'administrateur".%R%
    echo.
    echo   %FNT%Appuie sur une touche pour fermer.%R%%HID%
    pause >nul
    echo %SHW%
)
exit /b

:run
cls
mode con: cols=110 lines=45
echo.
echo   %ACC%%B%SEAN TWEAK%R%   %DIM%optimisation windows%R%                       %FNT%v2.0%R%
echo.
echo   %FNT%Démarrage...%R%%HID%

rem  PowerShell 7 (pwsh) si disponible, sinon Windows PowerShell 5.1
where pwsh >nul 2>&1
if %errorlevel% equ 0 (
    pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0Optimisation-Windows.ps1"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Optimisation-Windows.ps1"
)

rem  capture du code AVANT tout echo : un echo remet errorlevel a 0
set "CODE=%errorlevel%"
echo %SHW%
if not "%CODE%"=="0" (
    echo.
    echo   %BAD%^|%R%  %TXT%Le script s'est terminé avec le code %CODE%.%R%
    echo   %FNT%Journal : %%LOCALAPPDATA%%\TweakSean\tweaksean.log%R%
    echo.
    pause
)
exit /b
