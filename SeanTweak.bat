@echo off
chcp 65001 >nul
title Sean Tweak
color 0B
mode con: cols=110 lines=45
cd /d "%~dp0"

if not exist "%~dp0Optimisation-Windows.ps1" (
    echo [ERREUR] Optimisation-Windows.ps1 est introuvable dans ce dossier.
    pause
    exit /b 1
)

:: Test d'elevation : fltmc echoue si on n'est pas admin (plus rapide que net session)
fltmc >nul 2>&1
if %errorlevel% equ 0 goto run

cls
echo.
echo   ███████╗███████╗ █████╗ ███╗   ██╗    ████████╗██╗    ██╗███████╗ █████╗ ██╗  ██╗
echo   ██╔════╝██╔════╝██╔══██╗████╗  ██║    ╚══██╔══╝██║    ██║██╔════╝██╔══██╗██║ ██╔╝
echo   ███████╗█████╗  ███████║██╔██╗ ██║       ██║   ██║ █╗ ██║█████╗  ███████║█████╔╝ 
echo   ╚════██║██╔══╝  ██╔══██║██║╚██╗██║       ██║   ██║███╗██║██╔══╝  ██╔══██║██╔═██╗ 
echo   ███████║███████╗██║  ██║██║ ╚████║       ██║   ╚███╔███╔╝███████╗██║  ██║██║  ██╗
echo   ╚══════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝       ╚═╝    ╚══╝╚══╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝
echo.
echo   optimisation windows                                                        v2.0
echo.
echo   ────────────────────────────────────────────────────────────────────────────────
echo.
echo     Ce script necessite les droits administrateur.
echo.
echo     •  Clic droit sur SeanTweak.bat
echo     •  Selectionnez "Executer en tant qu'administrateur"
echo.
echo   ────────────────────────────────────────────────────────────────────────────────
echo.
pause
exit /b 1

:run
cls
color 0B
mode con: cols=110 lines=45
echo.
echo   ███████╗███████╗ █████╗ ███╗   ██╗    ████████╗██╗    ██╗███████╗ █████╗ ██╗  ██╗
echo   ██╔════╝██╔════╝██╔══██╗████╗  ██║    ╚══██╔══╝██║    ██║██╔════╝██╔══██╗██║ ██╔╝
echo   ███████╗█████╗  ███████║██╔██╗ ██║       ██║   ██║ █╗ ██║█████╗  ███████║█████╔╝ 
echo   ╚════██║██╔══╝  ██╔══██║██║╚██╗██║       ██║   ██║███╗██║██╔══╝  ██╔══██║██╔═██╗ 
echo   ███████║███████╗██║  ██║██║ ╚████║       ██║   ╚███╔███╔╝███████╗██║  ██║██║  ██╗
echo   ╚══════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝       ╚═╝    ╚══╝╚══╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝
echo.
echo   optimisation windows                                                        v2.0
echo.

:: Utilise PowerShell 7 (pwsh) si disponible, sinon retombe sur Windows PowerShell 5.1
where pwsh >nul 2>&1
if %errorlevel% equ 0 (
    pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0Optimisation-Windows.ps1"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Optimisation-Windows.ps1"
)
if %errorlevel% neq 0 pause
