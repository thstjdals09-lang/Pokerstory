@echo off
rem Opens the Godot editor on the 3D square (Forward+ so the preview shows shadows and light).
set "GODOT_EXE=%GODOT%"
if "%GODOT_EXE%"=="" set "GODOT_EXE=%USERPROFILE%\tools\godot\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT_EXE%" (
  echo Godot 4.7.2 not found: %GODOT_EXE%
  pause
  exit /b 1
)
start "" "%GODOT_EXE%" --editor --path "%~dp0game" --rendering-method forward_plus res://diorama/diorama.tscn
