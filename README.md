# IPAForge

IPAForge is an iOS app project for importing, inspecting, locally signing, and exporting IPA files.

## Current implementation

- SwiftUI iOS application scaffold.
- Imports an `.ipa` file through the iOS document picker.
- Copies the selected file into the app's private Documents/Imported directory.
- Opens and enumerates the archive with [ZIPFoundation](https://github.com/weichsel/ZIPFoundation).
- Reports archive size, entry count, total uncompressed size, Payload presence, app bundle names, and Info.plist entries.
- Includes a macOS GitHub Actions build workflow.

The archive library advertises large-file support and deterministic memory consumption. ZIP64 compatibility still needs verification against real-world ZIP64 test archives, including the 4 GB-class file that motivated this project.

## Build

The project is generated with XcodeGen.

1. Install Xcode and XcodeGen.
2. Run `xcodegen generate` in the repository root.
3. Open `IPAForge.xcodeproj` in Xcode.
4. Select an iPhone simulator or a connected iPhone and build.

The project uses Swift Package Manager to fetch ZIPFoundation.

## Roadmap

1. Validate ZIP64 reading and large-file behavior with test fixtures.
2. Add safe, streaming extraction with path traversal and disk-space protections.
3. Add local P12 and provisioning-profile import with Keychain-backed secret handling.
4. Implement and test Mach-O / bundle signing, including nested frameworks and extensions.
5. Repackage and export the signed IPA.
6. Evaluate supported installation workflows separately; iOS does not expose a general public API for installing arbitrary IPA files from a regular app.

## Security

IPA files and signing credentials must remain on-device. Never commit IPA files, P12 files, provisioning profiles, private keys, or passwords. See [SECURITY.md](SECURITY.md).

## Status

**Prototype 0.1.0.** IPA import and archive inspection are implemented in source. Signing, repackaging, and direct installation are not implemented yet.
