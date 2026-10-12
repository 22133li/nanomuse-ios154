# nanoMuse iOS 15.4 Backport

nanoMuse iPhone/iPad app ([nano-muse/nanoMuse](https://github.com/nano-muse/nanoMuse),
`android/src/ios`, OpenMinis 1.13-based) backported to run on **iOS 15.4**.

Upstream requires iOS 16.0+. This tree carries the 15.4 compatibility changes:

- Deployment target 16.0 → 15.4 (app, Share/FileProvider/Widget extensions)
- `NavigationStack` → `NavigationView`; programmatic (`path:`) navigation
  reworked onto `NavigationLink(isActive:)` (1-level chat stack, 2-level settings)
- AppIntents declarations gated `@available(iOS 16, *)` (Siri/Shortcuts off on 15.4)
- `PhotosPicker` → `PHPickerViewController` wrapper (`NanoMusePHPicker`)
- iOS 16/17-only API usages audited with 15.4 fallbacks

## Build

GitHub Actions (`iOS 15.4 Backport Build`, `macos-15`): builds the native
dependencies from source (LAME → FFmpeg → iSH → Alpine rootfs → rclone),
archives unsigned, zips the IPA and uploads it as the `nanoMuse-iOS154`
artifact. Sideload the IPA on a jailbroken device (TrollStore / Sileo).

## License

GPL-3.0-or-later, same as upstream. See upstream `LICENSE`.
