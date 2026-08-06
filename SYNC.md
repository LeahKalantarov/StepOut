# Why rebuilds show the old app

There are **two different StepOut projects**. Only one of them was getting our changes.

| | What you've been building (iPad) | What the cloud agent edits |
|---|---|---|
| **Location** | iCloud → Desktop → StepOut | github.com/LeahKalantarov/StepOut |
| **UI** | Full app (handwritten tutor, fold buttons, floating nav) | Simple MVP (3 rows, tutor cards) |
| **In git?** | Probably not, or never pushed | Yes — all our commits are here |

**Pulling from GitHub cannot update your iPad app** until the project Xcode opens **is** that git repo — or until your real Mac code is pushed to GitHub.

The cloud agent **cannot see** your iCloud Desktop folder. It only sees the GitHub clone.

---

# Fix (do this once, in order)

## 1. Quit Xcode

## 2. Copy your real project off iCloud to a local folder

In Terminal **on your Mac**:

```bash
mkdir -p ~/Developer
rsync -a "$HOME/Library/Mobile Documents/com~apple~CloudDocs/Desktop/StepOut/" ~/Developer/StepOut/
cd ~/Developer/StepOut
```

(If Desktop isn’t under iCloud, use the path from Finder when you **Show in Finder** on the Xcode project.)

## 3. Check what you actually have

```bash
cd ~/Developer/StepOut
find . -name "ContentView.swift"
find . -name "FloatingNavRail.swift"   # your real app has this; GitHub does not
git status 2>&1
```

- If you see **FloatingNavRail.swift** → this is your real app. Good.
- If `git status` says **not a git repository** → this folder was never connected to GitHub.

## 4. Connect your real app to GitHub

**Option A — your Mac code is the source of truth** (recommended):

```bash
cd ~/Developer/StepOut
git init
git add -A
git commit -m "My actual StepOut app from Mac"
git branch -M main
git remote add origin https://github.com/LeahKalantarov/StepOut.git
git pull origin main --allow-unrelated-histories
# resolve any conflicts, keeping YOUR UI files
git push origin main
```

**Option B — start fresh from GitHub** (you lose the redesigned UI):

```bash
cd ~/Developer
rm -rf StepOut
git clone https://github.com/LeahKalantarov/StepOut.git
```

## 5. Open the correct project in Xcode

```bash
open ~/Developer/StepOut/StepOut/StepOut.xcodeproj
```

Product → Clean Build Folder → Run on iPad.

---

# Cursor: local vs cloud

- **Cloud agent** (this chat) → edits GitHub only.
- **Local agent** → edits the folder open on your Mac.

Until step 4 is done, cloud agent changes **will not** appear on your iPad.

After your Mac code is on GitHub:

1. Open **~/Developer/StepOut** in Cursor on your Mac.
2. Use **local** agent for UI work, **or** cloud agent after push (same repo).

---

# iCloud

Yes — **stop keeping the project in iCloud Desktop.**

- iCloud sync was failing in Finder (“Unable to complete iCloud Drive sync”).
- Even when it works, it’s a third copy that drifts out of date.

Work only in **~/Developer/StepOut** after the copy above.

---

# After sync

Tell the agent: “Work on the Mac UI in ContentView — apply tutor gesture changes to the handwritten tutor batches, not the MVP cards.”

Then changes will land in the app you actually run.
