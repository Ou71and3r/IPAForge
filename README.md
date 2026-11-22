# IPAForge

An on-device iOS IPA import and signing utility.

## Project goals

- Import IPA files from the iOS Files app.
- Support large ZIP and ZIP64 archives using streaming extraction.
- Sign app bundles locally with a user-provided P12 certificate and provisioning profile.
- Preserve required entitlements, embedded provisioning profiles, frameworks, extensions, and nested code signatures.
- Export the signed IPA back to Files.

## Security principles

- IPA files and signing credentials stay on the device.
- Never upload certificates, private keys, provisioning profiles, or IPA contents to a server.
- Store private-key material securely and avoid logging secrets.

## Platform limitations

Installing arbitrary IPA files directly from a regular iOS app is restricted by iOS. The initial scope is local signing and export; installation options must be evaluated separately and must not be represented as guaranteed.

## Status

Project initialized. Implementation and device testing are pending.
