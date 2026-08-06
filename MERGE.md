# Finish the merge (you are here)

Your Mac already has the **real app** (`FloatingNavRail.swift`, full `ContentView`, etc.) and it's committed locally as `5135fdc`.

GitHub has **different commits** (checker diagnosis, tutor prompts, MVP cards). Git stopped because those histories diverged — that's normal.

Run these **on your Mac** in order:

```bash
cd ~/Developer/StepOut

# Merge GitHub into your local main (your UI wins on conflicts)
git pull origin main --no-rebase
```

Git will either merge cleanly or list **conflict** files.

## If there are conflicts

Keep **your** iPad UI, add **GitHub's** new backend files:

```bash
cd ~/Developer/StepOut

# YOUR app UI — always keep local version
git checkout --ours StepOut/StepOut/ContentView.swift
git checkout --ours StepOut/StepOut/NotebookPage.swift
git checkout --ours StepOut/StepOut/PenPalette.swift
git checkout --ours StepOut/StepOut/FloatingNavRail.swift
git checkout --ours StepOut/StepOut/Theme.swift
git checkout --ours StepOut/StepOut/HandwrittenLine.swift
git checkout --ours StepOut/StepOut/TutorLine.swift

# NEW files from GitHub — take theirs if conflict
git checkout --theirs backend/checker/diagnosis.py 2>/dev/null || true
git checkout --theirs backend/tutor/ 2>/dev/null || true
git checkout --theirs SYNC.md README.md 2>/dev/null || true

# Backend: if these conflict, prefer YOUR local copy (you already have lesson/tutor)
git checkout --ours backend/main.py
git checkout --ours backend/checker/step_checker.py

git add -A
git commit -m "Merge GitHub cloud changes into local StepOut app"
git push origin main
```

## If pull merges with no conflicts

```bash
git push origin main
```

## Then in Xcode

1. **Quit Xcode**
2. Open **`~/Developer/StepOut/StepOut/StepOut.xcodeproj`** (not iCloud Desktop)
3. **Product → Clean Build Folder**
4. Run on iPad

## Confirm

Your app should still look like **your** redesigned UI (floating nav, handwritten tutor).

After merge + push, tell the cloud agent: *"The real app is now on GitHub main — apply tutor gesture changes to TutorLine batches in ContentView."*

## Do not

- Do **not** `git push --force` unless you mean to wipe GitHub history
- Do **not** open the iCloud Desktop copy anymore
