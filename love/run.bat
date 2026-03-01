@echo off
rem Launch Path of Building using LOVE
rem Usage: run.bat [path\to\love.exe]

setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
rem Remove trailing backslash
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

rem --- Find love.exe ---
if not "%~1"=="" (
	set "LOVE_BIN=%~1"
) else (
	rem Check PATH first
	where love.exe >NUL 2>NUL
	if !errorlevel! equ 0 (
		set "LOVE_BIN=love.exe"
	) else (
		rem Check common install locations
		if exist "%ProgramFiles%\LOVE\love.exe" (
			set "LOVE_BIN=%ProgramFiles%\LOVE\love.exe"
		) else if exist "%ProgramFiles(x86)%\LOVE\love.exe" (
			set "LOVE_BIN=%ProgramFiles(x86)%\LOVE\love.exe"
		) else if exist "%LocalAppData%\Programs\LOVE\love.exe" (
			set "LOVE_BIN=%LocalAppData%\Programs\LOVE\love.exe"
		) else (
			echo Error: love.exe not found.
			echo.
			echo Install LOVE 11.5+ from https://love2d.org or pass the path as an argument:
			echo   run.bat "C:\path\to\love.exe"
			echo.
			pause
			exit /b 1
		)
	)
)

rem --- Verify love.exe exists ---
if not exist "%LOVE_BIN%" (
	echo Error: love.exe not found at "%LOVE_BIN%"
	pause
	exit /b 1
)

rem --- Check LOVE version ---
set "LOVE_VER="
for /f "tokens=*" %%v in ('"%LOVE_BIN%" --version 2^>^&1') do (
	set "LOVE_LINE=%%v"
)
rem Extract version number (e.g. "LOVE 11.5" -> "11")
for /f "tokens=2 delims= " %%a in ("!LOVE_LINE!") do (
	for /f "tokens=1 delims=." %%b in ("%%a") do (
		set "LOVE_MAJOR=%%b"
	)
)
if defined LOVE_MAJOR (
	if !LOVE_MAJOR! LSS 11 (
		echo Warning: LOVE version !LOVE_LINE! detected. LOVE 11.5+ is recommended.
	)
)

rem --- Check for fonts ---
if not exist "%SCRIPT_DIR%\fonts" mkdir "%SCRIPT_DIR%\fonts"

set "FONTS_MISSING=0"
if not exist "%SCRIPT_DIR%\fonts\FontinSmallCaps.ttf" set "FONTS_MISSING=1"
if not exist "%SCRIPT_DIR%\fonts\BitstreamVeraSansMono.ttf" set "FONTS_MISSING=1"

if "!FONTS_MISSING!"=="1" (
	echo Fonts not found. Please place TTF fonts in %SCRIPT_DIR%\fonts\
	echo Required:
	echo   - FontinSmallCaps.ttf ^(Fontin SmallCaps^)
	echo   - BitstreamVeraSansMono.ttf ^(Bitstream Vera Sans Mono^)
	echo.
	echo Fontin SmallCaps is available from exljbris Font Foundry ^(free for personal use^).
	echo Bitstream Vera Sans Mono: https://www.gnome.org/fonts/
	echo.
	echo Attempting to find system fonts as fallback...

	rem Try to copy Bitstream Vera from Windows Fonts
	if not exist "%SCRIPT_DIR%\fonts\BitstreamVeraSansMono.ttf" (
		if exist "%SystemRoot%\Fonts\VeraMono.ttf" (
			copy "%SystemRoot%\Fonts\VeraMono.ttf" "%SCRIPT_DIR%\fonts\BitstreamVeraSansMono.ttf" >NUL
			echo   Copied VeraMono.ttf from system fonts
		)
	)

	rem Try to find FontinSmallCaps in system fonts
	if not exist "%SCRIPT_DIR%\fonts\FontinSmallCaps.ttf" (
		if exist "%SystemRoot%\Fonts\FontinSmallCaps.ttf" (
			copy "%SystemRoot%\Fonts\FontinSmallCaps.ttf" "%SCRIPT_DIR%\fonts\FontinSmallCaps.ttf" >NUL
			echo   Copied FontinSmallCaps.ttf from system fonts
		) else if exist "%SystemRoot%\Fonts\Fontin-SmallCaps.ttf" (
			copy "%SystemRoot%\Fonts\Fontin-SmallCaps.ttf" "%SCRIPT_DIR%\fonts\FontinSmallCaps.ttf" >NUL
			echo   Copied Fontin-SmallCaps.ttf from system fonts
		) else (
			rem Use Consolas as a last-resort fallback
			if exist "%SystemRoot%\Fonts\consola.ttf" (
				copy "%SystemRoot%\Fonts\consola.ttf" "%SCRIPT_DIR%\fonts\FontinSmallCaps.ttf" >NUL
				echo   Copied Consolas as FontinSmallCaps fallback
			)
		)
	)

	rem Final check
	if not exist "%SCRIPT_DIR%\fonts\FontinSmallCaps.ttf" (
		echo.
		echo   WARNING: Could not find a fallback for FontinSmallCaps.ttf
		echo   The application may fail to render text. Please install the font manually.
		echo.
	)
	if not exist "%SCRIPT_DIR%\fonts\BitstreamVeraSansMono.ttf" (
		echo.
		echo   WARNING: Could not find a fallback for BitstreamVeraSansMono.ttf
		echo   The application may fail to render text. Please install the font manually.
		echo.
	)
)

rem --- Create lib directory ---
if not exist "%SCRIPT_DIR%\lib" mkdir "%SCRIPT_DIR%\lib"

echo Starting Path of Building...
cd /d "%SCRIPT_DIR%"
"%LOVE_BIN%" .
