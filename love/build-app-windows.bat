@echo off
rem Build Path of Building for Windows using LÖVE runtime
rem Output: Builds\PathOfBuilding\ with fused exe + LÖVE DLLs + game data
rem
rem Usage: build-app-windows.bat
rem Requires: curl (ships with Windows 10+), PowerShell 5+

setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

for %%I in ("%SCRIPT_DIR%\..") do set "REPO_DIR=%%~fI"
set "BUILD_DIR=%REPO_DIR%\Builds"
set "DIST_DIR=%BUILD_DIR%\PathOfBuilding"
set "LOVE_VERSION=11.5"
set "LOVE_ZIP_URL=https://github.com/love2d/love/releases/download/%LOVE_VERSION%/love-%LOVE_VERSION%-win64.zip"
set "LOVE_ZIP=%BUILD_DIR%\love-%LOVE_VERSION%-win64.zip"
set "LOVE_EXTRACTED=%BUILD_DIR%\love-%LOVE_VERSION%-win64"

echo === Building Path of Building (Windows) ===
echo Repository: %REPO_DIR%
echo Output:     %DIST_DIR%
echo.

rem Create build directory
if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"

rem --- Download LÖVE if not cached ---
if exist "%LOVE_ZIP%" (
	echo Using cached LOVE zip: %LOVE_ZIP%
) else (
	echo Downloading LOVE %LOVE_VERSION%...
	curl -L -o "%LOVE_ZIP%" "%LOVE_ZIP_URL%"
	if !errorlevel! neq 0 (
		echo Error: Failed to download LOVE
		exit /b 1
	)
	echo Downloaded.
)

rem --- Extract LÖVE if not cached ---
if exist "%LOVE_EXTRACTED%" (
	echo Using cached LOVE runtime: %LOVE_EXTRACTED%
) else (
	echo Extracting LOVE...
	powershell -Command "Expand-Archive -Path '%LOVE_ZIP%' -DestinationPath '%BUILD_DIR%' -Force"
	if !errorlevel! neq 0 (
		echo Error: Failed to extract LOVE
		exit /b 1
	)
	echo Extracted.
)

rem --- Clean previous build ---
if exist "%DIST_DIR%" (
	echo Cleaning previous build...
	rmdir /s /q "%DIST_DIR%"
)
mkdir "%DIST_DIR%"
mkdir "%DIST_DIR%\runtime"

rem --- Create .love file ---
echo Creating .love file...
set "LOVE_FILE=%BUILD_DIR%\PathOfBuilding.love"
if exist "%LOVE_FILE%" del "%LOVE_FILE%"

rem Stage files using robocopy (exclude build/launch scripts and scripts/ dir)
set "STAGING=%BUILD_DIR%\love-staging"
if exist "%STAGING%" rmdir /s /q "%STAGING%"
robocopy "%SCRIPT_DIR%" "%STAGING%" /E /XF run.sh run.bat build-app-linux.sh build-app-windows.bat /XD scripts >NUL

rem Zip the staging directory into a .love file
powershell -Command "Compress-Archive -Path '%STAGING%\*' -DestinationPath '%LOVE_FILE%' -Force"
if !errorlevel! neq 0 (
	echo Error: Failed to create .love file
	exit /b 1
)
rmdir /s /q "%STAGING%"

rem --- Fuse love.exe + .love into LOVE-PathOfBuilding.exe ---
echo Fusing binary...
copy /b "%LOVE_EXTRACTED%\love.exe"+"%LOVE_FILE%" "%DIST_DIR%\LOVE-PathOfBuilding.exe" >NUL

rem --- Copy LÖVE runtime DLLs ---
echo Copying LOVE runtime DLLs...
for %%f in ("%LOVE_EXTRACTED%\*.dll") do copy "%%f" "%DIST_DIR%\" >NUL

rem Copy LÖVE license
if exist "%LOVE_EXTRACTED%\license.txt" (
	copy "%LOVE_EXTRACTED%\license.txt" "%DIST_DIR%\love-license.txt" >NUL
)

rem --- Copy game data ---
echo Copying game data...
xcopy /E /I /Q "%REPO_DIR%\src" "%DIST_DIR%\src"
rem Copy manifest and default part files for auto-updates
if exist "%REPO_DIR%\manifest.xml" (
	copy "%REPO_DIR%\manifest.xml" "%DIST_DIR%\src\" >NUL
)
if exist "%REPO_DIR%\changelog.txt" copy "%REPO_DIR%\changelog.txt" "%DIST_DIR%\src\" >NUL
if exist "%REPO_DIR%\help.txt" copy "%REPO_DIR%\help.txt" "%DIST_DIR%\src\" >NUL
if exist "%REPO_DIR%\LICENSE.md" copy "%REPO_DIR%\LICENSE.md" "%DIST_DIR%\src\" >NUL
xcopy /E /I /Q "%REPO_DIR%\runtime\lua" "%DIST_DIR%\runtime\lua"
xcopy /E /I /Q "%SCRIPT_DIR%\lib" "%DIST_DIR%\lib"

rem Copy license
if exist "%REPO_DIR%\LICENSE.md" (
	copy "%REPO_DIR%\LICENSE.md" "%DIST_DIR%\" >NUL
)

rem --- Clean up intermediate .love file ---
del "%LOVE_FILE%"

echo.
echo === Build complete ===
echo Run with: %DIST_DIR%\LOVE-PathOfBuilding.exe
