//==============================================
//  Pull from GitHub
//  Pulls latest changes for the Scores repo.
//  If pull can't merge cleanly, extracts remote copy for MuseScore Diff.
//==============================================

import QtQuick 2.0
import MuseScore 3.0
import Muse.UiComponents 1.0
import FileIO 3.0

MuseScore {
    id: pullPlugin
    title: "Pull from GitHub"
    categoryCode: "composing-arranging-tools"
    menuPath: "Plugins.Pull from GitHub"
    description: "Pull latest score from GitHub (diff if needed)"
    version: "1.0"
    requiresScore: true

    FileIO { id: fileIO }

    MessageDialog {
        id: msg
        title: "Pull from GitHub"
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

        var scoresDirWin = scoresDir.replace(/\//g, "\\");

        // Per-run script name (temporary)
        var runTag = (new Date()).getTime().toString();
        var pullBat = pluginDir + "/musescore-git-pull-" + runTag + ".bat";

        // ---- only handle .mscz ----
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
                msg.text =
                    "This plugin only supports .mscz files.\n\n" +
                    "Please use File → Save As… and save \"" + nameNoExt + "\" as a .mscz file, then run this plugin again.";
            } else {
                msg.text =
                    "Couldn't find \"" + nameNoExt + ".mscz\" in your Scores folder.\n\n" +
                    "Please save the score as a .mscz file, then run this plugin again.";
            }
            msg.visible = true;
            return;
        }

        // Ensure Scores is a git repo
        fileIO.source = scoresDir + "/.git";
        if (!fileIO.exists()) {
            msg.text =
                "Your Scores folder doesn't appear to be a git repository yet.\n\n" +
                "Run \"Commit to GitHub\" first-time setup, then try Pull again.";
            msg.visible = true;
            return;
        }

        // ---- write pull bat ----
        fileIO.source = pullBat;
        if (fileIO.exists()) fileIO.remove();

        var pullBatWin = pullBat.replace(/\//g, "\\");
        var scoreFile = nameNoExt + ".mscz";

        fileIO.write([
            "@echo off",
            "setlocal EnableExtensions",
            "cd /d \"" + scoresDirWin + "\"",
            "",
            "set \"SCORE=" + nameNoExt.replace(/\"/g, "") + "\"",
            "set \"SCOREFILE=%SCORE%.mscz\"",
            "",
            "git fetch origin >nul 2>nul",
            "",
            "for /f \"delims=\" %%U in ('git rev-parse --abbrev-ref \"@{upstream}\" 2^>nul') do set \"UPSTREAM=%%U\"",
            "if not defined UPSTREAM goto doPull",
            "",
            "REM If remote has changes for this score, try to pull; if it conflicts, fall back to diff.",
            "for /f \"delims=\" %%L in ('git log \"HEAD..%UPSTREAM%\" --oneline -- \"%SCOREFILE%\" 2^>nul') do (set \"REMOTE_AHEAD=1\" & goto doPull)",
            "",
            ":doPull",
            "git pull --no-edit",
            "if errorlevel 1 goto pullFailed",
            "",
            "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command \"Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.MessageBox]::Show('Pull completed successfully.','Pull from GitHub',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null\"",
            "goto end",
            "",
            ":pullFailed",
            "REM Abort any in-progress merge so the working tree is clean.",
            "git merge --abort >nul 2>nul",
            "",
            "REM Extract remote version to Scores/<Name> - Copy/<Name> - Copy.mscx for MuseScore Diff.",
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
                "[System.Windows.Forms.MessageBox]::Show('Automatic merge was not possible for \"' + $env:SCORE + '\".' + $nl + $nl + " +
                    "'The remote version has been saved to:' + $nl + '  ' + $copyMscx + $nl + $nl + " +
                    "'Please run MuseScore Diff to review differences, then commit/push.','Manual Diff Required', " +
                    "[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null " +
            "} catch {}\"",
            "",
            ":end",
            "del \"" + pullBatWin + "\""
        ].join("\r\n"));

        Qt.openUrlExternally("file:///" + pullBat.replace(/\\/g, "/"));
        quit();
    }
}
