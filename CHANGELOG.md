# MuseScore Plugin Changelog — 2026-03-16

## Files Modified
- `commitToGithub_44.qml`
- `musescore diff.qml`

---

## `commitToGithub_44.qml`

### 1. Remote-change detection before committing
**Problem:** The plugin previously committed the current score to GitHub immediately, with no check for whether the remote had newer changes.

**Fix:** Introduced a `musescore-git-check.ps1` + `musescore-git-check.bat` step that runs silently before committing:
1. `git fetch origin`
2. Resolves `@{upstream}` — if none is set, falls through to commit directly
3. Runs `git log HEAD..@{upstream} -- ScoreName.mscz` to check for unpulled commits
4. If **no remote changes** → launches `commitBat` as before
5. If **remote has changes** → uses `git worktree add --detach` to check out the remote tree, unzips the remote `.mscz` to extract its `.mscx`, saves it to `Scores/ScoreName - Copy/ScoreName - Copy.mscx` (matching `musescore diff.qml`'s expected copy path), shows a Windows Forms warning dialog telling the user to run MuseScore Diff before committing

### 2. `git add` behaviour
The commit bat only ever stages the **currently open score** (`ScoreName.mscz` / `ScoreName.mscx`) — all other unrelated changes/deletions in the repo are intentionally ignored.

### 3. Residual `_diff.log.txt` detection (force-push path)
**Problem:** After resolving a diff and saving back to main, a `ScoreName_diff.log.txt` file is left in the Scores folder. On the next commit run, the remote-change check would wrongly block again.

**Fix:** Before any other logic, the plugin checks for `Scores/ScoreName_diff.log.txt`:
- If **found** → writes a commit bat with `git push --force-with-lease` (to override the remote changes the user already reviewed) and a `del ScoreName_diff.log.txt` line, then launches it immediately, skipping all setup/check steps entirely
- If **not found** → proceeds with the normal remote-check flow

### 4. `nameNoExt` / `scoreFile` moved earlier
`nameNoExt` and `scoreFile` are now computed before the commit bat is written, so they are available for the diff-log check.

### 5. Cleanup timer — `commitBat` no longer deleted
**Problem:** The 1500ms cleanup timer deleted `commitBat` while the check PS1 was still running `git fetch` (which can take 3–5+ seconds). When the PS1 finished and called `Start-Process $commitBat`, the file was already gone — silently preventing any commit.

**Fix:** `commitBat` is no longer deleted by the main cleanup timer. It is overwritten fresh on every plugin run, so leaving it on disk is safe.

---

## `musescore diff.qml`

### 1. Flat file format detection for `origPath`
**Problem:** The plugin hardcoded `origPath = Scores/ScoreName/ScoreName.mscx` (subdirectory structure), which didn't match scores stored flat in the Scores folder.

**Fix:** `origPath` is now resolved with priority order:
1. `Scores/ScoreName.mscx` — flat uncompressed (checked first)
2. `Scores/ScoreName.mscz` — flat compressed (sets `origMsczPath`; PS1 will handle)
3. `Scores/ScoreName/ScoreName.mscx` — subdirectory fallback (original behaviour)

`outPath` is also placed flat (`Scores/ScoreName_diff.mscx`) when the score is flat, rather than in a nonexistent subdirectory.

### 2. `writeScore` writes to a temp file instead of `curScore.path`
**Problem:** `writeScore(curScore, curScore.path, "mscx")` caused MuseScore to create `ScoreName.mscx` and orphan `ScoreName.mscz` on disk, corrupting the git-tracked file and scattering zip contents (`META-INF/`, `Thumbnails/`, etc.) into the Scores folder.

**Fix:** `writeScore` now writes to `Scores/ScoreName_temp.mscx`. The real score file is never touched. The diff PS1 reads from this temp file and deletes it immediately after loading into memory. The cleanup timer also deletes it as a safety net.

### 3. Diff PS1 — `$tempMscx` parameter
The diff PS1 now accepts a 5th optional parameter `$tempMscx`. Reading priority:
- If `$tempMscx` is provided and exists → read XML from it (then delete it)
- Else if `$origMscz` is provided → extract `.mscx` from the `.mscz` zip, read from that
- Else → read directly from `$orig`

### 4. "Save to Main" saves in the original repository format
**Problem:** "Save to Main" always saved as `.mscx`, even when the repository originally stored the score as `.mscz`.

**Fix:** The review PS1 now accepts a 3rd optional parameter `$origMscz`. After stripping diff colours and markers:
1. Always saves cleaned XML to `$orig` (the `.mscx` path)
2. If `$origMscz` is set → repacks the `.mscx` into a fresh `.mscz` zip at the original path
3. `$savedPath` = the `.mscz` if repacked, else the `.mscx`

### 5. Automatic file management after "Save to Main"
After saving:
1. Deletes `$out` (the diff output file)
2. Deletes the `ScoreName - Copy/` directory (the remote copy fetched during the commit check)
3. Activates MuseScore and sends `Ctrl+W` + `{TAB}{ENTER}` to close the diff tab (and dismiss any "save changes?" prompt)
4. Opens the saved file (`Start-Process $savedPath`) so MuseScore loads the resolved result

### 6. Bat passes `origMsczPath` and `tempMscxPath` to scripts
- Diff PS1 receives: `$orig`, `$copy`, `$out`, `$origMscz` (empty string if not mscz), `$tempMscx`
- Review PS1 receives: `$orig`, `$out`, `$origMscz`
