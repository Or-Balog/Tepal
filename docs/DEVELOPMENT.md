# Development and installation

Tepal is a local native macOS companion that lives in its Dock tile, runs drift-free Pomodoro cycles, and reads locally synced Calendar events for on-screen pet reminders. It has no account, backend, analytics, network client, native-notification integration, or calendar write path.

## Requirements

- Apple-silicon Mac running macOS 26.0 or later.
- Xcode 26 or the matching Command Line Tools with Swift 6.2 or later.
- A Google account added to macOS under **System Settings > Internet Accounts** if Calendar reminders are wanted. Pomodoro-only use does not require Calendar access.

## Build and test

From the repository root:

```bash
Scripts/test.sh
swift build -c release
Scripts/package-app.sh release
```

The packaging script accepts only `debug` or `release` and assembles one app: `dist/Tepal.app`. It applies an ad-hoc signature with the Calendar entitlement. Tepal runs without App Sandbox so its optional double-knock feature can access the motion sensor. Verify a release candidate with:

```bash
codesign --verify --deep --strict --verbose=2 dist/Tepal.app
plutil -lint Config/Tepal-Info.plist Config/Tepal.entitlements
```

Some Command Line Tools installations have a SwiftPM Testing-framework staging issue. This repository's verified fallback command is:

```bash
CLANG_MODULE_CACHE_PATH=/private/tmp/tepal-clang-cache \
swift test --disable-sandbox --cache-path .build/swiftpm-cache \
  -Xswiftc -F \
  -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath \
  -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath \
  -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```

## Double-knock for the next event

There is one Tepal app. After Calendar setup, enable **Settings > Pet > Double-knock for my next event** to use two gentle desk taps to display the next event. This is off by default for new users. Existing preferences are preserved when upgrading from the former experimental build. Motion sensing stays local and does not record the keyboard or microphone. Results depend on the Mac model and desk; **Preview next event** is available without sensing.

App Sandbox blocked the driver update required to receive motion samples during development. Tepal therefore uses the former non-sandboxed build as its single distribution profile. Calendar access still requires macOS permission. The reference for the sensor research is listed in [Credits](../CREDITS.md).

## Upgrade compatibility

Tepal uses the bundle identifier `com.or-balog.tepal`, which also names the app's `Logger` subsystems.

The `dockpet.v1.*` preference keys, the serialized `moonmossPalette` key and the `DockPetHistory` store name are compatibility identifiers inside the app's own storage, not display names. Renaming them would discard existing settings and history for no benefit.

Quit an older running copy before launching Tepal. A rebuilt ad-hoc signature can cause macOS to ask for Calendar access again. Check **Launch at login** after moving the app.

## Install locally

Quit Tepal, then use Finder to move only the existing `/Applications/Tepal.app` bundle to Trash. Copy into a confirmed-empty destination so stale files from an older bundle cannot survive a merge:

```bash
test ! -e /Applications/Tepal.app || {
  echo "Refusing to merge over an existing /Applications/Tepal.app; move that exact bundle to Trash first."
  exit 1
}
cp -R dist/Tepal.app /Applications/Tepal.app
open /Applications/Tepal.app
```

The app is ad-hoc signed for local use; it is not a notarized public distribution. After source changes, rebuild, move the old exact bundle to Trash, and copy the new bundle into the empty `/Applications/Tepal.app` path. Do not use a merge copy when replacing the app.

On first launch, Tepal explains Calendar access before requesting it. Confirm only a CalDAV source you know is your Google account, then select the calendars to read. If the account is absent or permission is denied, choose Pomodoro-only mode; the pet and timer remain operational.

## Calendar privacy

Apple does not provide a read-only EventKit permission. Tepal therefore asks for **Full Calendar Access**, but its behavior is read-only:

- The EventKit adapter exposes authorization, calendar listing, event fetching, and change observation only.
- Application code has no EventKit save, remove, commit, create, edit, delete, accept, or decline path.
- Upcoming event summaries remain in memory. For calendar selection, reminder deduplication, and snooze, local persistence contains selected opaque source/calendar identifiers, opaque occurrence identifiers, occurrence-start timestamps, and snooze deadlines. It never persists event titles, descriptions, locations, attendees, or calendar names.
- A failed, denied, revoked, or removed Calendar source clears stale in-memory schedule data without disabling Pomodoro.

Tepal has no network client and no analytics or telemetry dependency. The app is not sandboxed; these are application behavior guarantees, not sandbox-enforced restrictions. Google synchronization is performed by macOS Calendar, outside Tepal.

## Launch at login

After installing in `/Applications`, open **Settings > Pet** and toggle **Launch at login**. Registration uses Apple's documented `SMAppService.mainApp` API only in direct response to that toggle. The control displays the current macOS registration state; a failed change shows an error and is not saved as if it succeeded. If macOS reports that approval is required, allow Tepal under **System Settings > General > Login Items**.

Moving or replacing the app can invalidate registration. Reopen the installed copy and check the toggle. Turning launch at login off is a separate direct action; clearing Tepal's local data does not silently edit macOS Login Items.

## Clear local data

Open **Settings > Privacy > Clear All Local Data** and confirm. This removes:

- preferences and Google-calendar selections;
- active timer recovery and reminder occurrence/snooze keys;
- completed-focus dates and recorded durations; and
- unlocked cosmetic rewards.

It also clears in-memory event summaries immediately. It never changes Calendar events. If launch at login is enabled, turn that toggle off separately before or after clearing data.

## Remaining hands-on acceptance

See [Beta status](BETA.md) for dated verification and outstanding manual checks. On a normal interactive desktop, run:

```bash
open /Applications/Tepal.app
Scripts/package-app.sh debug
open -n dist/Tepal.app --args --demo-meeting-seconds 15
```

Use the first command to exercise Dock bottom/left/right/auto-hide layouts, multiple displays, fullscreen Spaces, keyboard navigation, VoiceOver, light/dark appearance, Reduced Motion, timer recovery, Calendar grant/revocation, and the installed launch-at-login toggle. The debug-only second launch provides a local 15-second reminder fixture; rebuild `release` afterward because the fixture is intentionally absent from release binaries.

For the required energy check, use Xcode Instruments **Energy Log** for at least 10 idle minutes and **Time Profiler** for at least two active Pomodoro minutes. Record average CPU, wakeups, memory trend, and Dock redraw behavior. These profiling checks require full Xcode with Instruments; do not infer energy use from automated tests.

New focus sessions retain their original duration across pauses, restarts, and timer-preference changes. Older history records show “Duration not recorded.” A temporary history update failure preserves the last verified pet growth and displays a status message.

### Focus until your next meeting

While idle with a connected calendar, open **More (•••) → Focus until my next meeting · 2 min prep**. Tepal starts a one-off focus session ending two minutes before the next timed meeting, then shows its preparation reminder. This explicitly chosen reminder also works when routine meeting alerts are disabled. The option requires at least three minutes until the meeting and is unavailable during an ongoing meeting. Your normal focus duration is unchanged.

The selected end time is fixed for that session. Pausing or restarting the app does not push it past that time. A session that is still paused when the deadline arrives returns to idle without counting a completed focus. The preparation reminder is omitted if a refreshed calendar shows the selected occurrence moved or was cancelled. No next phase starts automatically after this session.
