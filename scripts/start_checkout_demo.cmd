@echo off
setlocal
node "%~dp0start_checkout_demo.mjs" %*
exit /b %errorlevel%
