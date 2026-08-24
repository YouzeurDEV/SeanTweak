@echo off
setlocal
chcp 65001 >nul
title Sean Tweak
cd /d "%~dp0"

rem  Ce fichier est volontairement en ASCII pur : les caracteres de dessin
rem  Unicode combines a "chcp 65001" font perdre le fil a l'analyseur de cmd,
rem  qui se met alors a executer les lignes du logo comme des commandes.
rem  Le logo anime est affiche par le script PowerShell.

if not exist "%~dp0Optimisation-Windows.ps1" (
    echo.
    echo   [ERREUR] Optimisation-Windows.ps1 est introuvable dans ce dossier.
    echo   Garde SeanTweak.bat et Optimisation-Windows.ps1 cote a cote.
    echo.
    pause
    exit /b 1
)

rem  Test d'elevation : fltmc echoue si on n'est pas administrateur
rem  (plus rapide que net session)
fltmc >nul 2>&1
if %errorlevel% equ 0 goto run

cls
echo.
echo   SEAN TWEAK  -  optimisation windows                            v2.0
echo   --------------------------------------------------------------------
echo.
echo   Sean Tweak modifie le registre et les services : les droits
echo   administrateur sont necessaires.
echo.
echo   Une fenetre de confirmation Windows va s'ouvrir.
echo.

powershell -NoProfile -Command "try { Start-Process -FilePath '%~f0' -Verb RunAs -ErrorAction Stop } catch { exit 1 }"

if %errorlevel% neq 0 (
    echo   Elevation refusee : Sean Tweak n'a rien modifie.
    echo.
    echo   Pour reessayer : clic droit sur SeanTweak.bat, puis
    echo   "Executer en tant qu'administrateur".
    echo.
    pause
)
exit /b

:run
cls
mode con: cols=110 lines=45

rem  PowerShell 7 (pwsh) si disponible, sinon Windows PowerShell 5.1
where pwsh >nul 2>&1
if %errorlevel% equ 0 (
    pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0Optimisation-Windows.ps1"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Optimisation-Windows.ps1"
)

if %errorlevel% neq 0 (
    echo.
    echo   Le script s'est termine avec le code %errorlevel%.
    pause
)
exit /b
