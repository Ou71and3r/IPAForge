# IPAForge

IPAForge is an iOS app prototype for importing, inspecting, locally signing, and exporting IPA files.

## Implemented in source

- SwiftUI iOS application targeting iOS 16 and later.
- Imports an `.ipa` file through the iOS document picker and copies it into the app's private Documents/Imported directory.
- Inspects ZIP entries with ZIPFoundation without extracting the full archive.
- Reports archive size, entry count, total declared uncompressed size, Payload presence, app bundle names, and Info.plist entries.
- Rejects unsafe archive paths, symbolic links, duplicate/colliding paths, more than 200,000 entries, and declared expanded sizes above 20 GiB.
- Imports P12 and MobileProvision files into the app's private Application Support/SigningMaterial directory.
- Excludes imported IPA files, signed IPA exports, and signing workspaces from device backups; applies iOS file protection to these files. Imported signing material is excluded from backups and stored with complete file protection.
- Contains an on-device signing flow using the RorkSign package, checks selected provisioning profiles against the signing identity, matches profiles to bundle identifiers, and exports its output through the iOS share sheet.
- Writes signed output through a temporary file, re-inspects the completed archive before export, and moves it into place without overwriting an existing signed IPA.
- Cleans abandoned signing workspaces and partial outputs older than 24 hours after an interrupted operation.
- GitHub Actions builds both the iOS Simulator and generic iOS device targets without code signing, and runs archive-path security tests on the simulator.

## Validation status

The latest GitHub Actions run builds both the iOS Simulator and generic iOS device targets. It also runs the archive-path security tests and the OTA manifest validator tests.

CI compilation and unit tests do not constitute installation or execution on a physical iPhone. ZIP64 handling with a real 4 GB-class IPA still requires a dedicated end-to-end device test.

The OTA flow starts a loopback HTTP server, streams the IPA from disk in 1 MiB chunks, requests a manifest from the external HTTPS manifest generator, and validates the returned property list before opening the iOS installation handoff. The IPA itself is not uploaded to the manifest service. The local download and final installation still require physical-device validation on the target iOS version.

## Build

The project is generated with XcodeGen.

1. Install Xcode and XcodeGen.
2. Run `xcodegen generate` in the repository root.
3. Open `IPAForge.xcodeproj` in Xcode.
4. Select an iPhone simulator or a connected iPhone and build.

The project uses Swift Package Manager to fetch ZIPFoundation and RorkSign.

## Installation

IPAForge provides an OTA installation handoff for the signed IPA. It validates the embedded provisioning profile and the manifest response before opening the iOS installation flow. Ad Hoc profiles must include the UDID of the iPhone being used; Enterprise profiles do not require a device list.

The installation handoff depends on iOS accepting the local loopback download URL and the external manifest generator being reachable. This flow must be tested on a physical iPhone before it can be considered fully validated.

## Security

IPA files and signing credentials are intended to remain on-device. Never commit IPA files, P12 files, provisioning profiles, private keys, or passwords. See [SECURITY.md](SECURITY.md).

**Status: active development.** CI covers simulator and device-target builds plus automated archive and manifest validation. Physical-device OTA installation and large ZIP64 archive handling remain the final end-to-end validation items.
