#!/bin/bash
# Run while git merge is in progress (after: git pull origin main --no-rebase)
set -e
cd "$(git rev-parse --show-toplevel)"

if ! git diff --name-only --diff-filter=U | grep -q .; then
  echo "No merge conflicts right now. Status:"
  git status -sb
  exit 0
fi

echo "Resolving conflicts: keeping YOUR iPad app, adding GitHub backend extras..."

# YOUR real app (floating nav, handwritten tutor, full notebook)
git checkout --ours StepOut/StepOut/ContentView.swift
git checkout --ours StepOut/StepOut/CheckResult.swift
git checkout --ours StepOut/StepOut/CheckService.swift
git checkout --ours StepOut/StepOut/Info.plist
git checkout --ours backend/main.py
git checkout --ours backend/checker/step_checker.py
git checkout --ours backend/test_checker.py
git checkout --ours backend/.env.example

# MVP-only file — your app uses NotebookPage instead
git rm -f StepOut/StepOut/NotebookRow.swift 2>/dev/null || rm -f StepOut/StepOut/NotebookRow.swift

# Drop GitHub MVP-only UI files if they appeared
git rm -f StepOut/StepOut/TutorNote.swift StepOut/StepOut/TutorNoteCard.swift StepOut/StepOut/AppBuild.swift 2>/dev/null || true

# NEW backend modules from GitHub (diagnosis + tutor prompts)
git checkout origin/main -- backend/checker/diagnosis.py 2>/dev/null || true
git checkout origin/main -- backend/tutor 2>/dev/null || true
git checkout origin/main -- backend/test_tutor.py 2>/dev/null || true
git checkout origin/main -- SYNC.md MERGE.md README.md 2>/dev/null || true
git checkout origin/main -- scripts/which-stepout.sh 2>/dev/null || true

# Photo library permission (from GitHub) if missing from your Info.plist
if ! grep -q NSPhotoLibraryUsageDescription StepOut/StepOut/Info.plist 2>/dev/null; then
  /usr/bin/python3 - <<'PY'
from pathlib import Path
p = Path("StepOut/StepOut/Info.plist")
text = p.read_text()
needle = "\t<key>NSAppTransportSecurity</key>"
insert = '\t<key>NSPhotoLibraryUsageDescription</key>\n\t<string>Attach photos of your work or notes so the tutor has more context.</string>\n'
if needle in text and "NSPhotoLibraryUsageDescription" not in text:
    text = text.replace(needle, insert + needle)
    p.write_text(text)
    print("Added NSPhotoLibraryUsageDescription to Info.plist")
PY
fi

git add -A

if git diff --name-only --diff-filter=U | grep -q .; then
  echo ""
  echo "Still conflicted — fix these manually:"
  git diff --name-only --diff-filter=U
  exit 1
fi

git commit -m "Merge GitHub cloud changes; keep local StepOut UI"

echo ""
echo "Done. Now run:  git push origin main"
echo "Then open:      ~/Developer/StepOut/StepOut/StepOut.xcodeproj"
