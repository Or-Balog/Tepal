# Credits and asset provenance

## Creator and maintainer

Tepal was created by **[Or Balog](https://www.linkedin.com/in/or-balog/)**, the project creator and maintainer. The third-party research and generated-artwork provenance are acknowledged below.

## Motion-sensor research

Tepal's Swift motion-sensor implementation was informed by the protocol research in [olvvier/apple-silicon-accelerometer](https://github.com/olvvier/apple-silicon-accelerometer). The source file `Sources/TepalMac/Knock/SPUMotionSensor.swift` records this reference. Tepal does not bundle the upstream Python package.

The upstream project is MIT-licensed, Copyright (c) 2026 olvvier. Its license notice is retained in [LICENSES/apple-silicon-accelerometer-MIT.txt](LICENSES/apple-silicon-accelerometer-MIT.txt). The upstream license was checked on 11 September 2026.

## Artwork

The botanical creature and forest habitat were created with the built-in image-generation tool during development of this project. The maintainer confirmed the creature's project origin on 11 September 2026; the background-generation prompt and selected generated concept are recorded in the private development archive.

Project materials are distributed under the [MIT License](LICENSE), with third-party notices retained as listed here.

Production images are bundled in `Sources/TepalApp/Resources/` and `Sources/TepalMac/Resources/`. The app icon is bundled under `Config/`. The README and launch-card screenshots are app-rendered test scenes. Any meeting details shown are fictional.

## Platform and sound

Tepal uses Apple's system frameworks, fonts and system symbols through the macOS SDK. They remain subject to Apple's terms; the project does not redistribute the SDK or font files. Sound cues are synthesized by Tepal's code rather than loaded from a third-party sound pack.
