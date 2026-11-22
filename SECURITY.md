# Security policy

IPAForge is designed to process app archives and signing credentials locally on the device.

- Never commit IPA files, P12 certificates, private keys, provisioning profiles, or passwords.
- Do not upload user archives or signing material to a server.
- Keep private-key handling in Keychain-backed APIs where possible.
- Avoid logging certificate data, private keys, passwords, entitlements, or archive contents.
- Treat imported IPA files as untrusted input. Validate archive paths and metadata before extracting files.
- Any future extraction implementation must defend against path traversal, symlinks, decompression bombs, and disk-space exhaustion.

The current prototype only copies and inspects IPA ZIP entries. It does not yet import signing credentials or modify code signatures.
