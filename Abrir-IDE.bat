@echo off
chcp 65001 >nul
setlocal
title IntelliJ IDEA en contenedor

rem El proyecto tiene que estar en el disco de Windows; %~dp0 lo resuelve
rem aunque haya espacios o acentos en la ruta. Se quita la barra final porque
rem wsl --cd no la acepta.
set "PROJECT_DIR=%~dp0"
if "%PROJECT_DIR:~-1%"=="\" set "PROJECT_DIR=%PROJECT_DIR:~0,-1%"

rem Se usa la distro "Ubuntu" si existe; si el alumno la renombro, la de por
rem defecto de WSL.
set "DISTRO=-d Ubuntu"
wsl.exe -d Ubuntu -e true >nul 2>&1
if errorlevel 1 set "DISTRO="

echo.
echo  Abriendo IntelliJ IDEA en el contenedor...
echo.
echo  Carpeta del proyecto:
echo    %PROJECT_DIR%
echo.
echo  Comprueba que es donde has clonado el proyecto. Si no lo es, cierra
echo  esta ventana y abre Abrir-IDE.bat desde la carpeta correcta.
echo.
echo  NO cierres esta ventana: es el IDE. Se cierra sola al salir.
echo.

rem Si el .bat se copia fuera del proyecto (por ejemplo al escritorio), el
rem lanzador no esta y el error de bash no diria nada util.
if not exist "%PROJECT_DIR%\docker\idea-desktop\run-idea.sh" (
  echo.
  echo  *** No encuentro docker\idea-desktop\run-idea.sh en esta carpeta. ***
  echo  Abre Abrir-IDE.bat desde la carpeta del proyecto.
  echo.
  pause
  exit /b 1
)

rem Los ficheros .sh pueden llegar con finales de linea de Windows (CRLF) si
rem el proyecto se copio en un ZIP o por USB; bash falla con eso, asi que se
rem normalizan antes de ejecutar.
wsl.exe %DISTRO% --cd "%PROJECT_DIR%" bash -c "sed -i 's/\r$//' docker/idea-desktop/run-idea.sh docker/idea-desktop/entrypoint.sh 2>/dev/null; bash docker/idea-desktop/run-idea.sh"

if errorlevel 1 (
  echo.
  echo  *** El IDE no ha podido arrancar. ***
  echo  Copia el mensaje de arriba y avisa al profesor.
  echo.
  pause
)
endlocal
