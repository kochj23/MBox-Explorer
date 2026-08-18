# Releasing MBox Explorer

The goal: ship a `.dmg` that end users can **open with a simple drag-and-drop, no Gatekeeper
warnings**. On macOS that requires the app to be **signed with a "Developer ID Application"
certificate** *and* **notarized by Apple**. A build signed only with an "Apple Development"
certificate (the default for local debug builds) is **rejected by Gatekeeper** and gives users the
dreaded *"the developer cannot be verified"* dialog.

`scripts/release.sh` automates the whole pipeline: **archive → export (Developer ID) → DMG →
notarize → staple → verify**.

## One-time setup

1. **Developer ID Application certificate** (needs a paid Apple Developer account, team `QRRCB8HB3W`).
   In Xcode: *Settings → Accounts → Manage Certificates → + → Developer ID Application*. Confirm it's
   installed:
   ```bash
   security find-identity -v -p codesigning | grep "Developer ID Application"
   ```

2. **Notary credentials as a keychain profile** (so no secrets live in the repo). Create an
   [app-specific password](https://support.apple.com/en-us/102654) for your Apple ID, then:
   ```bash
   xcrun notarytool store-credentials MBOX_NOTARY \
     --apple-id "you@digitalnoise.net" \
     --team-id QRRCB8HB3W \
     --password "abcd-efgh-ijkl-mnop"   # the app-specific password
   ```

3. **Metal Toolchain** (once per machine, needed to compile the MLX dependency):
   ```bash
   xcodebuild -downloadComponent MetalToolchain
   ```

## Cut a release

```bash
./scripts/release.sh 2.3.0        # or omit the version to use today's date
```

The script prints the finished path, e.g. `build/MBox-Explorer-2.3.0.dmg`. Upload that `.dmg` to a
[GitHub Release](https://github.com/kochj23/MBox-Explorer/releases). Users drag it to Applications and
it launches clean — the stapled notarization ticket means it works even offline.

## Overrides (env vars)

| Var | Default | Purpose |
|---|---|---|
| `SCHEME` | `MBox Explorer` | Xcode scheme to archive |
| `CONFIG` | `Release` | Build configuration |
| `TEAM_ID` | `QRRCB8HB3W` | Apple Developer team |
| `NOTARY_PROFILE` | `MBOX_NOTARY` | `notarytool` keychain profile name |

## Troubleshooting

- **`error: No signing certificate "Developer ID Application" found`** → step 1 above isn't done.
- **`Error: No Keychain password item found for profile: MBOX_NOTARY`** → step 2 above isn't done.
- **Notarization status `Invalid`** → run `xcrun notarytool log <submission-id> --keychain-profile MBOX_NOTARY`
  to see which binary failed (usually an un-signed nested helper — the export step signs everything,
  so this is rare).
- **`missing Metal Toolchain`** during archive → step 3 above.
