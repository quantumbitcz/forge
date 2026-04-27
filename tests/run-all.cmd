@echo off
setlocal
set "TIER=%~1"
if "%TIER%"=="" set "TIER=all"

set "BASH_EXE="
if exist "%ProgramFiles%\Git\bin\bash.exe" (
  set "BASH_EXE=%ProgramFiles%\Git\bin\bash.exe"
) else if exist "%ProgramFiles(x86)%\Git\bin\bash.exe" (
  set "BASH_EXE=%ProgramFiles(x86)%\Git\bin\bash.exe"
) else (
  for /f "delims=" %%I in ('where bash 2^>NUL') do (
    if not defined BASH_EXE set "BASH_EXE=%%I"
  )
)

if not defined BASH_EXE (
  echo ERROR: bash.exe not found. Probed:
  echo   %ProgramFiles%\Git\bin\bash.exe
  echo   %ProgramFiles(x86)%\Git\bin\bash.exe
  echo   PATH (via 'where bash')
  echo Install Git for Windows, or expose WSL bash on PATH.
  exit /b 1
)

"%BASH_EXE%" "%~dp0run-all.sh" %TIER%
exit /b %ERRORLEVEL%
