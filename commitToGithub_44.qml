//==============================================
//  Commit to GitHub
//  Uses temp script + openUrlExternally (QProcess unreliable in MuseScore 4.x)
//==============================================

import QtQuick 2.0
import MuseScore 3.0
import Muse.UiComponents 1.0
import FileIO 3.0

MuseScore {
    id: commitPlugin
    title: "Commit to GitHub"
    categoryCode: "composing-arranging-tools"
    menuPath: "Plugins.Commit to GitHub"
    description: "Commit scores to GitHub"
    version: "2.2"
    requiresScore: true

    FileIO { id: fileIO }

    onRun: {
        if (typeof curScore == 'undefined' || curScore == null) { quit(); return; }

        var scoreName = curScore.scoreName;

        // ---- resolve paths ----
        var pluginDirUrl = Qt.resolvedUrl(".");
        var pluginDirStr = (pluginDirUrl.toString
            ? pluginDirUrl.toString()
            : ("" + pluginDirUrl)).replace("file:///", "").replace(/\/$/, "");

        var lastSlash = Math.max(pluginDirStr.lastIndexOf("/"), pluginDirStr.lastIndexOf("\\"));
        var pluginDir = lastSlash > 0 ? pluginDirStr.substring(0, lastSlash) : pluginDirStr;
        if (pluginDir.indexOf("Plugins") === -1) pluginDir = pluginDirStr;

        var ms4Dir    = pluginDir.substring(0, Math.max(pluginDir.lastIndexOf("/"), pluginDir.lastIndexOf("\\")));
        var scoresDir = ms4Dir + "/Scores";

        var linkFile  = pluginDir + "/github_link.txt";
        var commitBat = pluginDir + "/musescore-git-push.bat";
        var setupPs1  = pluginDir + "/musescore-git-setup.ps1";
        var setupBat  = pluginDir + "/musescore-git-setup.bat";

        var scoresDirWin = scoresDir.replace(/\//g, "\\");
        var commitBatWin = commitBat.replace(/\//g, "\\");
        var linkFileWin  = linkFile.replace(/\//g, "\\");
        var setupPs1Win  = setupPs1.replace(/\//g, "\\");

        var lastDot   = scoreName.lastIndexOf(".");
        var nameNoExt = lastDot >= 0 ? scoreName.substring(0, lastDot) : scoreName;
        var scoreFile = nameNoExt + ".mscz";

        // ---- diff marker: created by MuseScore Diff at <Scores>/<Name>/<Name>_diff.log.txt ----
        var diffLogTxt = scoresDir + "/" + nameNoExt + "/" + nameNoExt + "_diff.log.txt";
        fileIO.source = diffLogTxt;
        var hasDiffLogTxt = fileIO.exists();

        // ---- always write the normal + force commit bats ----
        var batLines = [
            "@echo off",
            "cd /d \"" + scoresDirWin + "\"",
            "if exist \"" + scoreName + ".mscz\" git add \"" + scoreName + ".mscz\"",
            "if exist \"" + scoreName + ".mscx\" git add \"" + scoreName + ".mscx\"",
            "git commit -m \"Commit from MuseScore plugin: " + scoreName + "\"",
            "git push"
        ];
        batLines.push("pause");

        fileIO.source = commitBat;
        if (fileIO.exists()) fileIO.remove();
        fileIO.write(batLines.join("\r\n"));

        var forceBat = pluginDir + "/musescore-git-push-force.bat";
        var forceBatWin = forceBat.replace(/\//g, "\\");
        fileIO.source = forceBat;
        if (fileIO.exists()) fileIO.remove();
        fileIO.write([
            "@echo off",
            "cd /d \"" + scoresDirWin + "\"",
            "if exist \"" + scoreName + ".mscz\" git add \"" + scoreName + ".mscz\"",
            "if exist \"" + scoreName + ".mscx\" git add \"" + scoreName + ".mscx\"",
            "git commit -m \"Commit from MuseScore plugin: " + scoreName + "\"",
            "git push --force",
            "pause"
        ].join("\r\n"));

        // ---- Step 1: check for github_link.txt in QML (no terminal opened yet) ----
        fileIO.source = linkFile;
        var needsSetup = !fileIO.exists();

        var checkPs1    = pluginDir + "/musescore-git-check.ps1";
        var checkBat    = pluginDir + "/musescore-git-check.bat";
        var checkPs1Win = checkPs1.replace(/\//g, "\\");

        if (needsSetup) {
            // ---- Step 2: show popup asking for the repo URL ----
            // On OK: save github_link.txt, clone the repo, then launch the commit bat.
            fileIO.source = setupPs1;
            if (fileIO.exists()) fileIO.remove();
            fileIO.write([
"param($scoresDir, $linkFile, $commitBat)",
"Add-Type -AssemblyName System.Windows.Forms",
"Add-Type -AssemblyName System.Drawing",
"[System.Windows.Forms.Application]::EnableVisualStyles()",
"",
"$form = New-Object System.Windows.Forms.Form",
"$form.Text = 'Commit to GitHub \u2014 First-time Setup'",
"$form.Size = New-Object System.Drawing.Size(520, 185)",
"$form.StartPosition = 'CenterScreen'",
"$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog",
"$form.MaximizeBox = $false; $form.MinimizeBox = $false",
"$form.BackColor = [System.Drawing.Color]::FromArgb(245,245,245)",
"",
"$lbl = New-Object System.Windows.Forms.Label",
"$lbl.Text = 'No GitHub link found. Please provide the repository URL:'",
"$lbl.Font = New-Object System.Drawing.Font('Segoe UI', 10)",
"$lbl.Location = New-Object System.Drawing.Point(16, 16)",
"$lbl.Size = New-Object System.Drawing.Size(480, 36)",
"",
"$txt = New-Object System.Windows.Forms.TextBox",
"$txt.Font = New-Object System.Drawing.Font('Segoe UI', 10)",
"$txt.Location = New-Object System.Drawing.Point(16, 58)",
"$txt.Size = New-Object System.Drawing.Size(480, 28)",
"$txt.PlaceholderText = 'https://github.com/user/repo.git'",
"",
"$ok = New-Object System.Windows.Forms.Button",
"$ok.Text = 'Clone & Commit'",
"$ok.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)",
"$ok.Location = New-Object System.Drawing.Point(270, 104)",
"$ok.Size = New-Object System.Drawing.Size(130, 34)",
"$ok.BackColor = [System.Drawing.Color]::FromArgb(30,107,46)",
"$ok.ForeColor = [System.Drawing.Color]::White",
"$ok.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat",
"$ok.Add_Click({",
"    $url = $txt.Text.Trim()",
"    if ($url -eq '') { [System.Windows.Forms.MessageBox]::Show('Please enter a URL.', 'Error'); return }",
"    $form.Hide()",
"    Set-Content -Path $linkFile -Value $url -Encoding UTF8",
"    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('ms_clone_' + [System.Guid]::NewGuid().ToString('N').Substring(0,8))",
"    & git clone $url \"$tmp\"",
"    if (Test-Path \"$tmp\\.git\") {",
"        if (Test-Path \"$scoresDir\\.git\") { Remove-Item -Recurse -Force \"$scoresDir\\.git\" }",
"        Move-Item \"$tmp\\.git\" \"$scoresDir\\.git\"",
"        Remove-Item -Recurse -Force $tmp",
"    } else {",
"        [System.Windows.Forms.MessageBox]::Show('git clone failed. Check the URL and your credentials.', 'Clone Failed')",
"        Remove-Item -Path $linkFile -Force",
"        $form.Show(); return",
"    }",
"    Start-Process -FilePath $commitBat",
"    $form.Close()",
"})",
"",
"$cancel = New-Object System.Windows.Forms.Button",
"$cancel.Text = 'Cancel'",
"$cancel.Font = New-Object System.Drawing.Font('Segoe UI', 10)",
"$cancel.Location = New-Object System.Drawing.Point(416, 104)",
"$cancel.Size = New-Object System.Drawing.Size(82, 34)",
"$cancel.Add_Click({ $form.Close() })",
"",
"$form.Controls.AddRange(@($lbl, $txt, $ok, $cancel))",
"$form.ShowDialog() | Out-Null"
            ].join("\n"));

            // Launcher bat — needed so Qt.openUrlExternally can open the PS1
            fileIO.source = setupBat;
            if (fileIO.exists()) fileIO.remove();
            fileIO.write(
                "@echo off\r\n" +
                "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden" +
                " -File \"" + setupPs1Win + "\"" +
                " \"" + scoresDirWin + "\"" +
                " \"" + linkFileWin + "\"" +
                " \"" + commitBatWin + "\"\r\n"
            );

            Qt.openUrlExternally("file:///" + setupBat.replace(/\\/g, "/"));
        } else {
            // ---- Step 3: link exists — check for unpulled changes first ----
            fileIO.source = checkPs1;
            if (fileIO.exists()) fileIO.remove();
            fileIO.write([
"param($scoresDir, $scoreFile, $nameNoExt, $commitBat, $forceBat, $diffLogTxt)",
"Set-Location $scoresDir",
"",
"# Fetch silently; ignore errors (offline, no remote, etc.)",
"git fetch origin 2>&1 | Out-Null",
"",
"# Resolve upstream branch; if none is set, skip the check and commit",
"$upstream = git rev-parse --abbrev-ref '@{upstream}' 2>&1",
"if ($LASTEXITCODE -ne 0) { Start-Process $commitBat; exit }",
"",
"# Any commits on remote that touch this file and aren't in local HEAD?",
"$unpulled = git log \"HEAD..${upstream}\" --oneline -- $scoreFile 2>&1",
"if ($LASTEXITCODE -ne 0 -or -not $unpulled) { Start-Process $commitBat; exit }",
"",
"# Remote has changes for this file. If we've already diffed (marker exists), force-push local to replace remote.",
"if (Test-Path $diffLogTxt) { Start-Process $forceBat; exit }",
"",
"# Remote has changes — check out that tree into a temp worktree",
"$tmpTree = Join-Path ([System.IO.Path]::GetTempPath()) ('ms_pull_' + [System.Guid]::NewGuid().ToString('N').Substring(0,8))",
"git worktree add --detach $tmpTree $upstream 2>&1 | Out-Null",
"",
"$success = $false",
"$remoteFile = Join-Path $tmpTree $scoreFile",
"if (Test-Path $remoteFile) {",
"    Add-Type -AssemblyName System.IO.Compression.FileSystem",
"    $copyDir  = Join-Path $scoresDir ($nameNoExt + ' - Copy')",
"    $copyMscx = Join-Path $copyDir  ($nameNoExt + ' - Copy.mscx')",
"    if (-not (Test-Path $copyDir)) { New-Item -ItemType Directory -Path $copyDir | Out-Null }",
"    try {",
"        $zip   = [System.IO.Compression.ZipFile]::OpenRead($remoteFile)",
"        $entry = $zip.Entries | Where-Object { $_.Name -like '*.mscx' } | Select-Object -First 1",
"        if ($entry) {",
"            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $copyMscx, $true)",
"            $success = $true",
"        }",
"        $zip.Dispose()",
"    } catch {}",
"}",
"git worktree remove --force $tmpTree 2>&1 | Out-Null",
"",
"if ($success) {",
"    Add-Type -AssemblyName System.Windows.Forms",
"    Add-Type -AssemblyName System.Drawing",
"    [System.Windows.Forms.Application]::EnableVisualStyles()",
"    [System.Windows.Forms.MessageBox]::Show(",
"        'Remote changes were found for \"' + $nameNoExt + '\".' + [char]13 + [char]10 + [char]13 + [char]10 +",
"        'The remote version has been saved to:' + [char]13 + [char]10 +",
"        '  ' + (Join-Path $copyDir ($nameNoExt + ' - Copy.mscx')) + [char]13 + [char]10 + [char]13 + [char]10 +",
"        'Please run MuseScore Diff to review differences before committing.',",
"        'Unpulled Changes Detected',",
"        [System.Windows.Forms.MessageBoxButtons]::OK,",
"        [System.Windows.Forms.MessageBoxIcon]::Warning",
"    ) | Out-Null",
"} else {",
"    # Could not extract remote version — fall back to committing",
"    Start-Process $commitBat",
"}"
            ].join("\n"));

            fileIO.source = checkBat;
            if (fileIO.exists()) fileIO.remove();
            fileIO.write(
                "@echo off\r\n" +
                "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden" +
                " -File \"" + checkPs1Win + "\"" +
                " \"" + scoresDirWin + "\"" +
                " \"" + scoreFile + "\"" +
                " \"" + nameNoExt + "\"" +
                " \"" + commitBatWin + "\"" +
                " \"" + forceBatWin + "\"" +
                " \"" + diffLogTxt.replace(/\//g, "\\") + "\"\r\n"
            );

            Qt.openUrlExternally("file:///" + checkBat.replace(/\\/g, "/"));
        }

        // Setup files are loaded by their processes well within 1.5 s.
        // commitBat is kept alive when needsSetup — the PS1 launches it after cloning.
        var cleanup = Qt.createQmlObject('import QtQuick 2.0; Timer { interval: 1500; repeat: false }', commitPlugin, "cleanupTimer");
        cleanup.triggered.connect(function() {
            fileIO.source = setupBat;  if (fileIO.exists()) fileIO.remove();
            fileIO.source = setupPs1;  if (fileIO.exists()) fileIO.remove();
            fileIO.source = checkPs1;  if (fileIO.exists()) fileIO.remove();
            fileIO.source = checkBat;  if (fileIO.exists()) fileIO.remove();
            fileIO.source = forceBat; if (fileIO.exists()) fileIO.remove();
            if (!needsSetup) { fileIO.source = commitBat; if (fileIO.exists()) fileIO.remove(); }
            quit();
        });
        cleanup.start();
    }
}