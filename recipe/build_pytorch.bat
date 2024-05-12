
if "%megabuild%" == "true" (
    call %RECIPE_DIR%\bld.bat
) else (
    for %%f in (torch-*.whl) do (
        %PYTHON% -m pip install --no-deps %%f
    )    
)
