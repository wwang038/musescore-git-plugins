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

    MessageDialog {
        id: msgUnsupported
        title: "Commit to GitHub"
        visible: false
        onAccepted: quit()
    }

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

        // Per-run script names to avoid overwriting a still-running cmd.exe instance.
        // (Some machines block launching .ps1/.vbs via openUrlExternally; .bat is the most compatible.)
        var runTag = (new Date()).getTime().toString();
        var commitBat = pluginDir + "/musescore-git-push-" + runTag + ".bat";
        var setupPs1  = pluginDir + "/musescore-git-setup-" + runTag + ".ps1";
        var setupBat  = pluginDir + "/musescore-git-setup-" + runTag + ".bat";

        var scoresDirWin = scoresDir.replace(/\//g, "\\");
        var commitBatWin = commitBat.replace(/\//g, "\\");
        var linkFileWin  = linkFile.replace(/\//g, "\\");
        var setupPs1Win  = setupPs1.replace(/\//g, "\\");

        // Invariant: only handle .mscz. If the score is only present as .mscx, instruct user to Save As .mscz.
        var lastDot = scoreName.lastIndexOf(".");
        var nameNoExt = lastDot >= 0 ? scoreName.substring(0, lastDot) : scoreName;

        var msczPath = scoresDir + "/" + nameNoExt + ".mscz";
        var mscxPath = scoresDir + "/" + nameNoExt + ".mscx";

        fileIO.source = msczPath;
        var hasMscz = fileIO.exists();
        fileIO.source = mscxPath;
        var hasMscx = fileIO.exists();

        if (!hasMscz) {
            if (hasMscx) {
                msgUnsupported.text =
                    "This plugin only supports .mscz files.\n\n" +
                    "Please use File → Save As… and save \"" + nameNoExt + "\" as a .mscz file, then run this plugin again on that .mscz.";
            } else {
                msgUnsupported.text =
                    "Couldn't find \"" + nameNoExt + ".mscz\" in your Scores folder.\n\n" +
                    "Please save the score as a .mscz file, then run this plugin again.";
            }
            msgUnsupported.visible = true;
            return;
        }

        // Diff marker written by musescore diff.qml (flat layout): Scores/<Name>_diff.log.txt
        var diffLogTxt = scoresDir + "/" + nameNoExt + "_diff.log.txt";

        // ---- always write the commit bat (includes git fetch + remote-ahead check) ----
        fileIO.source = commitBat;
        if (fileIO.exists()) fileIO.remove();
        fileIO.write([
            "@echo off",
            "setlocal EnableExtensions",
            "cd /d \"" + scoresDirWin + "\"",
            "",
            "set \"SCORE=" + nameNoExt.replace(/"/g, "") + "\"",
            "set \"SCOREFILE=%SCORE%.mscz\"",
            "set \"DIFFLOG=" + diffLogTxt.replace(/\//g, "\\") + "\"",
            "",
            "git fetch origin >nul 2>nul",
            "",
            "if exist \"%DIFFLOG%\" goto doPushForce",
            "",
            "for /f \"delims=\" %%U in ('git rev-parse --abbrev-ref \"@{upstream}\" 2^>nul') do set \"UPSTREAM=%%U\"",
            "if not defined UPSTREAM goto doPushNormal",
            "",
            "for /f \"delims=\" %%L in ('git log \"HEAD..%UPSTREAM%\" --oneline -- \"%SCOREFILE%\" 2^>nul') do (set \"REMOTE_AHEAD=1\" & goto afterRemoteCheck)",
            ":afterRemoteCheck",
            "if not defined REMOTE_AHEAD goto doPushNormal",
            "",
            "REM Remote is ahead and no diff marker: extract remote copy for MuseScore Diff and stop.",
            "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command \"try { " +
                "$sd = (Get-Location).Path; " +
                "$nl = [Environment]::NewLine; " +
                "$up = git rev-parse --abbrev-ref '@{upstream}' 2>$null; " +
                "if (-not $up) { exit }; " +
                "$tmp = Join-Path ([IO.Path]::GetTempPath()) ('ms_pull_' + [Guid]::NewGuid().ToString('N').Substring(0,8)); " +
                "git worktree add --detach $tmp $up 2>$null | Out-Null; " +
                "$remoteFile = Join-Path $tmp $env:SCOREFILE; " +
                "$copyDir = Join-Path $sd ($env:SCORE + ' - Copy'); " +
                "$copyMscx = Join-Path $copyDir ($env:SCORE + ' - Copy.mscx'); " +
                "if (Test-Path $remoteFile) { " +
                    "Add-Type -AssemblyName System.IO.Compression.FileSystem; " +
                    "if (-not (Test-Path $copyDir)) { New-Item -ItemType Directory -Path $copyDir | Out-Null }; " +
                    "$zip = [IO.Compression.ZipFile]::OpenRead($remoteFile); " +
                    "$entry = $zip.Entries | Where-Object { $_.Name -like '*.mscx' } | Select-Object -First 1; " +
                    "if ($entry) { [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $copyMscx, $true) }; " +
                    "$zip.Dispose(); " +
                "}; " +
                "git worktree remove --force $tmp 2>$null | Out-Null; " +
                "Add-Type -AssemblyName System.Windows.Forms; " +
                "[System.Windows.Forms.MessageBox]::Show('Remote changes were found for \"' + $env:SCORE + '\".' + $nl + $nl + " +
                    "'The remote version has been saved to:' + $nl + '  ' + $copyMscx + $nl + $nl + " +
                    "'Please run MuseScore Diff to review differences, then run this plugin again to push.', 'Unpulled Changes Detected', " +
                    "[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null " +
            "} catch {}\"",
            "goto end",
            "",
            ":doPushNormal",
            "if exist \"%SCOREFILE%\" git add \"%SCOREFILE%\"",
            "git commit -m \"Commit from MuseScore plugin: %SCORE%\"",
            "git push",
            "goto end",
            "",
            ":doPushForce",
            "if exist \"%SCOREFILE%\" git add \"%SCOREFILE%\"",
            "git commit -m \"Commit from MuseScore plugin: %SCORE%\"",
            "git push --force",
            "if exist \"%DIFFLOG%\" del \"%DIFFLOG%\"",
            "goto end",
            "",
            ":end",
            "pause"
        ].join("\r\n"));

        // ---- Step 1: check for github_link.txt in QML (no terminal opened yet) ----
        fileIO.source = linkFile;
        var needsSetup = !fileIO.exists();

        if (needsSetup) {
            // ---- Step 2: show popup asking for the repo URL ----
            // On OK: save github_link.txt, clone the repo, then launch the commit bat.
            fileIO.source = setupPs1;
            if (fileIO.exists()) fileIO.remove();
            fileIO.write([
"param($scoresDir, $linkFile, $nameNoExt, $diffLogTxt)",
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
"    Set-Location $scoresDir",
"    $scoreFile = ($nameNoExt + '.mscz')",
"    if (Test-Path $scoreFile) { git add -- $scoreFile | Out-Null }",
"    $hasStaged = $false",
"    git diff --cached --quiet 2>$null; if ($LASTEXITCODE -ne 0) { $hasStaged = $true }",
"    if ($hasStaged) { git commit -m (\"Commit from MuseScore plugin: \" + $nameNoExt) | Out-Null }",
"    git push | Out-Null",
"    if (Test-Path $diffLogTxt) { Remove-Item -LiteralPath $diffLogTxt -Force -ErrorAction SilentlyContinue }",
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
"$form.ShowDialog() | Out-Null",
"Remove-Item -LiteralPath $MyInvocation.MyCommand.Path -Force -ErrorAction SilentlyContinue"
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
                " \"" + nameNoExt + "\"" +
                " \"" + diffLogTxt.replace(/\//g, "\\") + "\"\r\n" +
                "del \"%~f0\"\r\n"
            );

            Qt.openUrlExternally("file:///" + setupBat.replace(/\\/g, "/"));
        } else {
            // ---- Step 3: link exists — run the commit bat which performs fetch/check/push ----
            Qt.openUrlExternally("file:///" + commitBat.replace(/\\/g, "/"));
        }

        // Scripts self-delete after launch to avoid timing races.
        quit();
    }
}