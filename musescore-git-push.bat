@echo off
cd /d "C:\Users\Winson Wang\OneDrive\Documents\MuseScore4\Scores"
if exist "Bitch Lasagna.mscz" git add "Bitch Lasagna.mscz"
if exist "Bitch Lasagna.mscx" git add "Bitch Lasagna.mscx"
git commit -m "Commit from MuseScore plugin: Bitch Lasagna"
git push
pause