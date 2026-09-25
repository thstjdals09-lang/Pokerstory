@echo off
rem 3D diorama prototype of the village square (primitive shapes only). The 2D game is unchanged.
rem Uses the Forward+ renderer for shadows, ambient occlusion and depth blur.
set "GODOT_EXE=%GODOT%"
if "%GODOT_EXE%"=="" set "GODOT_EXE=%USERPROFILE%\tools\godot\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT_EXE%" (
  echo Godot 4.7.2 not found: %GODOT_EXE%
  pause
  exit /b 1
)
start "" "%GODOT_EXE%" --path "%~dp0game" --rendering-method forward_plus res://diorama/diorama.tscn
