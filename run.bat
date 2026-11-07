@echo off
setlocal enabledelayedexpansion
title Where Is It - Digital File System Investigator

:: Check if bash is in PATH
where.exe bash >nul 2>nul
if %errorlevel% equ 0 (
    set "BASH_CMD=bash"
    goto :RUN
)

:: Search standard and custom installation paths for Git Bash
if exist "D:\MyPrograms\Git\bin\bash.exe" (
    set "BASH_CMD=D:\MyPrograms\Git\bin\bash.exe"
    goto :RUN
)

if exist "%LOCALAPPDATA%\Programs\Git\bin\bash.exe" (
    set "BASH_CMD=%LOCALAPPDATA%\Programs\Git\bin\bash.exe"
    goto :RUN
)

if exist "C:\Program Files\Git\bin\bash.exe" (
    set "BASH_CMD=C:\Program Files\Git\bin\bash.exe"
    goto :RUN
)

if exist "C:\Program Files (x86)\Git\bin\bash.exe" (
    set "BASH_CMD=C:\Program Files (x86)\Git\bin\bash.exe"
    goto :RUN
)

:: Try resolving via git.exe location
for /f "tokens=*" %%i in ('where.exe git 2^>nul') do (
    set "GIT_EXE=%%i"
    set "GIT_DIR=!GIT_EXE:\cmd\git.exe=!"
    if exist "!GIT_DIR!\bin\bash.exe" (
        set "BASH_CMD=!GIT_DIR!\bin\bash.exe"
        goto :RUN
    )
    if exist "!GIT_DIR!\usr\bin\bash.exe" (
        set "BASH_CMD=!GIT_DIR!\usr\bin\bash.exe"
        goto :RUN
    )
)

:: If bash not found, notify user
echo ===============================================================================
echo ERROR: Git Bash was not found on your system!
echo ===============================================================================
echo 'Where Is It' requires a Bash execution environment to run.
echo.
echo Please ensure Git for Windows is installed:
echo   Download from: https://git-scm.com/download/win
echo.
echo Or add your Git bin folder to your system PATH.
echo ===============================================================================
pause
exit /b 1

:RUN
"%BASH_CMD%" "%~dp0src/main.sh" %*
if %errorlevel% neq 0 (
    echo.
    echo Application exited with code %errorlevel%.
)
endlocal
