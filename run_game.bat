@echo off
rem Runs the Pokerstory prototype with Godot 4.7.2.
rem Set GODOT to your Godot 4.7.2 executable if it is not in the default location below.
set "GODOT_EXE=%GODOT%"
if "%GODOT_EXE%"=="" set "GODOT_EXE=%USERPROFILE%\tools\godot\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT_EXE%" (
  echo Godot 4.7.2 not found: %GODOT_EXE%
  echo Download Godot_v4.7.2-stable_win64.exe.zip from https://github.com/godotengine/godot/releases/tag/4.7.2-stable
  echo and set the GODOT environment variable to the .exe path.
  pause
  exit /b 1
)
start "" "%GODOT_EXE%" --path "%~dp0game"
