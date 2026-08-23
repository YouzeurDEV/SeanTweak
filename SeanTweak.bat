@echo off
chcp 65001 >nul
title TweakSean
cd /d "%~dp0"

if not exist "%~dp0Optimisation-Windows.ps1" (
    echo [ERREUR] Optimisation-Windows.ps1 est introuvable dans ce dossier.
    pause
    exit /b 1
)

:: Test d'elevation : fltmc echoue si on n'est pas admin (plus rapide que net session)
fltmc >nul 2>&1
if %errorlevel% equ 0 goto run

echo Demande des droits administrateur...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$q=[char]34; Start-Process -FilePath $q$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe$q -Verb RunAs -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File ' + $q + '%~dp0Optimisation-Windows.ps1' + $q)"
exit /b

:run
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Optimisation-Windows.ps1"
if %errorlevel% neq 0 pause
