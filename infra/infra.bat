@echo off
REM ============================================================
REM  Infraestrutura IaaS do EsteticaPorDoSol no Google Cloud
REM  VPC + subnets + firewall + Cloud NAT + 2 VMs
REM
REM  Clique duas vezes para provisionar tudo.
REM  Argumentos sao repassados ao infra.ps1:
REM       infra.bat -SomenteApp     republica so a aplicacao
REM       infra.bat -Destruir       apaga a infraestrutura
REM ============================================================

setlocal
cd /d "%~dp0"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0infra.ps1" %*
set CODIGO=%ERRORLEVEL%

echo.
if %CODIGO% neq 0 (
    echo Terminou com erro. Codigo: %CODIGO%
) else (
    echo Concluido com sucesso.
)

echo.
echo Pressione qualquer tecla para fechar...
pause >nul
exit /b %CODIGO%
