@echo off
rem Opens the Godot editor on the 3D game camera (the one run_diorama.bat uses).
rem Select the root node "GameCamera3D" and change the values in the Inspector, then save (Ctrl+S).
set "GODOT_EXE=%GODOT%"
if "%GODOT_EXE%"=="" set "GODOT_EXE=%USERPROFILE%\tools\godot\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT_EXE%" (
  echo Godot 4.7.2 not found: %GODOT_EXE%
  pause
  exit /b 1
)
start "" "%GODOT_EXE%" --editor --path "%~dp0game" --rendering-method forward_plus res://scenes/game_camera_3d.tscn
