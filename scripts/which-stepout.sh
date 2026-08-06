#!/bin/bash
# Run this on your Mac in Terminal to see which StepOut project Xcode should open.

echo "=== Looking for StepOut projects ==="
for dir in "$HOME/Developer/StepOut" "$HOME/Desktop/StepOut" "$HOME/Library/Mobile Documents/com~apple~CloudDocs/Desktop/StepOut"; do
  if [ -d "$dir" ]; then
    echo ""
    echo "Found: $dir"
    if [ -d "$dir/.git" ]; then
      echo "  git: yes"
      (cd "$dir" && git log --oneline -1 && git remote get-url origin 2>/dev/null)
    else
      echo "  git: NO — this folder is not from GitHub"
    fi
    if [ -f "$dir/StepOut/StepOut/AppBuild.swift" ]; then
      echo "  AppBuild.swift:"
      grep marker "$dir/StepOut/StepOut/AppBuild.swift" || echo "    (no marker — old code)"
    elif [ -f "$dir/StepOut/AppBuild.swift" ]; then
      echo "  AppBuild.swift:"
      grep marker "$dir/StepOut/AppBuild.swift" || echo "    (no marker — old code)"
    else
      echo "  AppBuild.swift: NOT FOUND — wrong or very old project"
    fi
  fi
done

echo ""
echo "=== GitHub latest (should match after pull) ==="
curl -sL "https://raw.githubusercontent.com/LeahKalantarov/StepOut/main/StepOut/StepOut/AppBuild.swift" | grep marker

echo ""
echo "Open the project that shows: NEW BUILD · 0a6323e"
echo "Recommended path: ~/Developer/StepOut/StepOut/StepOut.xcodeproj"
