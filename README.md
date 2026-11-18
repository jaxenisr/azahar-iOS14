# Azahar for iPadOS 14

Play 3DS games on an iPad that can't be updated. No OS upgrade, free.

3DS emulation powered by [Azahar](https://github.com/azahar-emu/azahar) (GPLv3+).

## Download

**[Get the latest IPA →](../../releases/latest)**

1. Install [TrollStore](https://github.com/opa334/TrollStore) on your iPad.
2. Download `Azahar-iOS.ipa` and open it with TrollStore.
3. Launch the app, import your system files, then import a game.

The IPA is ad-hoc signed, so it installs through TrollStore, not the App Store.
Tested on an iPad 8th gen (A12) running iPadOS 14.7.1.

## What you need

- **3DS system files** (shared font/sysdata and a NAND image). No game boots without
  them. Put them in the app's `Documents/Azahar` folder.
- **Your game files** (`.3ds` or `.cci`). Put them in `Documents/ROMs`, either through
  the Files app or the import button.
- **No ROMs, keys or system files are included** in this app or its releases, and none
  ever will be. Bring your own.

## What it does

- Both screens, stacked like the handheld, with side-by-side and top-only layouts.
- Working touchscreen on the lower screen, in game and in menus.
- Working sound through the speaker.
- Controls drawn in the margins so they never cover the game, plus MFi controllers.
- Per-title settings: resolution scale, screen layout, speed, CPU clock, region,
  volume, control opacity and size.
- Console model (New 3DS or the original), texture filter and system region on the
  Emulation page, all read when a game starts.
- Cheats: one Gateway cheat file per title in `Documents/Azahar/cheats`, with a
  switch per cheat on the Emulation page. The core loads the file itself at start.
- Texture packs: a folder per title in `Documents/Azahar/load/textures`, with the
  load and dump switches beside the other graphics options.
- Amiibo: a dump per figure in `Documents/Azahar/amiibo`, loaded from the player
  while the game is asking for a tag. The core writes progress back into its copy,
  so your own dump is never modified.
- CPU JIT when the install allows one: if the app can run code it generates —
  TrollStore's JIT before launch, or a debugger attached to a build signed with
  `get-task-allow` — the emulated ARM11 is compiled as it runs. The Emulation page
  offers the choice and reports which is in force; without that permission the CPU
  is interpreted, and so is the next load after one that died with the JIT on.
- Artic Base: stream the title a console on your network has open, from the Games
  page's menu. The address is all it asks for, and nothing is copied to the iPad.
- A HUD with real numbers: fps, speed %, frame time, audio buffer and underruns.

## Performance, honestly

Without JIT the CPU is interpreted, so what runs well depends on the game (with
JIT enabled the CPU side gets substantially faster; nothing here has been timed on
a device with it, so no number is claimed):

- **Full speed:** 2D and light 3D games.
- **90-100%:** mid-weight titles, with occasional dips.
- **40-75%:** heavy titles, with audio crackle and stutter when new shaders compile.

Default resolution is 1x native. Higher resolution costs memory, and the device has
3 GB.

## Build it yourself

Needs a Mac with Xcode and XcodeGen.

```sh
bash scripts/fetch-azahar.sh      # pinned Azahar source into vendor/
bash scripts/build-core.sh        # iOS 14 arm64 core
xcodegen generate
xcodebuild -project AzaharIPad.xcodeproj -scheme AzaharIPad \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

CI builds and signs the IPA on every push to `main`. See `docs/azahar.md` for the
core's provenance and licence details, and `.github/workflows/build.yml` for the
exact build settings (deployment target 14.0, arm64 only, no chained fixups).

## Credits

Built by us.
This is a hobby project:
built with an AI assistant,
tested by one person on one iPad 8th gen.
It comes with no guarantees.
