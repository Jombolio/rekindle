# Native CBR/RAR decoder

`librekindle_rar.so` extracts image pages from CBR/RAR archives on-device so
downloaded comics/manga in RAR format are readable **offline** (no server).

- **Engine:** [libarchive](https://www.libarchive.org/) — decodes both RAR4 and
  RAR5. Its RAR5 reader is a clean-room **BSD-2** implementation (it does *not*
  use the license-encumbered unRAR source), so it is safe for F-Droid.
- **Entry point:** `rar_extract.c` → JNI `RarExtractor.nativeExtract`. It writes
  each image entry to the target dir as `rNNNNN.<ext>` and returns an interleaved
  `[entryPath, fileName, …]` array; the Kotlin side orders pages by entry path.
- **Kotlin bridge:** `com.rekindle.app.core.download.RarExtractor`.
- **Consumer:** `DownloadManager.extractRarPages()` (falls back to a ZIP attempt,
  then to server streaming, if the native lib is unavailable or the open fails).

## Build prerequisites

The main app build now includes this CMake project, so you need:

- **NDK** and **CMake** SDK components (Android Studio → SDK Manager, or
  `sdkmanager "ndk;<version>" "cmake;3.22.1"`).
- **Network access on the first native build** — libarchive is fetched via
  CMake `FetchContent`. Pin `URL_HASH` in `CMakeLists.txt` for reproducible /
  offline-safe builds (see the TODO there), or vendor the source and switch to
  `add_subdirectory`.

Built ABIs are limited in `app/build.gradle.kts` (`abiFilters`) to
`arm64-v8a`, `armeabi-v7a`, `x86_64`.

## Verify

```bash
cd android
./gradlew :app:assembleDebug         # compiles native + Kotlin
```

Then download a **CBR** (both RAR4 and RAR5) on-device, go offline, and confirm
it opens and pages render from local files.

## Licensing note

libarchive is BSD-2-Clause. Add its license to the app's third-party licenses /
About screen when shipping.
