# In-app auto-update (Sparkle)

The app updates itself via [Sparkle 2](https://sparkle-project.org): it checks
the appcast feed named in `Info.plist` (`SUFeedURL`) in the background and
offers signed updates with Sparkle's standard install dialog. No Homebrew, no
manual DMG round-trips — the first install is the only one done by hand.

## How the pieces fit

- **Feed:** `SUFeedURL` points at
  `https://github.com/clxte/meeting-transcriber/releases/latest/download/appcast.xml`.
  GitHub serves the asset of the newest **non-prerelease** release at that
  URL, so RC releases carry their own appcast without ever being offered to
  stable installs.
- **Appcast:** `scripts/generate-appcast.sh` writes a single-item feed and
  signs the DMG enclosure with the EdDSA private key. `release.yml` runs it on
  tag builds when the `SPARKLE_ED_PRIVATE_KEY` secret exists and attaches
  `appcast.xml` to the release next to the DMG; without the secret the release
  still ships and in-app update simply has nothing new to say.
- **Trust:** updates are only accepted when the enclosure signature verifies
  against `SUPublicEDKey` in `Info.plist`. Notarization protects the download
  the same way it protects the first install.
- **Versioning:** Sparkle compares `sparkle:version` against
  `CFBundleVersion`, which `build_release.sh` stamps with the release version
  (the checked-in plist's static `1` would otherwise never increase and no
  update would ever be offered). The dev bundle keeps `CFBundleVersion=1`,
  which conveniently orders *above* every `0.x.y` release, so dev builds are
  never prompted to "update" to a release.
- **Framework:** Sparkle is a dynamic framework; both bundle assemblers copy
  it to `Contents/Frameworks` (`scripts/lib/sparkle-resources.sh`), and the
  notarized build re-signs it inside-out — hardened-runtime library validation
  only loads frameworks signed by the app's own team.
- **Checks:** `SUEnableAutomaticChecks` is preset to true in `Info.plist`, so
  Sparkle never shows its "check automatically?" first-run prompt. A manual
  check lives in the menu bar ("Check for Updates..."), absent in the App
  Store variant (`#if !APPSTORE` — the store updates apps itself; a genuine
  MAS submission would additionally need the framework stripped, which this
  fork never does because it does not submit there).

## Key management

The EdDSA pair was generated with Sparkle's `generate_keys`:

- **Private key** — in the login keychain of the machine that generated it
  (item "Private key for signing Sparkle updates"). Never in the repo.
  For CI: export with `generate_keys -x sparkle-key.txt`, paste the file's
  content into the `SPARKLE_ED_PRIVATE_KEY` repo secret, delete the file.
- **Public key** — pinned as `SUPublicEDKey` in `Sources/Info.plist`.

Losing the private key means shipped apps will refuse every future update
(the public key baked into them can never verify again) — the escape hatch is
asking users to reinstall a DMG by hand. Back the keychain item up.

## Cutting an update

```bash
echo "0.8.1" > VERSION && git commit -am "chore: bump version to 0.8.1" && git push fork main
git tag v0.8.1 && git push fork v0.8.1
```

`release.yml` builds, notarizes, staples, publishes the release with DMG +
appcast. Installed apps see the update within a day (or immediately via
"Check for Updates...") and offer to install it.

## Testing an update cycle locally

1. Build and install the current version:
   `./scripts/build_release.sh --staple`, mount the DMG, drag to
   `/Applications`, launch once.
2. Bump `VERSION`, rebuild, and generate a local appcast for the new DMG:
   `SPARKLE_ED_PRIVATE_KEY=$(...) ./scripts/generate-appcast.sh --dmg … --version … --url "http://localhost:8000/MeetingTranscriber-….dmg" --output /tmp/serve/appcast.xml`
3. Serve DMG + appcast: `python3 -m http.server 8000 -d /tmp/serve`, and point
   the installed app at it:
   `defaults write app.meetingtranscriber SUFeedURL http://localhost:8000/appcast.xml`
4. "Check for Updates..." in the menu → Sparkle should offer, download,
   verify and relaunch into the new version. Clean up with
   `defaults delete app.meetingtranscriber SUFeedURL`.
