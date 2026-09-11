# Contributing to Tepal

Small, focused improvements are welcome. Explain the problem, the change and how it was checked. For substantial changes, discuss the approach with the maintainer before starting.

## Development

Use an Apple-silicon Mac on macOS 26+ with Swift 6.2+ and matching Xcode or Command Line Tools.

```bash
Scripts/test.sh
Scripts/package-app.sh release
```

`TepalCore` holds timer, reminder and creature policies. `TepalMac` owns macOS integration, persistence, rendering and motion sensing. `TepalApp` owns the UI and app lifecycle.

Keep changes compatible with saved settings/history. Preserve the internal compatibility identifiers documented in [Development](docs/DEVELOPMENT.md). Add regression coverage when a change could lose user data or alter timer/reminder behavior.

Do not add telemetry, network services, calendar writes, new permissions or bundled third-party assets without discussing the product and privacy implications first. Cite the source and include the appropriate notice for externally derived code or assets.

## Reporting problems

Include steps to reproduce, expected/actual behavior, Mac model, macOS version and app version. Share the smallest useful excerpt of a diagnostic, not an entire personal log or Calendar export. Do not post credentials or private event content in public issues.

## Source snapshot

The public source snapshot intentionally excludes local development history, design experiments, diagnostics and build products. `Scripts/export-source.py` uses a reviewed file list in `Config/public-source-files.txt`; add new publishable files there deliberately.
