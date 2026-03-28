@echo off
setlocal EnableExtensions
REM Claudius — Windows launcher for Claude Code multi-backend bootstrapper.
REM Interactive prompts and JSON/API logic run in PowerShell (claudius.ps1).
REM
REM Claude Code user settings (global):
REM   %USERPROFILE%\.claude\settings.json
REM Claudius preferences:
REM   %USERPROFILE%\.claude\claudius-prefs.json
REM (Same layout as macOS/Linux: ~/.claude/...)
REM
REM If claude.exe is missing, install Claude Code using ONE of:
REM   powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://claude.ai/install.ps1 | iex"
REM   curl -fsSL https://claude.ai/install.cmd -o install.cmd && install.cmd && del install.cmd
REM   winget install Anthropic.ClaudeCode
REM Docs: https://code.claude.com/docs  (Git for Windows is required.)
REM
set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%claudius.ps1"
if not exist "%PS_SCRIPT%" (
  echo ERROR: Missing "%PS_SCRIPT%"
  echo Place claudius.ps1 next to claudius.bat
  exit /b 1
)

if /I "%~1"=="--help" goto :help
if /I "%~1"=="-h" goto :help

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" %*
set "EC=%ERRORLEVEL%"
exit /b %EC%

:help
call :print_help
exit /b 0

:print_help
echo Usage: %~nx0 [OPTIONS]
echo.
echo Claudius — Claude Code multi-backend bootstrapper (Windows^)
echo.
echo Config:
echo   %%USERPROFILE%%\.claude\settings.json
echo   %%USERPROFILE%%\.claude\claudius-prefs.json
echo.
echo Options:
echo   --help, -h          This help
echo   --init              Reset preferences (backend, URLs, keys^)
echo   --purge             Purge session data under .claude
echo   --dry-run, --test   Test without writing config or starting Claude
echo   --by-pass-start     Write config only; do not start Claude
echo   --last              Use last model and context from prefs
echo.
echo PowerShell script: "%PS_SCRIPT%" (5.1+^)
echo https://github.com/Somnius/Claudius-Bootstrapper
echo.
exit /b 0
