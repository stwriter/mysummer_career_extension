@echo off
setlocal

:: Set paths relative to the script location
set "ROOT_DIR=%~dp0"
set "BASE_UI=%ROOT_DIR%..\\rls_career_overhaul\\baseUI"
set "RLS_VUE_SRC=%ROOT_DIR%..\\rls_career_overhaul\\ui-vue-src"
set "RLS_UI=%ROOT_DIR%..\\rls_career_overhaul\\ui"
set "VUE_SRC=%ROOT_DIR%ui-vue-src"
set "BUILD_DIR=%ROOT_DIR%ui-build-temp"
set "DIST_TARGET=%ROOT_DIR%ui\\vue-dist"

echo.
echo ========================================
echo   BeamNG UI Build Script (MYSUMCAR)
echo ========================================
echo.

:: Check for Node.js
where node >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo Error: Node.js is not installed or not in PATH.
    pause
    exit /b 1
)

:: 1. Prepare build directory
echo [1/4] Preparing build directory...
mkdir "%BUILD_DIR%"
:: Copy baseUI to temp build directory
robocopy "%BASE_UI%" "%BUILD_DIR%" /E /MT /NFL /NDL /NJH /NJS /nc /ns /np >nul

:: 2. Overwrite with custom source
echo [2/4] Merging RLS ui-vue-src into build directory...
robocopy "%RLS_VUE_SRC%" "%BUILD_DIR%\\src" /E /MT /NFL /NDL /NJH /NJS /nc /ns /np >nul

echo       Merging extension ui-vue-src into build directory...
robocopy "%VUE_SRC%" "%BUILD_DIR%\\src" /E /MT /NFL /NDL /NJH /NJS /nc /ns /np >nul

:: 3. Build
echo [3/4] Building UI...
pushd "%BUILD_DIR%"

:: Copy existing node_modules from baseUI to speed up if they exist
if exist "%BASE_UI%\\node_modules" (
    echo   Copying existing node_modules from baseUI...
    robocopy "%BASE_UI%\\node_modules" "node_modules" /E /MT /NFL /NDL /NJH /NJS /nc /ns /np >nul
)

:: Check if npm install is needed
if not exist "node_modules" (
    echo   node_modules not found, running npm install...
    call npm install
) else (
    echo   node_modules already present, skipping npm install...
)

if %ERRORLEVEL% neq 0 (
    echo Error: npm install failed.
    popd
    pause
    exit /b 1
)

echo   Running npm run build...
call npm run build
if %ERRORLEVEL% neq 0 (
    echo Error: npm build failed.
    popd
    pause
    exit /b 1
)
popd

:: 4. Copy to final location
echo [4/4] Copying build results to %DIST_TARGET%...
if not exist "%DIST_TARGET%" mkdir "%DIST_TARGET%"
:: Clean target first to avoid stale files
del /q /s "%DIST_TARGET%\\*" 2>nul
robocopy "%BUILD_DIR%\\dist" "%DIST_TARGET%" /E /MT /NFL /NDL /NJH /NJS /nc /ns /np >nul

:: Fix rolldown-vite bug: copy working index.html from RLS
echo     Fixing index.html (rolldown-vite bug workaround)...
copy /Y "%RLS_UI%\\vue-dist\\index.html" "%DIST_TARGET%\\index.html" >nul

echo     Syncing RLS UI support folders into extension UI...
if not exist "%ROOT_DIR%ui\\modules" mkdir "%ROOT_DIR%ui\\modules"
if not exist "%ROOT_DIR%ui\\modModules" mkdir "%ROOT_DIR%ui\\modModules"
if not exist "%ROOT_DIR%ui\\startScreen" mkdir "%ROOT_DIR%ui\\startScreen"
robocopy "%RLS_UI%\\modules" "%ROOT_DIR%ui\\modules" /E /MT /NFL /NDL /NJH /NJS /nc /ns /np >nul
robocopy "%RLS_UI%\\modModules" "%ROOT_DIR%ui\\modModules" /E /MT /NFL /NDL /NJH /NJS /nc /ns /np >nul
robocopy "%RLS_UI%\\startScreen" "%ROOT_DIR%ui\\startScreen" /E /MT /NFL /NDL /NJH /NJS /nc /ns /np >nul

echo.
echo ========================================
echo   Build Successful!
echo ========================================
echo.
