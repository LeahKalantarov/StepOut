# StepOut

Handwritten math tutoring on iPad — write steps, get checked, talk back to the tutor.

## Run locally (not iCloud)

**Do not keep this project in iCloud Drive.** Xcode and iCloud sync fight each other; you end up building old or half-synced files.

### One-time setup on your Mac

```bash
mkdir -p ~/Developer
cd ~/Developer

# If you already cloned here, just pull:
git clone https://github.com/LeahKalantarov/StepOut.git
cd StepOut
git pull origin main
```

Open in Xcode:

```
~/Developer/StepOut/StepOut/StepOut.xcodeproj
```

After a pull: **Product → Clean Build Folder** (Shift+Cmd+K), then run on your iPad.

You should see a **pink pill** under the title: **`NEW BUILD · 0a6323e`**

### Backend

```bash
cd backend
cp .env.example .env   # add MyScript keys; OPENAI_API_KEY optional
pip install -r requirements.txt
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

On a real iPad, set the server IP in `StepOut/StepOut/CheckService.swift` (simulator uses `localhost`).

### Moving off iCloud Desktop

If your old copy lives at **Desktop → StepOut** (iCloud):

1. Quit Xcode.
2. Use the fresh clone at `~/Developer/StepOut` (above) — don't rely on the iCloud folder.
3. Optional: delete or archive the old `~/Desktop/StepOut` after confirming the new copy works.
4. In **System Settings → Apple ID → iCloud → iCloud Drive → Options**, you can turn off **Desktop & Documents** if you don't want projects there at all.
