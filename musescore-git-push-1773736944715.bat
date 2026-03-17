@echo off
setlocal EnableExtensions
cd /d "C:\Users\Winson Wang\OneDrive\Documents\MuseScore4\Scores"

set "SCORE=Bitch Lasagna"
set "SCOREFILE=%SCORE%.mscz"
set "DIFFLOG=C:\Users\Winson Wang\OneDrive\Documents\MuseScore4\Scores\Bitch Lasagna\Bitch Lasagna_diff.log.txt"

git fetch origin >nul 2>nul

for /f "delims=" %%U in ('git rev-parse --abbrev-ref "@{upstream}" 2^>nul') do set "UPSTREAM=%%U"
if not defined UPSTREAM goto doPushNormal

for /f "delims=" %%L in ('git log "HEAD..%UPSTREAM%" --oneline -- "%SCOREFILE%" 2^>nul') do (set "REMOTE_AHEAD=1" & goto afterRemoteCheck)
:afterRemoteCheck
if not defined REMOTE_AHEAD goto doPushNormal

if exist "%DIFFLOG%" goto doPushForce

REM Remote is ahead and no diff marker: extract remote copy for MuseScore Diff and stop.
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "^
  try {^
    Set-Location 'C:\Users\Winson Wang\OneDrive\Documents\MuseScore4\Scores';^
    $up = git rev-parse --abbrev-ref '@{upstream}' 2>$null;^
    if (-not $up) { exit }^
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('ms_pull_' + [Guid]::NewGuid().ToString('N').Substring(0,8));^
    git worktree add --detach $tmp $up 2>$null | Out-Null;^
    $remoteFile = Join-Path $tmp ($env:SCOREFILE);^
    $copyDir = Join-Path 'C:\Users\Winson Wang\OneDrive\Documents\MuseScore4\Scores' ($env:SCORE + ' - Copy');^
    $copyMscx = Join-Path $copyDir ($env:SCORE + ' - Copy.mscx');^
    if (Test-Path $remoteFile) {^
      Add-Type -AssemblyName System.IO.Compression.FileSystem;^
      if (-not (Test-Path $copyDir)) { New-Item -ItemType Directory -Path $copyDir | Out-Null }^
      $zip = [IO.Compression.ZipFile]::OpenRead($remoteFile);^
      $entry = $zip.Entries | Where-Object { $_.Name -like '*.mscx' } | Select-Object -First 1;^
      if ($entry) { [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $copyMscx, $true) }^
      $zip.Dispose();^
    }^
    git worktree remove --force $tmp 2>$null | Out-Null;^
    Add-Type -AssemblyName System.Windows.Forms;^
    [System.Windows.Forms.MessageBox]::Show('Remote changes were found for "' + $env:SCORE + '".' + "`r`n`r`n" + 'The remote version has been saved to:' + "`r`n" + '  ' + $copyMscx + "`r`n`r`n" + 'Please run MuseScore Diff to review differences, then run this plugin again to push.','Unpulled Changes Detected',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null;^
  } catch {}"
goto end

:doPushNormal
if exist "%SCOREFILE%" git add "%SCOREFILE%"
git commit -m "Commit from MuseScore plugin: %SCORE%"
git push
goto end

:doPushForce
if exist "%SCOREFILE%" git add "%SCOREFILE%"
git commit -m "Commit from MuseScore plugin: %SCORE%"
git push --force
goto end

:end
pause