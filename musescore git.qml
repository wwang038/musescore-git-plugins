//==============================================
//  MuseScore Diff v3
//  Two-pass LCS diff over normalized measure signatures.
//  Debug: always writes musescore-diff-debug.txt next to this file.
//==============================================

import QtQuick 2.0
import MuseScore 3.0
import Muse.UiComponents 1.0
import FileIO 3.0

MuseScore {
    id: diffPlugin
    title: "MuseScore Diff"
    categoryCode: "composing-arranging-tools"
    menuPath: "Plugins.MuseScore Diff"
    description: "LCS measure diff against NAME - Copy"
    version: "3.0"
    requiresScore: true

    FileIO { id: fileIO }

    // Write text to a file (overwrites).
    function writeFile(path, text) {
        fileIO.source = path;
        if (fileIO.exists()) fileIO.remove();
        fileIO.write(text);
    }

    // Append a line to the debug log.
    function dbg(log, msg) { log.push(msg); }

    onRun: {
        var log = [];
        dbg(log, "onRun started");

        // ---- resolve paths ------------------------------------------------
        var pluginDirUrl = Qt.resolvedUrl(".");
        var pluginDirStr = (pluginDirUrl.toString
            ? pluginDirUrl.toString()
            : ("" + pluginDirUrl)).replace("file:///", "").replace(/\/$/, "");
        dbg(log, "pluginDirStr=" + pluginDirStr);

        var lastSlash = Math.max(pluginDirStr.lastIndexOf("/"), pluginDirStr.lastIndexOf("\\"));
        // pluginDir is the Plugins folder itself
        var pluginDir = lastSlash > 0 ? pluginDirStr.substring(0, lastSlash) : pluginDirStr;
        // If Qt.resolvedUrl(".") already points to the Plugins folder, use it directly
        if (pluginDir.indexOf("Plugins") === -1) {
            pluginDir = pluginDirStr;
        }
        dbg(log, "pluginDir=" + pluginDir);

        var ms4Dir    = pluginDir.substring(0, Math.max(pluginDir.lastIndexOf("/"), pluginDir.lastIndexOf("\\")));
        var scoresDir = ms4Dir + "/Scores";
        dbg(log, "ms4Dir=" + ms4Dir);
        dbg(log, "scoresDir=" + scoresDir);

        var debugPath = pluginDir + "/musescore-diff-debug.txt";

        // ---- score check -------------------------------------------------
        if (typeof curScore === 'undefined' || curScore === null) {
            dbg(log, "ABORT: curScore undefined/null");
            writeFile(debugPath, log.join("\n"));
            Qt.openUrlExternally("file:///" + debugPath.replace(/\\/g, "/"));
            quit(); return;
        }
        dbg(log, "curScore OK");

        var scoreName = curScore.scoreName;
        dbg(log, "scoreName=" + scoreName);
        if (!scoreName || scoreName === "") {
            dbg(log, "ABORT: empty scoreName");
            writeFile(debugPath, log.join("\n"));
            Qt.openUrlExternally("file:///" + debugPath.replace(/\\/g, "/"));
            quit(); return;
        }

        var lastDot   = scoreName.lastIndexOf(".");
        var nameNoExt = lastDot >= 0 ? scoreName.substring(0, lastDot) : scoreName;
        dbg(log, "nameNoExt=" + nameNoExt);

        var origPath = scoresDir + "/" + nameNoExt + "/" + nameNoExt + ".mscx";
        var copyPath = scoresDir + "/" + nameNoExt + " - Copy/" + nameNoExt + " - Copy.mscx";
        var outPath  = scoresDir + "/" + nameNoExt + "/" + nameNoExt + "_diff.mscx";
        dbg(log, "origPath=" + origPath);
        dbg(log, "copyPath=" + copyPath);
        dbg(log, "outPath="  + outPath);

        fileIO.source = origPath;
        if (!fileIO.exists()) {
            dbg(log, "ABORT: original .mscx not found");
            writeFile(debugPath, log.join("\n"));
            Qt.openUrlExternally("file:///" + debugPath.replace(/\\/g, "/"));
            quit(); return;
        }
        dbg(log, "orig exists OK");

        fileIO.source = copyPath;
        if (!fileIO.exists()) {
            dbg(log, "ABORT: copy .mscx not found");
            writeFile(debugPath, log.join("\n"));
            Qt.openUrlExternally("file:///" + debugPath.replace(/\\/g, "/"));
            quit(); return;
        }
        dbg(log, "copy exists OK");

        // ---- build PowerShell script -------------------------------------
        // All JS strings here are double-quoted.
        // PowerShell single-quoted strings ( '...' ) sit fine inside JS double-quoted strings.
        // PowerShell double-quoted strings that contain literal " are written as \" in JS.
        var ps1 = [
"param($orig, $copy, $out)",
"",
"# Write all errors to log so we can see them",
"$logPath = [System.IO.Path]::ChangeExtension($out, '.log.txt')",
"function Log($msg) { Add-Content -Path $logPath -Value $msg }",
"Log 'PS started'",
"",
"try {",
"",
"$ox = [xml](Get-Content -Path $orig -Raw -Encoding UTF8)",
"$cx = [xml](Get-Content -Path $copy -Raw -Encoding UTF8)",
"Log 'XML loaded'",
"$so = $ox.museScore.Score",
"$sc = $cx.museScore.Score",
"$staffsO = @($so.SelectNodes('Staff[@id]'))",
"$staffsC = @($sc.SelectNodes('Staff[@id]'))",
"Log ('staffsO=' + $staffsO.Count + ' staffsC=' + $staffsC.Count)",
"if ($staffsO.Count -eq 0 -or $staffsC.Count -eq 0) { $ox.Save($out); Start-Process $out; exit }",
"",
"# ---- token helpers ------------------------------------------------",
"",
"function Get-Duration($node) {",
"    $dt = $node.SelectSingleNode('durationType')",
"    if (-not $dt) { return '?' }",
"    $dots = $node.SelectSingleNode('dots')",
"    if ($dots -and [int]$dots.InnerText -gt 0) { return $dt.InnerText + ('.' * [int]$dots.InnerText) }",
"    return $dt.InnerText",
"}",
"",
"function Get-PitchName($midi) {",
"    $names = @('C','Cs','D','Ds','E','F','Fs','G','Gs','A','As','B')",
"    $p = [int]$midi",
"    return $names[$p % 12] + ([Math]::Floor($p / 12) - 1)",
"}",
"",
"function Get-Token($node) {",
"    switch ($node.Name) {",
"        'Rest' { return 'R:' + (Get-Duration $node) }",
"        'Chord' {",
"            $pitches = @($node.SelectNodes('Note') | ForEach-Object {",
"                $pn = $_.SelectSingleNode('pitch')",
"                if ($pn) { Get-PitchName $pn.InnerText } else { '?' }",
"            } | Sort-Object)",
"            $hasTie = $node.OuterXml -match 'type=.Tie'",
"            $tie = if ($hasTie) { ':tie' } else { '' }",
"            return 'C:' + ($pitches -join ',') + ':' + (Get-Duration $node) + $tie",
"        }",
"        'Dynamic' {",
"            $s = $node.SelectSingleNode('subtype')",
"            return 'D:' + $(if ($s) { $s.InnerText } else { '?' })",
"        }",
"        'Harmony' {",
"            $n = $node.SelectSingleNode('name')",
"            return 'H:' + $(if ($n) { $n.InnerText } else { $node.InnerText.Trim() })",
"        }",
"        'Lyrics' {",
"            $t = $node.SelectSingleNode('text')",
"            return 'L:' + $(if ($t) { $t.InnerText } else { '?' })",
"        }",
"        'KeySig'  {",
"            $k = $node.SelectSingleNode('concertKey')",
"            return 'K:' + $(if ($k) { $k.InnerText } else { '?' })",
"        }",
"        'TimeSig' {",
"            $n = $node.SelectSingleNode('sigN'); $d = $node.SelectSingleNode('sigD')",
"            return 'T:' + $(if ($n -and $d) { $n.InnerText + '/' + $d.InnerText } else { '?' })",
"        }",
"        'Tempo' {",
"            $t = $node.SelectSingleNode('tempo')",
"            return 'Tm:' + $(if ($t) { $t.InnerText } else { '?' })",
"        }",
"        default { return $null }",
"    }",
"}",
"",
"function Get-Sig($meas) {",
"    $parts = @()",
"    $voices = @($meas.ChildNodes | Where-Object { $_.Name -eq 'voice' })",
"    for ($vi = 0; $vi -lt $voices.Count; $vi++) {",
"        $ev = @()",
"        foreach ($ch in @($voices[$vi].ChildNodes | Where-Object { $_.NodeType -eq 'Element' })) {",
"            $tok = Get-Token $ch",
"            if ($tok) { $ev += '[' + $tok + ']' }",
"        }",
"        if ($ev.Count -gt 0) { $parts += 'v' + ($vi+1) + ':' + ($ev -join '') }",
"    }",
"    return ($parts -join '|')",
"}",
"",
"# ---- LCS ----------------------------------------------------------",
"",
"# Get-LCS uses a 1D flat array (W = m+1 columns) to avoid PowerShell's",
"# ambiguous comma-in-subscript parsing that breaks with 2D int[,] arrays.",
"function Get-LCS($a, $b) {",
"    $n = $a.Count; $m = $b.Count; $W = $m + 1",
"    $dp = New-Object 'int[]' (($n+1)*$W)",
"    for ($i = $n-1; $i -ge 0; $i--) {",
"        for ($j = $m-1; $j -ge 0; $j--) {",
"            if ($a[$i] -eq $b[$j]) {",
"                $dp[$i*$W+$j] = 1 + $dp[($i+1)*$W+($j+1)]",
"            } else {",
"                $u = $dp[($i+1)*$W+$j]",
"                $l = $dp[$i*$W+($j+1)]",
"                $dp[$i*$W+$j] = if ($u -ge $l) { $u } else { $l }",
"            }",
"        }",
"    }",
"    $ops = [System.Collections.Generic.List[object]]::new()",
"    $i = 0; $j = 0",
"    while ($i -lt $n -and $j -lt $m) {",
"        if ($a[$i] -eq $b[$j]) {",
"            $ops.Add([pscustomobject]@{ op='equal';  oi=$i; ci=$j }); $i++; $j++",
"        } elseif ($dp[($i+1)*$W+$j] -ge $dp[$i*$W+($j+1)]) {",
"            $ops.Add([pscustomobject]@{ op='delete'; oi=$i; ci=$null }); $i++",
"        } else {",
"            $ops.Add([pscustomobject]@{ op='insert'; oi=$null; ci=$j }); $j++",
"        }",
"    }",
"    while ($i -lt $n) { $ops.Add([pscustomobject]@{ op='delete'; oi=$i; ci=$null }); $i++ }",
"    while ($j -lt $m) { $ops.Add([pscustomobject]@{ op='insert'; oi=$null; ci=$j }); $j++ }",
"    return $ops",
"}",
"",
"function Merge-Ops($ops) {",
"    $out = [System.Collections.Generic.List[object]]::new()",
"    $k = 0",
"    while ($k -lt $ops.Count) {",
"        if ($k+1 -lt $ops.Count -and $ops[$k].op -eq 'delete' -and $ops[$k+1].op -eq 'insert') {",
"            $out.Add([pscustomobject]@{ op='replace'; oi=$ops[$k].oi; ci=$ops[$k+1].ci })",
"            $k += 2",
"        } else { $out.Add($ops[$k]); $k++ }",
"    }",
"    return $out",
"}",
"",
"# ---- coloring -----------------------------------------------------",
"",
"function Set-Color($doc, $node, $r, $g, $b) {",
"    $col = $doc.CreateElement('color')",
"    $col.SetAttribute('r',$r); $col.SetAttribute('g',$g)",
"    $col.SetAttribute('b',$b); $col.SetAttribute('a',255)",
"    $node.AppendChild($col) | Out-Null",
"}",
"",
"function Color-Measure($doc, $meas, $r, $g, $b) {",
"    foreach ($v in @($meas.ChildNodes | Where-Object { $_.Name -eq 'voice' })) {",
"        foreach ($el in @($v.ChildNodes | Where-Object { $_.NodeType -eq 'Element' })) {",
"            Set-Color $doc $el $r $g $b",
"        }",
"    }",
"}",
"",
"# Diff-Measure: color m and m' based on event-level LCS.",
"#   equal  events -> green  in BOTH m (orig) and m' (copy)",
"#   delete events -> red    in m  (existed in orig, gone in copy)",
"#   insert events -> red    in m' (new in copy, not in orig)",
"# Voices present in copy but not orig -> all green in m'.",
"# Voices present in orig but not copy -> all red in m.",
"function Diff-Measure($doc, $mOrig, $mCopy) {",
"    $voO = @($mOrig.ChildNodes | Where-Object { $_.Name -eq 'voice' })",
"    $voC = @($mCopy.ChildNodes | Where-Object { $_.Name -eq 'voice' })",
"    $maxVi = if ($voO.Count -gt $voC.Count) { $voO.Count } else { $voC.Count }",
"    for ($vi = 0; $vi -lt $maxVi; $vi++) {",
"        $hasO = $vi -lt $voO.Count",
"        $hasC = $vi -lt $voC.Count",
"        if ($hasO -and $hasC) {",
"            $elO = @($voO[$vi].ChildNodes | Where-Object { $_.NodeType -eq 'Element' })",
"            $elC = @($voC[$vi].ChildNodes | Where-Object { $_.NodeType -eq 'Element' })",
"            $tO  = @($elO | ForEach-Object { $t = Get-Token $_; if ($t) {$t} else {'__'} })",
"            $tC  = @($elC | ForEach-Object { $t = Get-Token $_; if ($t) {$t} else {'__'} })",
"            $evOps = Get-LCS $tO $tC",
"            foreach ($eop in $evOps) {",
"                if ($eop.op -eq 'equal') {",
"                    Set-Color $doc $elO[$eop.oi] 0 200 0",
"                    Set-Color $doc $elC[$eop.ci] 0 200 0",
"                } elseif ($eop.op -eq 'delete') {",
"                    Set-Color $doc $elO[$eop.oi] 220 0 0",
"                } elseif ($eop.op -eq 'insert') {",
"                    Set-Color $doc $elC[$eop.ci] 220 0 0",
"                }",
"            }",
"        } elseif ($hasO) {",
"            # Voice only in orig - all red",
"            foreach ($el in @($voO[$vi].ChildNodes | Where-Object { $_.NodeType -eq 'Element' })) { Set-Color $doc $el 220 0 0 }",
"        } elseif ($hasC) {",
"            # Voice only in copy - all green",
"            foreach ($el in @($voC[$vi].ChildNodes | Where-Object { $_.NodeType -eq 'Element' })) { Set-Color $doc $el 0 200 0 }",
"        }",
"    }",
"}",
"",
"# Make-RestPlaceholder: clone a measure and replace every Chord with a Rest",
"# of the same duration, giving a visual 'empty measure' for deleted positions.",
"function Make-RestPlaceholder($doc, $meas) {",
"    $clone = $meas.CloneNode($true)",
"    foreach ($v in @($clone.ChildNodes | Where-Object { $_.Name -eq 'voice' })) {",
"        $chords = @($v.ChildNodes | Where-Object { $_.Name -eq 'Chord' })",
"        foreach ($chord in $chords) {",
"            $rest = $doc.CreateElement('Rest')",
"            $dt = $chord.SelectSingleNode('durationType')",
"            if ($dt) { $rest.AppendChild($dt.CloneNode($true)) | Out-Null }",
"            $dots = $chord.SelectSingleNode('dots')",
"            if ($dots) { $rest.AppendChild($dots.CloneNode($true)) | Out-Null }",
"            $v.ReplaceChild($rest, $chord) | Out-Null",
"        }",
"    }",
"    return $clone",
"}",
"",
"function Insert-After($parent, $node, $anchor) {",
"    if ($anchor) { $parent.InsertAfter($node, $anchor) | Out-Null }",
"    else {",
"        $first = $parent.SelectSingleNode('Measure')",
"        if ($first) { $parent.InsertBefore($node, $first) | Out-Null }",
"        else        { $parent.AppendChild($node) | Out-Null }",
"    }",
"}",
"",
"# ---- cross-staff synchronized diff -----------------------------------",
"# Build a SINGLE combined-signature sequence across all staves so that the",
"# LCS alignment is shared. This guarantees that when any staff has a replace/",
"# insert/delete at measure position i, ALL staves insert the corresponding",
"# copy measure at that position, keeping vertical alignment intact.",
"",
"$idsO = @($staffsO | ForEach-Object { $_.id })",
"$idsC = @($staffsC | ForEach-Object { $_.id })",
"$commonIds = @($idsO | Where-Object { $idsC -contains $_ })",
"Log ('commonIds=' + ($commonIds -join ','))",
"",
"# Collect per-staff measure arrays and Staff XML nodes",
"$sMeasO = @{}   # staffId -> orig Measure[] ",
"$sMeasC = @{}   # staffId -> copy Measure[]",
"$sStO   = @{}   # staffId -> orig Staff node",
"$nMeasO = 0; $nMeasC = 0",
"foreach ($sid in $commonIds) {",
"    $stO = $staffsO | Where-Object { $_.id -eq $sid } | Select-Object -First 1",
"    $stC = $staffsC | Where-Object { $_.id -eq $sid } | Select-Object -First 1",
"    if (-not $stO -or -not $stC) { continue }",
"    $sMeasO[$sid] = @($stO.SelectNodes('Measure'))",
"    $sMeasC[$sid] = @($stC.SelectNodes('Measure'))",
"    $sStO[$sid]   = $stO",
"    if ($sMeasO[$sid].Count -gt $nMeasO) { $nMeasO = $sMeasO[$sid].Count }",
"    if ($sMeasC[$sid].Count -gt $nMeasC) { $nMeasC = $sMeasC[$sid].Count }",
"}",
"Log ('nMeasO=' + $nMeasO + ' nMeasC=' + $nMeasC)",
"",
"# Build combined signatures: one string per measure position, all staves joined",
"$sigO = @()",
"$sigC = @()",
"for ($i = 0; $i -lt $nMeasO; $i++) {",
"    $parts = @()",
"    foreach ($sid in $commonIds) {",
"        if ($sMeasO.ContainsKey($sid) -and $i -lt $sMeasO[$sid].Count) {",
"            $parts += Get-Sig $sMeasO[$sid][$i]",
"        } else { $parts += '' }",
"    }",
"    $sigO += $parts -join '||'",
"}",
"for ($j = 0; $j -lt $nMeasC; $j++) {",
"    $parts = @()",
"    foreach ($sid in $commonIds) {",
"        if ($sMeasC.ContainsKey($sid) -and $j -lt $sMeasC[$sid].Count) {",
"            $parts += Get-Sig $sMeasC[$sid][$j]",
"        } else { $parts += '' }",
"    }",
"    $sigC += $parts -join '||'",
"}",
"",
"$ops = Merge-Ops (Get-LCS $sigO $sigC)",
"Log ('total ops=' + $ops.Count + ' equal=' + (@($ops|Where-Object{$_.op -eq 'equal'}).Count) + ' replace=' + (@($ops|Where-Object{$_.op -eq 'replace'}).Count) + ' insert=' + (@($ops|Where-Object{$_.op -eq 'insert'}).Count) + ' delete=' + (@($ops|Where-Object{$_.op -eq 'delete'}).Count))",
"",
"# One anchor per staff so insertions chain correctly within each staff",
"$anchors = @{}",
"foreach ($sid in $commonIds) { $anchors[$sid] = $null }",
"",
"foreach ($op in $ops) {",
"    foreach ($sid in $commonIds) {",
"        $stO   = $sStO[$sid]",
"        $measO = $sMeasO[$sid]",
"        $measC = $sMeasC[$sid]",
"        switch ($op.op) {",
"            'equal' {",
"                if ($op.oi -lt $measO.Count) { $anchors[$sid] = $measO[$op.oi] }",
"            }",
"            'delete' {",
"                if ($op.oi -lt $measO.Count) {",
"                    # m: color the original measure red in-place (notes that shouldn't exist)",
"                    Color-Measure $ox $measO[$op.oi] 220 0 0",
"                    # m': rest placeholder colored red (what the copy has here - nothing)",
"                    $rp = Make-RestPlaceholder $ox $measO[$op.oi]",
"                    Color-Measure $ox $rp 220 0 0",
"                    Insert-After $stO $rp $measO[$op.oi]",
"                    $anchors[$sid] = $rp",
"                }",
"            }",
"            'insert' {",
"                if ($op.ci -lt $measC.Count) {",
"                    $imp = $ox.ImportNode($measC[$op.ci], $true)",
"                    Color-Measure $ox $imp 0 180 0",
"                    Insert-After $stO $imp $anchors[$sid]",
"                    $anchors[$sid] = $imp",
"                }",
"            }",
"            'replace' {",
"                if ($op.oi -lt $measO.Count -and $op.ci -lt $measC.Count) {",
"                    $mO  = $measO[$op.oi]",
"                    $imp = $ox.ImportNode($measC[$op.ci], $true)",
"                    Diff-Measure $ox $mO $imp",
"                    $stO.InsertAfter($imp, $mO) | Out-Null",
"                    $anchors[$sid] = $imp",
"                }",
"            }",
"        }",
"    }",
"}",
"",
"# Handle original-only staves (not present in copy).",
"# At replace positions: duplicate the original measure so the measure count matches.",
"# At delete positions: insert red clone as normal.",
"# At insert positions: nothing to show (no content from copy for this staff).",
"$origOnlyIds = @($idsO | Where-Object { $idsC -notcontains $_ })",
"foreach ($sid in $origOnlyIds) {",
"    $stO   = $staffsO | Where-Object { $_.id -eq $sid } | Select-Object -First 1",
"    if (-not $stO) { continue }",
"    $measO = @($stO.SelectNodes('Measure'))",
"    $anchor = $null",
"    foreach ($op in $ops) {",
"        switch ($op.op) {",
"            'equal'   { if ($op.oi -lt $measO.Count) { $anchor = $measO[$op.oi] } }",
"            'delete'  {",
"                if ($op.oi -lt $measO.Count) {",
"                    Color-Measure $ox $measO[$op.oi] 220 0 0",
"                    $rp = Make-RestPlaceholder $ox $measO[$op.oi]",
"                    Color-Measure $ox $rp 220 0 0",
"                    Insert-After $stO $rp $measO[$op.oi]",
"                    $anchor = $rp",
"                }",
"            }",
"            'insert'  {",
"                # No copy content for this staff - insert a silent rest measure to preserve alignment.",
"                # Use the nearest original measure as a template and clear its voice content.",
"                if ($anchor) {",
"                    $blank = $anchor.CloneNode($true)",
"                    foreach ($v in @($blank.ChildNodes | Where-Object { $_.Name -eq 'voice' })) {",
"                        $blank.RemoveChild($v) | Out-Null",
"                    }",
"                    Insert-After $stO $blank $anchor",
"                    $anchor = $blank",
"                }",
"            }",
"            'replace' {",
"                if ($op.oi -lt $measO.Count) {",
"                    # Duplicate the original measure to keep measure count in sync with other staves.",
"                    $dup = $measO[$op.oi].CloneNode($true)",
"                    $stO.InsertAfter($dup, $measO[$op.oi]) | Out-Null",
"                    $anchor = $dup",
"                }",
"            }",
"        }",
"    }",
"}",
"",
"Log 'saving'",
"$ox.Save($out)",
"Log 'done'",
"Start-Process $out",
"",
"} catch {",
"    Log ('ERROR: ' + $_.Exception.Message)",
"    Log $_.ScriptStackTrace",
"}"
        ];

        var ps1Content = ps1.join("\n");
        var ps1Path    = pluginDir + "/musescore-diff.ps1";
        var revPath    = pluginDir + "/musescore-diff-review.ps1";
        var batPath    = pluginDir + "/musescore-diff.bat";

        dbg(log, "writing diff ps1 to " + ps1Path);
        writeFile(ps1Path, ps1Content);

        // ---- review dialog PS1 (Windows Forms, runs after diff completes) --
        var rev = [
"param($orig, $out)",
"Add-Type -AssemblyName System.Windows.Forms",
"Add-Type -AssemblyName System.Drawing",
"[System.Windows.Forms.Application]::EnableVisualStyles()",
"",
"$form = New-Object System.Windows.Forms.Form",
"$form.Text = 'MuseScore Diff \u2014 Review & Save'",
"$form.Size = New-Object System.Drawing.Size(580, 460)",
"$form.StartPosition = 'CenterScreen'",
"$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog",
"$form.MaximizeBox = $false",
"$form.MinimizeBox = $false",
"$form.BackColor  = [System.Drawing.Color]::FromArgb(245, 245, 245)",
"",
"$nl = [char]13 + [char]10",
"",
"# ---- title ----",
"$title = New-Object System.Windows.Forms.Label",
"$title.Text     = 'MuseScore Diff - How to use' + $nl + 'IMPORTANT: Do not click Save Changes or close this window until you are done!'",
"$title.Font     = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)",
"$title.ForeColor = [System.Drawing.Color]::FromArgb(30, 30, 30)",
"$title.Location = New-Object System.Drawing.Point(20, 14)",
"$title.Size     = New-Object System.Drawing.Size(540, 76)",
"",
"# ---- separator under title ----",
"$sep1 = New-Object System.Windows.Forms.Panel",
"$sep1.BackColor = [System.Drawing.Color]::FromArgb(200, 200, 200)",
"$sep1.Location  = New-Object System.Drawing.Point(0, 98)",
"$sep1.Size      = New-Object System.Drawing.Size(580, 1)",
"",
"# ---- body ----",
"$body = New-Object System.Windows.Forms.Label",
"$body.Text = 'Measures with colored notes represent differences between the original and the copy.' + $nl + $nl + '     Green notes:   the notes match across both versions.' + $nl + '     Red notes:   the notes differ between versions.' + $nl + $nl + 'For each pair of altered measures, edit the version you want to keep,' + $nl + 'then delete the other measure. Repeat until all differences are resolved.' + $nl + $nl + 'When you are done editing, click Save Changes below. This will overwrite' + $nl + 'the original score with the edited diff file and remove the diff file.'",
"$body.Font     = New-Object System.Drawing.Font('Segoe UI', 10)",
"$body.ForeColor = [System.Drawing.Color]::FromArgb(50, 50, 50)",
"$body.Location = New-Object System.Drawing.Point(20, 112)",
"$body.Size     = New-Object System.Drawing.Size(540, 260)",
"",
"# ---- separator above buttons ----",
"$sep2 = New-Object System.Windows.Forms.Panel",
"$sep2.BackColor = [System.Drawing.Color]::FromArgb(200, 200, 200)",
"$sep2.Location  = New-Object System.Drawing.Point(0, 368)",
"$sep2.Size      = New-Object System.Drawing.Size(580, 1)",
"",
"",
"# ---- Save Changes button ----",
"$saveBtn = New-Object System.Windows.Forms.Button",
"$saveBtn.Text      = 'Save Changes'",
"$saveBtn.Font      = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)",
"$saveBtn.Location  = New-Object System.Drawing.Point(445, 382)",
"$saveBtn.Size      = New-Object System.Drawing.Size(110, 36)",
"$saveBtn.BackColor = [System.Drawing.Color]::FromArgb(30, 107, 46)",
"$saveBtn.ForeColor = [System.Drawing.Color]::White",
"$saveBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat",
"$saveBtn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(58, 170, 85)",
"$saveBtn.Add_Click({",
"    $answer = [System.Windows.Forms.MessageBox]::Show(",
"        'This will overwrite:' + [char]13 + [char]10 + [char]13 + [char]10 + '  ' + $orig + [char]13 + [char]10 + [char]13 + [char]10 + 'with the edited diff file, then delete the diff.' + [char]13 + [char]10 + 'This cannot be undone. Continue?',",
"        'Confirm Save',",
"        [System.Windows.Forms.MessageBoxButtons]::YesNo,",
"        [System.Windows.Forms.MessageBoxIcon]::Warning",
"    )",
"    if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {",
"        $xml = [xml](Get-Content -Path $out -Raw -Encoding UTF8)",
"        foreach ($cn in @($xml.SelectNodes('//color'))) { $cn.ParentNode.RemoveChild($cn) | Out-Null }",
"        $xml.Save($orig)",
"        Remove-Item -Path $out -Force",
"        $form.Close()",
"    }",
"})",
"",
"$form.Controls.AddRange(@($title, $sep1, $body, $sep2, $saveBtn))",
"$form.ShowDialog() | Out-Null"
        ];
        writeFile(revPath, rev.join("\n"));
        dbg(log, "wrote review ps1 to " + revPath);

        // ---- bat: run diff PS1 then review PS1 sequentially ----------------
        // -WindowStyle Hidden suppresses the console window for both scripts.
        // The two commands run in sequence: review only starts after diff finishes.
        var bat = "@echo off\r\n"
            + "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden"
            + " -File \"" + ps1Path.replace(/\//g, "\\") + "\""
            + " \"" + origPath.replace(/\//g, "\\") + "\""
            + " \"" + copyPath.replace(/\//g, "\\") + "\""
            + " \"" + outPath.replace(/\//g, "\\") + "\"\r\n"
            + "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden"
            + " -File \"" + revPath.replace(/\//g, "\\") + "\""
            + " \"" + origPath.replace(/\//g, "\\") + "\""
            + " \"" + outPath.replace(/\//g, "\\") + "\"\r\n";

        dbg(log, "writing bat to " + batPath);
        writeFile(batPath, bat);

        // Write debug log before launching.
        dbg(log, "launching bat");
        writeFile(debugPath, log.join("\n"));

        Qt.openUrlExternally("file:///" + batPath.replace(/\\/g, "/"));

        // Clean up temp script files after a short delay and quit.
        // The bat/ps1 files are already loaded by the shell at this point.
        var cleanup = Qt.createQmlObject(
            'import QtQuick 2.0; Timer { interval: 8000; repeat: false }',
            diffPlugin, "cleanupTimer");
        cleanup.triggered.connect(function() {
            fileIO.source = ps1Path; if (fileIO.exists()) fileIO.remove();
            fileIO.source = revPath; if (fileIO.exists()) fileIO.remove();
            fileIO.source = batPath; if (fileIO.exists()) fileIO.remove();
            quit();
        });
        cleanup.start();
    }
}
