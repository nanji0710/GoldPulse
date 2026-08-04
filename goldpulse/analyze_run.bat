@echo off
rem 便捷脚本：修复 Windows PATH 污染导致 flutter 命令失效的问题
rem （本机 PATH 混入换行文本时，MSYS 转换会截断，使 flutter.bat 找不到 git/where）
set PATH=%USERPROFILE%\flutter\bin;C:\Windows\System32;C:\Windows
cd /d "%~dp0"
flutter analyze > analyze_out.txt 2>&1
