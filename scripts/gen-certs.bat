@echo off
echo ==========================================
echo Generating Kong hybrid clustering certs...
echo ==========================================

REM Create certs folder if not exists
if not exist "..\certs" (
    mkdir "..\certs"
)

REM Navigate to script directory (safety)
cd /d "%~dp0"

echo Running OpenSSL to create cluster.crt and cluster.key...

openssl req -x509 -nodes -newkey rsa:4096 ^
-keyout "..\certs\cluster.key" ^
-out "..\certs\cluster.crt" ^
-days 999 ^
-subj "/CN=kong_clustering"

if %ERRORLEVEL% NEQ 0 (
    echo ❌ OpenSSL failed! Make sure OpenSSL is installed and on PATH.
    pause
    exit /b 1
)

echo ✅ Certificates successfully generated!
echo Files:
echo  - certs\cluster.crt
echo  - certs\cluster.key
echo ==========================================
pause
