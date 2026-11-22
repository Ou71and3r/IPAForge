# IPAForge

IPAForge is an iOS app prototype for importing, inspecting, locally signing, and exporting IPA files.

## Implemented in source

- SwiftUI iOS application targeting iOS 16 and later.
- Imports an `.ipa` file through the iOS document picker and copies it into the app's private Documents/Imported directory.
- Inspects ZIP entries with ZIPFoundation without extracting the full archive.
- Reports archive size, entry count, total declared uncompressed size, Payload presence, app bundle names, and Info.plist entries.
- Rejects unsafe archive paths, symbolic links, duplicate/colliding paths, more than 200,000 entries, and declared expanded sizes above 20 GiB.
- Imports P12 and MobileProvision files into the app's private Application Support/SigningMaterial directory. Imported signing material is excluded from backups and stored with complete file protection.
- Contains an on-device signing flow using the RorkSign package, checks selected provisioning profiles against the signing identity, matches profiles to bundle identifiers, and exports its output through the iOS share sheet.
- Writes signed output through a temporary file and moves it into place without overwriting an existing signed IPA.
- GitHub Actions builds both the iOS Simulator and generic iOS device targets without code signing, and runs archive-path security tests on the simulator.

## Validation status

Latest GitHub Actions run for commit `c846c7d` (22 November 2026) passed:
- iOS Simulator build.
- Archive path security tests.
- Generic iOS device build.

This confirms compilation for the simulator and generic iOS device targets, but does not constitute installation or execution on a physical iPhone.

The signing implementation has not yet been validated end-to-end with a real IPA, P12 certificate, and matching provisioning profiles. The signing dependency includes ZIP64 archive reader/writer code, but ZIP64 handling and the motivating 4 GB-class archive still require dedicated end-to-end tests on a real device; source-level support is not proof of successful 4 GB signing.

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

**Status: prototype.** Simulator/device-target compilation and archive-path security tests pass in CI. Real signing, physical-device execution, ZIP64 handling of very large files, and installation have not yet been demonstrated end-to-end.
