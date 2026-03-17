@echo off
cd /d "C:\Users\Winson Wang\OneDrive\Documents\MuseScore4\Scores"
if exist "Bitch Lasagna.mscz" git add "Bitch Lasagna.mscz"
git commit -m "Commit from MuseScore plugin: Bitch Lasagna"
git push --force
pause
del "%~f0"