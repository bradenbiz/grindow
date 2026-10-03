# Local Grindow builds

Build and package the app with:

```sh
sh Scripts/build-local.sh
```

The output is `build/Grindow.app`. Quit the running copy before reopening it.
Xcode builds use the same identity once setup has written the git-ignored
`Config/Signing.local.xcconfig`. Without that file (a fresh clone, CI), the project
falls back to ad-hoc signing from `Config/Signing.xcconfig` so it still builds.
Do not re-sign with `codesign --sign -`: ad-hoc signing changes the app's designated
requirement between builds and breaks Accessibility permission continuity.

## One-time setup on a Mac

```sh
sh Scripts/setup-local-signing.sh
```

This creates **Grindow Local Development**, a ten-year self-signed code-signing
certificate, imports its private key into the default user keychain, and writes
`Config/Signing.local.xcconfig` so Xcode signs with it too. Re-run it after a fresh
clone to restore that file. Trust is
limited to code signing in the user's trust settings. Temporary key/export files
are removed. Only `/usr/bin/codesign` is preauthorized to use the imported key;
macOS may still ask for Keychain authorization when it is first used. Choose
Always Allow for that Grindow key if you want unattended subsequent builds.

Keep this certificate and private key. Re-running setup preserves an existing
valid identity and refuses to replace an incomplete one. Build refuses to fall
back to ad-hoc signing if the identity is missing. The key is not stored in git.
This identity is for local development, not notarized public distribution.

After the first certificate-signed build, remove the old Grindow Accessibility
entry and add `build/Grindow.app` once. Later updates with the same certificate,
bundle identifier, and designated requirement should retain that grant. Actual
permission retention must be confirmed after that one-time grant and an update.

To inspect the identity and validate the build:

```sh
codesign -d -r- build/Grindow.app
codesign --verify --deep --strict build/Grindow.app
```

The designated requirement should contain the bundle identifier and certificate
fingerprint, rather than only a `cdhash`. The build output location stays fixed even
when `GRINDOW_DERIVED_DATA` overrides the Xcode intermediate directory.
