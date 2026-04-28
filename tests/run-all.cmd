@echo off
setlocal enabledelayedexpansion
set "TIER=%~1"
if "!TIER!"=="" set "TIER=all"

rem Probe candidate bash.exe locations. We use delayed expansion (!VAR!)
rem because %ProgramFiles(x86)% contains a literal ')' that the cmd parser
rem treats as the end of an if/else block, which previously broke this
rem script with "\Git\bin\bash.exe was unexpected at this time.".
rem
rem We also avoid placing any unescaped ')' inside the if (...) error block
rem below — cmd's parser closes the block at the first stray ')', which
rem caused a regression where 'echo   PATH (via where bash)' silently
rem terminated the if-block early and the trailing diagnostic + 'exit /b 1'
rem ran unconditionally.
set "BASH_EXE="
set "PF=%ProgramFiles%"
set "PF86=%ProgramFiles(x86)%"

if exist "!PF!\Git\bin\bash.exe" set "BASH_EXE=!PF!\Git\bin\bash.exe"
if not defined BASH_EXE if exist "!PF86!\Git\bin\bash.exe" set "BASH_EXE=!PF86!\Git\bin\bash.exe"
if not defined BASH_EXE (
  for /f "delims=" %%I in ('where bash 2^>NUL') do (
    if not defined BASH_EXE set "BASH_EXE=%%I"
  )
)

if defined BASH_EXE goto :run

echo ERROR: bash.exe not found. Probed:
echo   !PF!\Git\bin\bash.exe
echo   !PF86!\Git\bin\bash.exe
echo   PATH lookup via where bash
echo Install Git for Windows, or expose WSL bash on PATH.
exit /b 1

:run
"!BASH_EXE!" "%~dp0run-all.sh" !TIER!
exit /b %ERRORLEVEL%
