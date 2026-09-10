@echo off
title Matnami Source Tester & Compatibility Suite
python tools\matnami_tester.py %*
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo An error occurred while running the tester.
)
pause

