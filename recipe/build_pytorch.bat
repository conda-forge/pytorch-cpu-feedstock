@echo On
setlocal enabledelayedexpansion

call %RECIPE_DIR%\bld.bat
if errorlevel 1 exit /b 1

rmdir /s /q %SP_DIR%\torch\bin
rmdir /s /q %SP_DIR%\torch\share
for %%f in (ATen caffe2 torch c10) do (
    rmdir /s /q %SP_DIR%\torch\include\%%f
)

@REM Delete all files from the lib directory that do not start with torch_python
for %%f in (%SP_DIR%\torch\lib\*) do (
    set "FILENAME=%%~nf"
    if "!FILENAME:~0,12!" neq "torch_python" (
        del %%f
    )
)
