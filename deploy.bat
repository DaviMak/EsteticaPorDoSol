@echo off
REM  Deploy do EsteticaPorDoSol no Google Cloud
REM  Clique duas vezes neste arquivo para executar.

setlocal
cd /d "%~dp0"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy.ps1" %*
set CODIGO=%ERRORLEVEL%

echo.
if %CODIGO% neq 0 (
    echo O deploy terminou com erro. Codigo: %CODIGO%
) else (
    echo Deploy finalizado com sucesso.
)

echo.
echo Pressione qualquer tecla para fechar...
pause >nul
exit /b %CODIGO%
