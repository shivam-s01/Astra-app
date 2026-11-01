<div align="center">

<img src="assets/images/aurum_logo.png" alt="Astra Music logo" width="120" />

# Astra Music

A music streaming app for Android with a native Kotlin audio engine and a Flutter interface.

<br/>

[![Version](https://img.shields.io/badge/version-2.3.2-E8628A?style=flat-square)](https://github.com/shivam-s01/Aurum-app/releases/latest)
[![Android](https://img.shields.io/badge/Android-arm64-3DDC84?style=flat-square&logo=android&logoColor=white)](https://github.com/shivam-s01/Aurum-app/releases/latest)
[![Flutter](https://img.shields.io/badge/Flutter-3.35-02569B?style=flat-square&logo=flutter&logoColor=white)](https://flutter.dev)
[![Kotlin](https://img.shields.io/badge/Kotlin-Media3-7F52FF?style=flat-square&logo=kotlin&logoColor=white)](https://developer.android.com/media/media3)
[![Languages](https://img.shields.io/badge/languages-26-8A63D2?style=flat-square)](#languages)

[Download](https://github.com/shivam-s01/Aurum-app/releases/latest) ·
[Features](#features) ·
[Languages](#languages) ·
[Support](https://astra.mmusic.workers.dev/support)

</div>

---

## About

Astra Music is a solo project. I wanted a music app that looks as good as the big ones but stays light on cheap phones: no stutter, no heat, no battery drain.

It started as a Flutter web app and is now a proper Android app. Playback runs on a native Media3 engine written in Kotlin instead of a Flutter audio plugin, so the background service, notification and lock-screen controls behave like they do in a native app. Flutter handles everything you see.

The repo and package are called **Aurum**. That was the working name; the app you install is Astra Music.

---

## Features

**Playback**
- Native Media3 engine with its own background media session, notification and lock-screen controls
- Gapless playback and crossfade
- Equalizer with bass boost, virtualizer and loudness
- Waveform seek bar
- Queue with reorder, remove and play next; loop (off, all, one) and shuffle
- Auto-queue that adds related songs and skips duplicates
- Sleep timer, plus an auto sleep guard
- Shake to skip
- Chromecast

**Finding music**
- JioSaavn and YouTube Music behind one search, with retry and fallback if a source fails
- Search suggestions as you type
- Moods and genres, artist and album pages, personalised mixes
- Home content follows your region

**Library**
- Favorites, playlists, followed artists and albums, listening history
- Import a playlist from a Spotify or YouTube link
- Offline downloads saved through Android MediaStore, with ID3 artwork embedded
- Cloud sync across devices with Google sign-in
- Line-synced lyrics (LRC), with plain text when synced lyrics are not available

**Together**
- Jam sessions: listen in sync with friends using a room code or a share link
- Link TV: approve a sign-in on the Astra TV app by scanning its QR code

**Look and feel**
- Dark, light, AMOLED and Material You (wallpaper) themes
- Three full-player layouts
- Player backgrounds that pick up colors from the current artwork
- Optional glass effect on the navigation bar and mini player
- Dynamic Island style overlay with adjustable position, size and accent color
- Home-screen widget
- Haptics and shared-element transitions

**Battery, data and privacy**
- Battery saver and data saver modes
- Capped image cache, so storage does not keep growing
- App lock with biometrics or device credentials
- Privacy policy and terms inside the app

**Astra Plus** is an optional paid tier.

---

## Download

Every release has one APK, built for **arm64-v8a**. That covers nearly every phone from the last several years.

1. Open the [latest release](https://github.com/shivam-s01/Aurum-app/releases/latest).
2. Download `astra-music-arm64-v8a-release.apk`.
3. Open it and allow installs from your browser or file manager if Android asks.

The app checks GitHub for new releases and shows an update prompt when there is one.

---

## Languages

26 languages, using Flutter's `gen-l10n` and one ARB file each.

English, Hindi, Tamil, Punjabi, Urdu, Persian, Arabic, French, Spanish, Portuguese, Italian, German, Dutch, Swedish, Polish, Romanian, Ukrainian, Russian, Greek, Turkish, Indonesian, Vietnamese, Thai, Japanese, Korean and Chinese (Simplified).

---

## Support

There are no ads in the app, and I build and maintain it alone. If you like it, you can [leave a tip](https://astra.mmusic.workers.dev/support). Tips are optional and unlock nothing. Telling a friend about the app helps just as much.

---

## Contact

Built by Shivam Sharma.

[![Instagram](https://img.shields.io/badge/Instagram-%40shivam__shrma.01-E4405F?style=flat-square&logo=instagram&logoColor=white)](https://www.instagram.com/shivam_shrma.01)
[![Telegram](https://img.shields.io/badge/Telegram-mr__s__s01-26A5E4?style=flat-square&logo=telegram&logoColor=white)](https://t.me/mr_s_s01)
[![LinkedIn](https://img.shields.io/badge/LinkedIn-shivam--s01-0A66C2?style=flat-square&logo=linkedin&logoColor=white)](https://linkedin.com/in/shivam-s01)
[![GitHub](https://img.shields.io/badge/GitHub-shivam--s01-181717?style=flat-square&logo=github&logoColor=white)](https://github.com/shivam-s01)

Found a bug or have an idea? [Open an issue](https://github.com/shivam-s01/Aurum-app/issues) or message me on Telegram.

---

## Legal

The source is visible for reading only. It is not open source; see [LICENSE](LICENSE) and [COPYRIGHT.md](COPYRIGHT.md). Copying, rebuilding or redistributing the code, design or branding is not allowed without written permission.

- [Privacy Policy](https://astra.mmusic.workers.dev/privacy)
- [Terms of Use](https://astra.mmusic.workers.dev/terms)

Astra Music is an independent project and is not affiliated with, endorsed by or sponsored by JioSaavn, YouTube or Google. All music, artwork and trademarks belong to their owners. The app gives access to publicly available streams and is meant for personal use.

<div align="center">

© 2026 Shivam Sharma. All rights reserved.

</div>
