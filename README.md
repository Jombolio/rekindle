# Rekindle

Rekindle is a self-hosted comic, manga, and book server with clients for Linux, Windows, and Android.

Run the server on any machine that holds your archive files. Connect from any device running the client, browse your libraries, read in the browser-free native reader, and download issues for offline use. Multiple users are supported, each with their own reading progress and permission level.

> **Disclaimer:** Rekindle is intended for use with content you own or have the legal right to access. The developers are not responsible for any misuse.

<p align="center">
  <img width="200" src="rekindle.png" alt="Rekindle logo" />
</p>

<p align="center">
  <a href="https://github.com/Jombolio/rekindle/actions/workflows/build.yml">
    <img src="https://img.shields.io/github/actions/workflow/status/Jombolio/rekindle/build.yml?branch=main&label=build&style=flat-square" alt="Build status" />
  </a>
  &nbsp;
  <a href="https://github.com/Jombolio/rekindle/releases/latest">
    <img src="https://img.shields.io/github/v/release/Jombolio/rekindle?label=release&style=flat-square" alt="Latest release" />
  </a>
  &nbsp;
  <a href="https://discord.gg/qppBqPzkTp">
    <img src="https://img.shields.io/badge/discord-join-5865F2?style=flat-square&logo=discord&logoColor=white" alt="Discord" />
  </a>
</p>

<img width="1277" height="371" alt="Rekindle screenshot" src="https://github.com/user-attachments/assets/0f389771-0a4d-4c71-897b-85dcdccb26d6" />

---

## Downloads

| Platform | Where to get it |
|----------|----------------|
| Server (Linux / Windows) | [GitHub Releases](https://github.com/Jombolio/rekindle/releases) |
| Client — (Linux / Windows) | [GitHub Releases](https://github.com/Jombolio/rekindle/releases) |
| Client — Android | F-Droid · custom repo: `https://fdroid.jombo.uk/repo` |
| Client — Android (Fallback) | [GitHub Releases](https://github.com/Jombolio/rekindle/releases) |

---

## Documentation

Full guides, configuration reference, and FAQ are on the **[GitHub Wiki](https://github.com/Jombolio/rekindle/wiki)**.

Please at least read this before posting an issue or requesting support.

---

## Supported Formats

`.cbz` · `.cbr` · `.epub` · `.mobi` · `.pdf`

---

## Building from Source

See [Building from Source](https://github.com/Jombolio/rekindle/wiki/Building-from-Source) on the wiki.

**Requirements:** .NET 10 SDK · Flutter SDK

```bash
# Server
cd server && dotnet run --project Rekindle.Server

# Client
cd desktop && flutter run
```
