@echo off
rem cspell:words LÖVE enabledelayedexpansion errorlevel
rem Build Path of Building for Windows using LÖVE runtime
rem Output: Builds\PathOfBuilding\ with launcher + LÖVE runtime + game data
rem
rem Uses the UNFUSED layout (matching CI): love\ directory on disk, LÖVE binary
rem runs with "love-runtime\love.exe love\" so love.filesystem.getSource() returns
rem the love\ directory path (sibling of src\).
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
mkdir "%DIST_DIR%\love-runtime"
mkdir "%DIST_DIR%\love"
mkdir "%DIST_DIR%\src"
mkdir "%DIST_DIR%\runtime"

rem --- LÖVE runtime (binary + DLLs) ---
echo Copying LOVE runtime...
copy "%LOVE_EXTRACTED%\love.exe" "%DIST_DIR%\love-runtime\" >NUL
for %%f in ("%LOVE_EXTRACTED%\*.dll") do copy "%%f" "%DIST_DIR%\love-runtime\" >NUL
if exist "%LOVE_EXTRACTED%\license.txt" (
	copy "%LOVE_EXTRACTED%\license.txt" "%DIST_DIR%\love-runtime\love-license.txt" >NUL
)

rem --- Game directory (love\) on disk, auto-updatable ---
echo Copying love\ game directory...
copy "%SCRIPT_DIR%\main.lua" "%DIST_DIR%\love\" >NUL
copy "%SCRIPT_DIR%\conf.lua" "%DIST_DIR%\love\" >NUL
xcopy /E /I /Q "%SCRIPT_DIR%\shim" "%DIST_DIR%\love\shim"
xcopy /E /I /Q "%SCRIPT_DIR%\lib" "%DIST_DIR%\love\lib"
if exist "%SCRIPT_DIR%\fonts" xcopy /E /I /Q "%SCRIPT_DIR%\fonts" "%DIST_DIR%\love\fonts"

rem --- Copy game data ---
echo Copying game data...
xcopy /E /I /Q "%REPO_DIR%\src" "%DIST_DIR%\src"
mkdir "%DIST_DIR%\runtime\lua"
xcopy /E /I /Q "%REPO_DIR%\runtime\lua" "%DIST_DIR%\runtime\lua"

rem Manifest (into src\ where UpdateCheck.lua expects it)
if exist "%REPO_DIR%\manifest.xml" (
	copy "%REPO_DIR%\manifest.xml" "%DIST_DIR%\src\" >NUL
)

rem Default part files
if exist "%REPO_DIR%\changelog.txt" copy "%REPO_DIR%\changelog.txt" "%DIST_DIR%\src\" >NUL
if exist "%REPO_DIR%\help.txt" copy "%REPO_DIR%\help.txt" "%DIST_DIR%\src\" >NUL
if exist "%REPO_DIR%\LICENSE.md" copy "%REPO_DIR%\LICENSE.md" "%DIST_DIR%\src\" >NUL

rem License at top level
if exist "%REPO_DIR%\LICENSE.md" (
	copy "%REPO_DIR%\LICENSE.md" "%DIST_DIR%\" >NUL
)

rem --- Create launcher batch script (unfused: passes love\ directory as argument) ---
echo @echo off> "%DIST_DIR%\LOVE-PathOfBuilding.bat"
echo set "SCRIPT_DIR=%%~dp0">> "%DIST_DIR%\LOVE-PathOfBuilding.bat"
echo if "%%SCRIPT_DIR:~-1%%"=="\" set "SCRIPT_DIR=%%SCRIPT_DIR:~0,-1%%">> "%DIST_DIR%\LOVE-PathOfBuilding.bat"
echo start "" "%%SCRIPT_DIR%%\love-runtime\love.exe" "%%SCRIPT_DIR%%\love" %%*>> "%DIST_DIR%\LOVE-PathOfBuilding.bat"

echo.
echo === Build complete ===
echo Run with: %DIST_DIR%\LOVE-PathOfBuilding.bat
