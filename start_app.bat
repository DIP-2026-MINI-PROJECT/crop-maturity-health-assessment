@echo off
rem Double-click to start CropVision. The app opens MATLAB with the watcher by itself.
cd /d "%~dp0"
".venv\Scripts\python.exe" -m streamlit run app.py
pause
