# IPAForge

IPAForge is an iOS app prototype for importing, inspecting, locally signing, and exporting IPA files.

## Implemented in source

- SwiftUI iOS application targeting iOS 16 and later.
- Imports an `.ipa` file through the iOS document picker and copies it into the app's private Documents/Imported directory.
- Inspects ZIP entries with ZIPFoundation without extracting the full archive.
- Reports archive size, entry count, total declared uncompressed size, Payload presence, app bundle names, and Info.plist entries.
- Rejects unsafe archive paths, more than 200,000 entries, and declared expanded sizes above 20 GiB.
- Imports P12 and MobileProvision files into the app's private Documents/SigningMaterial directory.
- Contains an on-device signing flow using the RorkSign package and exports its output through the iOS share sheet.
- GitHub Actions builds both the iOS Simulator and generic iOS device targets without code signing.

## Validation status

A successful simulator build has been recorded. A generic iOS device build is now part of CI and must pass before device compilation is considered verified.

The signing implementation has not yet been validated end-to-end with real signing credentials and an IPA. ZIP64 support and the motivating 4 GB-class archive also require dedicated real-file tests; metadata inspection alone is not proof of full ZIP64 signing/repacking support.

## Build

The project is generated with XcodeGen.

1. Install Xcode and XcodeGen.
2. Run `xcodegen generate` in the repository root.
3. Open `IPAForge.xcodeproj` in Xcode.
4. Select an iPhone simulator or a connected iPhone and build.

The project uses Swift Package Manager to fetch ZIPFoundation and RorkSign.

## Installation limitation

A regular iOS app cannot install arbitrary IPA files through a public system API. Supported distribution paths such as Apple Configurator, TestFlight, or an appropriately hosted OTA manifest must be evaluated separately. IPAForge does not currently claim direct self-installation.

## Security

IPA files and signing credentials are intended to remain on-device. Never commit IPA files, P12 files, provisioning profiles, private keys, or passwords. See [SECURITY.md](SECURITY.md).

**Status: prototype.** The source includes archive inspection and a signing workflow, but successful signing, ZIP64 handling of very large files, and installation have not yet been demonstrated end-to-end.
