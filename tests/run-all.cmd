@echo off
setlocal
set "TIER=%~1"
if "%TIER%"=="" set "TIER=all"

set "BASH_EXE=bash.exe"
where %BASH_EXE% >nul 2>nul
if errorlevel 1 (
  if exist "%ProgramFiles%\Git\bin\bash.exe" (
    set "BASH_EXE=%ProgramFiles%\Git\bin\bash.exe"
  ) else (
    echo ERROR: bash.exe not found. Install Git for Windows.
    exit /b 1
  )
)

"%BASH_EXE%" "%~dp0run-all.sh" %TIER%
exit /b %ERRORLEVEL%
