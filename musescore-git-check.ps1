param($scoresDir, $scoreFile, $nameNoExt, $commitBat, $forceBat, $diffLogTxt)
Set-Location $scoresDir

# Fetch silently; ignore errors (offline, no remote, etc.)
git fetch origin 2>&1 | Out-Null

# Resolve upstream branch; if none is set this is a brand-new score — push normally
$upstream = git rev-parse --abbrev-ref '@{upstream}' 2>&1
if ($LASTEXITCODE -ne 0) { Start-Process $commitBat; exit }

# Any commits on remote that touch this file and aren't in local HEAD?
$unpulled = git log "HEAD..${upstream}" --oneline -- $scoreFile 2>&1
if ($LASTEXITCODE -ne 0 -or -not $unpulled) { Start-Process $commitBat; exit }

# Remote is ahead for this file.
# If we have already reviewed the diff (marker exists), force-push to replace remote.
if (Test-Path $diffLogTxt) { Start-Process $forceBat; exit }

# No diff yet — extract the remote .mscz inner .mscx into the Copy folder
# so the user can run MuseScore Diff before committing.
$tmpTree = Join-Path ([System.IO.Path]::GetTempPath()) ('ms_pull_' + [System.Guid]::NewGuid().ToString('N').Substring(0,8))
git worktree add --detach $tmpTree $upstream 2>&1 | Out-Null

$success  = $false
$remoteFile = Join-Path $tmpTree $scoreFile
if (Test-Path $remoteFile) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $copyDir  = Join-Path $scoresDir ($nameNoExt + ' - Copy')
    $copyMscx = Join-Path $copyDir  ($nameNoExt + ' - Copy.mscx')
    if (-not (Test-Path $copyDir)) { New-Item -ItemType Directory -Path $copyDir | Out-Null }
    try {
        $zip   = [System.IO.Compression.ZipFile]::OpenRead($remoteFile)
        $entry = $zip.Entries | Where-Object { $_.Name -like '*.mscx' } | Select-Object -First 1
        if ($entry) {
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $copyMscx, $true)
            $success = $true
        }
        $zip.Dispose()
    } catch {}
}
git worktree remove --force $tmpTree 2>&1 | Out-Null

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
if ($success) {
    [System.Windows.Forms.MessageBox]::Show(
        'Remote changes were found for "' + $nameNoExt + '".' + [char]13 + [char]10 + [char]13 + [char]10 +
        'The remote version has been saved to:' + [char]13 + [char]10 +
        '  ' + $copyMscx + [char]13 + [char]10 + [char]13 + [char]10 +
        'Please run MuseScore Diff to review differences, then run this plugin again to push.',
        'Unpulled Changes Detected',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    ) | Out-Null
} else {
    # Could not extract remote version — fall back to a normal push
    Start-Process $commitBat
}