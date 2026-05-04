# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository layout

```
android/    Native Android client (Kotlin / Jetpack Compose)
desktop/    Desktop client — Linux & Windows (Flutter / Dart)
server/     Backend server (C# / .NET 10 / ASP.NET Core)
wiki/       GitHub Wiki source (Markdown)
fastlane/   F-Droid store metadata and build recipe
```

---

## Commands

### Server

```bash
cd server
dotnet run --project Rekindle.Server          # dev run
dotnet build                                   # build only
dotnet test                                    # all tests
dotnet test --filter "FullyQualifiedName~Unit" # unit tests only
dotnet test --filter "FullyQualifiedName~Integration" # integration only
dotnet publish Rekindle.Server /p:PublishProfile=linux-x64   # release Linux
dotnet publish Rekindle.Server /p:PublishProfile=win-x64     # release Windows
```

### Desktop client

```bash
cd desktop
flutter run -d linux      # run on Linux
flutter run -d windows    # run on Windows
flutter analyze           # lint
flutter test              # widget tests
flutter build linux  --release --obfuscate --split-debug-info=symbols/
flutter build windows --release --obfuscate --split-debug-info=symbols/
```

### Android client

```bash
cd android
./gradlew assembleDebug          # debug APK
./gradlew assembleRelease        # release APK (requires keystore)
./gradlew :app:compileDebugKotlin  # type-check only, fast
```

---

## Server architecture

**Two projects inside `server/`:**

- `Rekindle.Core` — domain logic: models, repositories, services, DB migrations. No ASP.NET dependency.
- `Rekindle.Server` — ASP.NET host: controllers, DI wiring (`Program.cs`), authorization policies, publish profiles.

**Database:** SQLite via Dapper (no ORM). `DbInitializer` runs numbered migrations sequentially on startup (`Migration_001` … `Migration_N`). To add a schema change, add a new `Migration_00N` method and register it in `ApplyMigrationsAsync`. Never modify existing migrations.

**Authorization** is claim-based, not role-based. The JWT contains a `permission_level` integer claim. `PermissionPolicies` maps named policies to minimum levels (1 = read, 2 = download, 3 = manage media, 4 = admin). Apply policies with `[Authorize(Policy = PermissionPolicies.IsAdmin)]` etc.

**Cover generation** is a background `Channel<CoverJob>` pipeline. The scanner enqueues jobs; `CoverGenerationService` dequeues and writes JPEG thumbnails. Custom covers take priority: `rekindle-cover.*` > `cover.*` > first archive image (checked per directory and inside archives).

**Page cache** lives under `CachePath/pages/{mediaId}/` with a `manifest.json` tracking page filenames and spread flags. `ArchiveService` extracts on first access and evicts LRU entries when the cache exceeds `CacheMaxSizeBytes`.

**Metadata scraping** routes strictly by library type: comics → ComicVine only; manga → MAL then AniList. `MetadataScraperService.ScrapeAsync` returns a `ScrapeResult` with status `Created | NoChange | Conflict` — conflicts are never written automatically; the client must call `/commit`.

---

## Desktop client architecture (Flutter)

State management is **Riverpod** throughout. Providers live in `desktop/lib/providers/`; screens consume them via `ref.watch` / `ref.read`.

Navigation is **GoRouter** (`desktop/lib/app.dart`). The router refreshes on `sourcesProvider` and `authProvider` changes so auth state drives redirects automatically. A 401 interceptor in `ApiClient` calls `clearToken` on the active source, which cascades through the provider graph and redirects to `/libraries`.

**Multi-server support:** `sourcesProvider` holds a list of `ServerSource` objects (persisted via `shared_preferences`). `activeSourceIdProvider` tracks which source the current screen is operating against. `apiClientProvider` derives from both.

**Local progress queue:** Reading progress is written to a local SQLite DB (`sqflite`) and synced to the server with a 3-second debounce. On reconnect, `syncPendingProgress` flushes unsynced rows.

**Reader:** `reader_provider.dart` holds `ReaderState` (currentPage, totalPages, direction, doublePage, scrollMode, spreads). Page-turn navigation gates on `_pageAnimating` to prevent rapid-tap overshooting. Double-page mode uses `buildSlides()` which auto-detects landscape spreads and always isolates the cover (page 0).

---

## Android client architecture

**Single-activity** app. Navigation via Jetpack Compose `NavHost` (`NavGraph.kt`). All transitions use 150 ms fade with a `blockInput` overlay to prevent mis-taps during animations.

**ViewModels** are `@HiltViewModel`. Each screen has one ViewModel. `MultiSourceLibraryViewModel` is the top-level VM that owns the source list and library data; it uses a raw `OkHttpClient` directly rather than Retrofit (the Retrofit singleton is for authenticated per-source calls).

**Retrofit singleton** is scoped to the active source via `BaseUrlInterceptor` (rewrites the base URL at request time from `PrefsStore.activeSource`). `AuthInterceptor` attaches the Bearer token. `UnauthorizedInterceptor` clears the active source token on 401, triggering `MainViewModel.tokenLost` which pops the nav stack to Libraries.

**Progress** is saved to a local Room-like table (`progress_queue`) via `ProgressQueueDao` and synced to the server on close or after a debounce. Completed archives reopen at page 0.

**Downloads** are managed by `DownloadRepository` which tracks per-archive and per-folder download state as `StateFlow`s consumed directly by screens.

---

## Key cross-cutting decisions

- **Completed archives restart at page 0.** Both clients check `isCompleted` from progress before restoring `currentPage`.
- **`NaturalStringComparer`** is used everywhere filenames are sorted (archive entries, directory listings) so "Chapter 2" < "Chapter 10".
- **`FilenameParser`** extracts series/volume/issue metadata from filenames. The scraper uses `media.Title` (folder name), not `media.Series` (parsed from issue filenames), to avoid wrong search terms.
- **Spread detection** is server-side: `width > height` per page, stored in the manifest. Clients consume the `spreads` boolean array; they do not detect spreads themselves.
- **Permission levels** are integers, not enums, in both server JWT claims and client prefs. Level 4 = admin everywhere.
