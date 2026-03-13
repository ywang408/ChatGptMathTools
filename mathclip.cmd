@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Convert-ChatGptMathClipboard.ps1" %*
exit /b %ERRORLEVEL%
