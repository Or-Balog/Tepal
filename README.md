# Tepal

A native Mac companion for focus sessions and calendar reminders.  
Created by **[Or Balog](https://www.linkedin.com/in/or-balog/)**.

<img src="docs/assets/tepal-ready.png" width="360" alt="Tepal: a small leafy creature in a forest, with a 25-minute focus timer below">

Tepal lives in your Dock, with a forest habitat one click away. It keeps time, remembers your focus sessions, and can remind you about meetings from calendars synced through macOS. Everything stays on your Mac.

## A few useful details

**Focus until your next meeting.** Start a session that ends two minutes before the meeting, leaving time to get ready.

**Check what's next with two taps.** Optional double-knock sensing brings up your next event on compatible Macs. It is off by default.

**Keep what you've finished.** Completed focus sessions grow your companion and unlock palettes. Pausing or closing the app preserves timer recovery.

<img src="docs/assets/tepal-focus.png" width="260" alt="Tepal during a focus session"> <img src="docs/assets/tepal-rest.png" width="260" alt="Tepal during a rest period">

<sub>App-rendered test scenes. Meeting details shown here are fictional.</sub>

## Try it from source

**Apple silicon · macOS 26+ · Swift 6.2+**

With matching Xcode or Command Line Tools installed, run these commands from the repository folder:

```bash
git clone https://github.com/Or-Balog/Tepal.git
cd Tepal
Scripts/test.sh
Scripts/package-app.sh release
open dist/Tepal.app
```

This is an early source release. The packaged app is ad-hoc signed; a notarized download is not available yet. [Build and installation details →](docs/DEVELOPMENT.md)

## Your calendar, on your Mac

Tepal has no account, backend, analytics or network client. For reminders, connect a Google account through macOS Internet Accounts, then choose your calendars in Tepal. The timer works without this connection.

macOS asks for Full Calendar Access, but Tepal only reads events. Event titles stay in memory. The optional motion sensor uses an undocumented hardware interface, so the app runs without App Sandbox. [Privacy details →](docs/PRIVACY.md)

## Made by Or Balog

I built Tepal because I kept running into two problems at work: getting distracted when I wanted to focus, and missing calendar popups when I finally did. Sometimes that meant showing up late to a meeting.

I wanted a focus timer and meeting reminders in one small companion. Tepal is my attempt at that.

— **[Or Balog](https://www.linkedin.com/in/or-balog/)**

Built in Swift with AppKit and SwiftUI, with no third-party Swift package dependencies.

The name comes from *tepal*, a leaf-like part of a flower. It fits the creature's leafy shape, with a small “pal” at the end.

Bug reports and focused contributions are welcome. [Contributing](CONTRIBUTING.md) · [Beta status](docs/BETA.md) · [Credits](CREDITS.md)

---

[MIT License](LICENSE) · Copyright © 2026 **Or Balog**
