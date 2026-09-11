# Beta status

Tepal is a local development beta for Apple-silicon Macs running macOS 26 or later. No notarized public binary is provided in this source snapshot.

## Verified on 11 September 2026

- The Tepal rename passed 313 automated tests across 22 suites.
- Compatibility checks read an old palette/preferences record and a history store written before the module rename.
- The release app built and passed deep/strict ad-hoc signature verification.
- The packaged app's name, settings, menus and optional double-knock control were inspected directly.

These are dated development results, not a claim that every Mac configuration has been tested.

## Known limits and remaining checks

- Calendar connection requires a Google account synced through macOS and explicit Calendar consent. An ad-hoc rebuild can trigger a new consent request.
- Double-knock depends on the Mac model, OS and surface. It uses an undocumented sensor interface and may be unavailable. Use Preview next event when sensing is unavailable.
- The app runs without App Sandbox. A crash or forced termination may prevent restoration of the sensor driver's previous reporting interval.
- Complete a real Calendar reminder and physical double-knock trial with the app's windows closed before wider distribution.
- Complete measured energy/CPU checks, VoiceOver navigation, display scaling, multiple displays, Dock positions/auto-hide, full-screen Spaces and Reduced Motion interaction checks.
- Check installed launch-at-login behavior from `/Applications/Tepal.app`.
- Prepare Developer ID signing and notarization before offering a convenient public binary.

Please describe your Mac model, macOS version, app version and reproduction steps when reporting a bug. Omit private Calendar details and credentials.
