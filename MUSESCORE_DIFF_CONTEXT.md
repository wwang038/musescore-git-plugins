# MuseScore Diff Plugin — Full Context

## Overview

A MuseScore 4 plugin (`musescore diff.qml`) that performs a musical score diff between a score and its copy, displays the differences with colored notes inside MuseScore, and provides a review dialog for the user to resolve differences and save back to the original.

**File locations:**
- Plugin: `C:\Users\winso\Documents\MuseScore4\Plugins\musescore diff.qml`
- Backup (do not edit): `C:\Users\winso\Documents\MuseScore4\Plugins\musescore git.qml`

---

## How It Works — End-to-End Flow

### 1. Plugin trigger (`onRun`)
The user opens the original score in MuseScore and runs the plugin via `Plugins > Composing/arranging tools > MuseScore Diff`.

**Before anything else**, the plugin force-saves the current score to disk:
```javascript
writeScore(curScore, curScore.path, "mscx");
```
This ensures the `.mscx` file reflects the latest in-memory edits before the diff reads it.

### 2. Path resolution
The plugin expects this directory structure:
```
Documents/MuseScore4/Scores/
  SongName/
    SongName.mscx          ← original (the open score)
    SongName_diff.mscx     ← output diff (created by plugin)
  SongName - Copy/
    SongName - Copy.mscx   ← the copy to diff against
```

### 3. Script generation and execution
The plugin writes two PowerShell scripts and a `.bat` file to the Plugins folder at runtime, then launches the `.bat`. The `.bat` runs the two scripts sequentially:
1. **`musescore-diff.ps1`** — does the XML diff, writes `SongName_diff.mscx`, opens it in MuseScore
2. **`musescore-diff-review.ps1`** — shows a Windows Forms review dialog

After 8 seconds, the plugin deletes the generated `.ps1`/`.bat` files (they are already loaded by the shell by then).

---

## Diff Algorithm (`musescore-diff.ps1`)

### Tokenization
Each musical element in a measure voice is converted to a canonical string token:

| Element | Token format | Example |
|---|---|---|
| Chord | `C:pitches:duration[:tie]` | `C:E4,G4:quarter` |
| Rest | `R:duration` | `R:half` |
| Dynamic | `D:subtype` | `D:mf` |
| Harmony | `H:name` | `H:Am` |
| Lyrics | `L:text` | `L:hel-` |
| KeySig | `K:concertKey` | `K:2` |
| TimeSig | `T:N/D` | `T:4/4` |
| Tempo | `Tm:value` | `Tm:2.5` |

A measure's **signature** (`Get-Sig`) concatenates all token strings across all voices: `v1:[tok1][tok2]|v2:[tok3]`.

### Cross-staff alignment
Rather than diffing each staff independently, a **single combined signature** is built per measure position across all staves (joined with `||`). This ensures the LCS alignment is globally consistent — when any staff changes at position *i*, ALL staves show the corresponding insertion/change.

### LCS core
`Get-LCS` runs a standard bottom-up Longest Common Subsequence over the combined signatures, using a flattened 1D int array to avoid PowerShell's 2D array parsing issues. Produces `equal / delete / insert` ops.

### Merge-Ops (bug fixed)
`Merge-Ops` converts adjacent `delete + insert` pairs into `replace` ops.

**The bug that was fixed:** The original implementation only looked one step ahead (`if ops[k]=delete and ops[k+1]=insert`). This failed for the case where the LCS produces `[delete, delete, insert, insert]` (when no measures match at all), producing `[delete, replace, insert]` instead of `[replace, replace]`, yielding 5 output measures from 2+2 inputs.

**The fix:** Collect the full contiguous run of deletes, then the full run of inserts, and pair them N-to-N:
```powershell
function Merge-Ops($ops) {
    while ($k -lt $ops.Count) {
        if ($ops[$k].op -eq 'delete') {
            # collect all consecutive deletes
            # collect all consecutive inserts that follow
            # pair them as replaces, emit any leftovers
        }
    }
}
```

---

## Output Layout — Musical Chaining

### Old layout (interleaved, discarded)
```
... equal | orig₁ | copy₁ | orig₂ | copy₂ | equal ...
```
This was unmusical — you couldn't hear either version as a coherent passage.

### New layout (grouped blocks)
```
... equal | orig₁ | orig₂ | ... | origₙ | copy₁ | copy₂ | ... | copyₙ | equal ...
```
For each contiguous block of differing measures, ALL original measures appear first (in-place, colored), then ALL copy measures are chained immediately after.

### Two-phase rendering per diff block
**Phase 1** — iterate ops, color orig measures in place, collect copy nodes in a list (do NOT insert yet):
- `replace`: run `Diff-Measure` on orig+copy (event-level coloring), track as first orig if applicable
- `delete`: color orig red, create rest placeholder (red), add placeholder to copy list
- `insert`: import copy measure (green), add to copy list

**Phase 2** — insert all copy nodes in order after the last orig measure:
```powershell
$copyAnchor = $lastOrigAnchor
foreach ($cn in $copyNodes) {
    if ($cn -ne $null) { Insert-After $stO $cn $copyAnchor; $copyAnchor = $cn }
}
```

---

## Coloring Scheme

| Color | RGB | Meaning |
|---|---|---|
| Green | `0, 200, 0` | Notes that match in both versions (event-level equal) |
| Red | `220, 0, 0` | Notes that differ / were deleted / were inserted |
| Green (insert) | `0, 180, 0` | Whole measures inserted from copy |
| Blue | `30, 100, 200` | Diff boundary markers (StaffText) |

Colors are written as `<color r="..." g="..." b="..." a="255"/>` child elements on each XML node.

**On "Save to Main"**, ALL `<color>` elements are stripped from the XML before writing back to the original score.

---

## Diff Boundary Markers

Three colored `<StaffText>` markers are inserted on the **first staff only** (top staff) at each diff block:

| Char | Code | Placement | Meaning |
|---|---|---|---|
| `▶` | `[char]9654` | Before first note of first orig measure | Start of diff block |
| `‖` | `[char]8214` | Before first note of first copy measure | Transition: orig → copy |
| `◀` | `[char]9664` | After last note of last copy measure (`AppendChild`) | End of diff block |

Characters are generated via PowerShell `[char]` at runtime to avoid UTF-8 encoding issues when writing the PS1 file from QML's `FileIO`.

**On "Save to Main"**, these markers are also stripped:
```powershell
$diffMarkChars = @([string][char]9654, [string][char]8214, [string][char]9664)
foreach ($st in @($xml.SelectNodes('//StaffText'))) {
    $t = $st.SelectSingleNode('text')
    if ($t -and $diffMarkChars -contains $t.InnerText.Trim()) {
        $st.ParentNode.RemoveChild($st) | Out-Null
    }
}
```

---

## Review Dialog (`musescore-diff-review.ps1`)

A Windows Forms dialog that appears after the diff opens in MuseScore.

### Layout (580×490 px)
- **Title label** (y=14, h=106): Instructions + important warning
- **Separator** (y=128)
- **Body label** (y=142, h=250): Color legend and workflow instructions
- **Separator** (y=398)
- **Auto Save button** (x=20, y=412, blue): Sends Ctrl+S to MuseScore via `WScript.Shell.AppActivate + SendKeys`
- **Save to Main button** (x=445, y=412, green): Finalizes and saves

### "Save to Main" flow
1. Confirm dialog (irreversible warning)
2. Load diff `.mscx` as XML
3. Strip all `<color>` child elements (`//color`)
4. Strip all diff marker `<StaffText>` elements
5. `$xml.Save($orig)` — overwrites original score
6. `Remove-Item $out` — deletes diff file
7. Close form

### "Auto Save" flow
Uses `WScript.Shell` to find the MuseScore window by title and send Ctrl+S:
```powershell
$wsh = New-Object -ComObject WScript.Shell
if ($wsh.AppActivate('MuseScore')) {
    Start-Sleep -Milliseconds 200
    $wsh.SendKeys('^s')
    Start-Sleep -Milliseconds 500
}
$form.Activate()
```
Intended to be clicked between reviewing each pair of altered measures.

---

## Original-Only Staves

Staves present in the original but not in the copy use the same two-phase grouping, but since there is no copy content, the "copy row" for these staves consists of:
- `delete` → rest placeholder (red)
- `insert` → blank measure (voice content cleared, for alignment)
- `replace` → duplicate of orig measure (to keep measure count in sync with other staves)

---

## Known Limitations / Research Notes

- **Measure background coloring** is not supported in MSCX format. Colors can only be applied to individual elements (notes, rests, etc.), not to measure backgrounds.
- **MuseScore 4 plugin submenus** are not natively supported. A single `.qml` file cannot produce multiple menu items. The workaround is multiple `.qml` files sharing the same `categoryCode`, which groups them under the same submenu.
- `menuPath` is deprecated in MuseScore 4 — `categoryCode` + `title` is the correct approach.

---

## File Structure Reference

```
musescore diff.qml
├── onRun (QML/JS)
│   ├── Force-saves current score via writeScore()
│   ├── Resolves orig/copy/out paths
│   ├── Builds ps1[] string array  ← the PowerShell diff script
│   ├── Builds rev[] string array  ← the Windows Forms review dialog script
│   ├── Writes .ps1, review .ps1, .bat to Plugins folder
│   ├── Launches .bat via Qt.openUrlExternally
│   └── Cleans up temp files after 8s timer
│
├── musescore-diff.ps1 (generated at runtime)
│   ├── Loads orig.mscx and copy.mscx as XML
│   ├── Token helpers: Get-Duration, Get-PitchName, Get-Token, Get-Sig
│   ├── LCS: Get-LCS, Merge-Ops
│   ├── Coloring: Add-DiffMark, Set-Color, Color-Measure, Diff-Measure
│   ├── Helpers: Make-RestPlaceholder, Insert-After
│   ├── Cross-staff alignment: builds $sigO/$sigC, runs LCS
│   ├── Segment grouping: groups ops into equal/diff blocks
│   ├── Main rendering loop (common staves, two-phase)
│   ├── Orig-only staves loop (two-phase)
│   └── Saves diff to _diff.mscx, opens in MuseScore
│
└── musescore-diff-review.ps1 (generated at runtime)
    ├── Windows Forms dialog
    ├── Auto Save button (WScript.Shell Ctrl+S)
    └── Save to Main button (strip colors+markers, save XML, delete diff)
```

---

## What "Save to Main" Strips

Everything added by the diff script is removed before saving back:

| What | How identified | Removal method |
|---|---|---|
| Note/rest colors | `//color` XPath | Remove from parent |
| Diff markers (▶ ‖ ◀) | `//StaffText` with matching InnerText | Remove from parent |

The saved original score has zero diff artifacts — clean, default-color notes.
