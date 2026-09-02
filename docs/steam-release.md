# Steam Release Runbook

All Steam IDs, account details, pricing, and release actions are owner-controlled
external inputs. Repository VDF files are examples with placeholders only.

## Account and app setup

1. Enroll the publisher in Steamworks and pay the Steam Direct fee for this app
   (currently USD $100 per product; verify the current fee and recoupment terms
   in Steamworks before payment).
2. Complete the publisher's banking, tax, identity, and payment-information
   checks. Keep those details and all Steam credentials outside this repository.
3. Create the app in Steamworks and record the assigned app ID plus separate
   Windows and Linux depot IDs. Never replace the placeholders in committed
   files with those IDs.

## Steam Cloud save

The game writes `user://pocket_circuit_save.json` and its `.bak` backup. With
the current Godot project name, the native locations are:

- Windows: `%APPDATA%\Godot\app_userdata\Pocket Circuit\`
- Linux/Steam Deck: `${XDG_DATA_HOME:-$HOME/.local/share}/godot/app_userdata/Pocket Circuit/`

Create Steam Auto-Cloud entries for both roots and include
`pocket_circuit_save.json` plus `pocket_circuit_save.json.bak`. Test a save made
on each OS, a cross-device download, offline play, and conflict handling before
enabling Cloud for customers.

## Build and depot upload

1. Install the official Godot 4.7.2 Linux and Windows x86_64 release templates.
2. From the repository root, run `./tools/build_release.sh`. Verify with
   `(cd builds && sha256sum --check SHA256SUMS)`. The build fails rather than
   retaining any unknown file in either depot directory.
3. Copy `steam/app_build_example.vdf` and both depot examples to a temporary
   directory outside the repository. Replace `<STEAM_APP_ID>`,
   `<WINDOWS_DEPOT_ID>`, `<LINUX_DEPOT_ID>`, `<CONTENT_ROOT>`,
   `<WINDOWS_DEPOT_CONFIG>`, and `<LINUX_DEPOT_CONFIG>` there. The two config
   placeholders must be the absolute paths of the completed depot VDF files.
   `<CONTENT_ROOT>` must contain the exported `windows/` and `linux/` folders.
4. Keep `"preview" "1"` for the first SteamPipe check. When the preview is
   correct, change it to `0` only in the temporary config.
5. Upload interactively; SteamCMD will request the account's password and Steam
   Guard response without storing them in the repository:

   ```bash
   ./steam/upload_build.sh --upload \
     --steamcmd /absolute/path/to/steamcmd \
     --account '<STEAM_ACCOUNT_NAME>' \
     --app-id '<STEAM_APP_ID>' \
     --windows-depot-id '<WINDOWS_DEPOT_ID>' \
     --linux-depot-id '<LINUX_DEPOT_ID>' \
     --config /absolute/path/to/completed/app_build.vdf \
     --windows-config /absolute/path/to/completed/windows_depot.vdf \
     --linux-config /absolute/path/to/completed/linux_depot.vdf
   ```

6. Assign the uploaded build to a password-protected test branch first. Verify
   both depot launch options, then promote the approved build to the intended
   release branch in Steamworks. Do not set a live branch in committed VDFs.

## Store and release gates

- Complete store page text, capsules, screenshots, trailer, platform support,
  system requirements, and controller disclosures.
- Obtain owner approval for base price and regional pricing before entering
  prices in Steamworks. Complete every required pricing/currency approval.
- Complete every required content and rights survey accurately; do not infer
  answers from this runbook.
- Submit the store page and release build for Valve review. Resolve review
  feedback and re-test the exact reviewed build on Windows, Linux, and Steam
  Deck.
- Satisfy Steam's current waiting periods and Coming Soon requirements. Verify
  them in Steamworks because policy can change.
- After Valve approval and the planned release time, the owner must use the
  Steamworks release process and press the final release button. Uploading or
  branch promotion alone does not publish the game.
