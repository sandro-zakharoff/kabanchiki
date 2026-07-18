# Release artifacts

Local production artifacts belong in `releases/windows`, `releases/android`, and
`releases/miniapp`. The directories are ignored by Git so installers, APKs and
static bundles do not enter source history. CI uploads distributable artifacts
to workflow runs or GitHub Releases.

## Layout

| Path | Artifact | How it is distributed |
|---|---|---|
| `releases/windows/Kabanchiki-<ver>-portable.zip` | Windows portable build (unzip and run `Kabanchiki.exe`) | GitHub Release asset |
| `releases/android/Kabanchiki-<ver>.apk` | Signed release APK | GitHub Release asset and/or the in-app updater (`app-releases` bucket) |
| `releases/miniapp/` | Static Telegram Mini App bundle | GitHub Pages (`.github/workflows/miniapp-pages.yml`) |

## Building

- **Windows:** `cd desktop && python -m PyInstaller Kabanchiki.spec --noconfirm --clean`,
  then zip `desktop/dist/Kabanchiki`.
- **Android:** `cd android && ./gradlew :app:assembleRelease` (needs
  `signing/keystore.properties`; the keystore is never committed).
- **Mini App:** the static files in `telegram/` are the build; the Pages workflow
  injects the public config and publishes them.
