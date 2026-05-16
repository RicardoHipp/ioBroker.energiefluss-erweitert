@echo off
cd /d D:\programmieren\eniergiefluss_erweitert_fork

echo Aktueller Status:
git status

echo.
set /p MSG="Commit-Nachricht eingeben: "

git add -A
git commit -m "%MSG%"
git push origin main

echo.
echo Fertig!
pause
