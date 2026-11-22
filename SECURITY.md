# Security policy

IPAForge processes IPA archives and signing credentials locally on the device.

- Never commit IPA files, P12 certificates, private keys, provisioning profiles, or passwords.
- Do not upload user archives or signing material to a server.
- The P12 and provisioning profile import flow copies selected files into the app's private Documents/SigningMaterial directory.
- The P12 password is held in the signing screen only for the duration of the operation and is cleared when signing succeeds or fails.
- Avoid logging certificate data, private keys, passwords, entitlements, or archive contents.
- Treat imported IPA files as untrusted input. Archive inspection rejects absolute paths, backslashes, NUL characters, dot traversal components, excessive entry counts, and declared expanded sizes above the configured limit.
- Archive inspection reads ZIP metadata; it does not extract every archive member. The current checks do not replace a full ZIP64, decompression-bomb, symlink, and disk-space test suite.
- Signing and repackaging must be tested against real IPA files before being considered production-ready.

## Current limitations

The signing implementation uses the RorkSign package, but end-to-end signing has not yet been verified with a real P12 certificate, matching provisioning profile, and target IPA. The app does not have a public iOS API for installing arbitrary IPA files directly.
