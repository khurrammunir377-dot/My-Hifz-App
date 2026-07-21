# Hifz Companion — Phase 1 + Phase 2

A free Quran memorization app. **Phase 1** (reading, navigation, audio
recording) plus **Phase 2** (live recitation checking: continuous
listening, word-level mistake detection, real-time interruption cue) are
both included in this build.

**If you're setting up recitation checking for the first time, see
[PHASE2_SETUP.md](PHASE2_SETUP.md) first** — it needs a small backend
piece (Supabase + Groq) before the mic button on the Recitation Screen
will do anything beyond recording.

## What's included

- Full, authentic Quran text (6,236 verses, 114 Surahs, all 30 Juz), sourced
  from an established open Quran text dataset (Uthmani script) — bundled as
  a local asset so the app works fully offline.
- Home screen (30 Juz list + Continue Last Session)
- Surah list per Juz
- Recitation screen: Arabic text display, verse navigation, audio recording,
  playback, re-record
- Settings screen: font size, dark mode, reference-audio toggle placeholder,
  Support This App placeholder
- Local SQLite storage for recordings (offline, on-device only)

## How the build works (same pattern as your UUDS app)

This repo does **not** commit the `android/` platform folder. Instead, the
GitHub Actions workflow (`.github/workflows/build.yml`) generates it fresh
on every build using `flutter create`, matched exactly to the Flutter
version running in CI — then copies in the custom app icon and Android
manifest (microphone permission, app name) from `android_overlay/`. This
avoids the SDK-version-mismatch and stale-Gradle-file issues you hit on the
last project, since the Android scaffold is never out of date with the
Flutter version.

## Steps to build your APK

1. **Create a new GitHub repository** (e.g. `hifz-companion`)
2. **Upload all these files**, keeping the folder structure exactly as-is
   (unzip and push, or upload via GitHub's web uploader — just make sure
   `.github/workflows/build.yml` ends up at that exact path)
3. Go to the **Actions** tab in your repo — the workflow will run
   automatically on push to `main` (or trigger it manually via
   "Run workflow" if it doesn't auto-start)
4. Wait for the build to finish (~5-8 minutes for the first run)
5. Click the completed run → under **Artifacts**, download
   `hifz-companion-apk`
6. Unzip that download to get `app-release.apk`
7. Transfer it to your phone (WhatsApp/email/USB) and install
   (you may need to allow "install from unknown sources" once)

## Testing checklist once installed

- [ ] App opens and shows the 30 Juz list
- [ ] Tapping a Juz shows the correct Surahs
- [ ] Tapping a Surah opens the Recitation screen at Ayah 1
- [ ] Arabic text displays correctly, right-to-left
- [ ] Mic permission prompt appears on first recording attempt
- [ ] Recording button works: starts, shows timer, stops
- [ ] Playback plays back exactly what was recorded
- [ ] Re-record and Next Verse buttons work
- [ ] Settings: font size and dark mode changes apply
- [ ] Closing and reopening the app keeps your last session (Continue card)
- [ ] App works with phone in airplane mode (fully offline)

## If the build fails

Open the failed Actions run and check which step failed — paste me the
error output and I'll fix it. Common first-run issues are usually version
mismatches between the pinned package versions in `pubspec.yaml` and what's
currently on pub.dev; those are quick fixes.

## Next step

Once you've checked everything above on your real phone, come back and I'll
give you the Phase 2 prompt/code (word-level mistake detection).
