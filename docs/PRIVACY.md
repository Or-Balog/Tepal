# Privacy

Tepal runs locally. The app has no account, backend, network client, analytics or telemetry dependency.

## Calendar

Tepal reads events already synced by macOS. Google account authentication and synchronization happen in macOS, outside Tepal. Apple exposes Full Calendar Access rather than a separate read-only EventKit permission; Tepal's implementation has no calendar creation, edit, save, or deletion path.

Event titles, descriptions, locations, attendees and calendar names are not written into Tepal's persistent stores. Upcoming event summaries remain in memory. Stored calendar settings and reminder state contain selected opaque source/calendar IDs, opaque occurrence IDs, occurrence-start timestamps, and snooze deadlines.

## Local history and settings

Tepal stores preferences, the pet name, timer recovery, completed-focus dates/durations and unlocked cosmetic rewards locally. Use **Settings → Privacy → Clear All Local Data** to clear Tepal's data. This does not change your Calendar events or macOS Login Items. Turn off launch at login separately if enabled.

## Double-knock

Double-knock sensing is optional and off by default for new users. On compatible Macs, the app processes motion-sensor samples in memory and reports recognized gestures. It does not record microphone audio, keystrokes, or raw motion samples to disk. Development fixtures are separate from the app's runtime data.

The sensor uses an undocumented Apple Silicon hardware interface. Tepal runs without App Sandbox to support it. Its local-only behavior is implemented in code; it is not enforced by a network-denying sandbox. Calendar access still requires macOS permission.
