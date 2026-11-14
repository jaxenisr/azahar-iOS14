# Azahar for iPadOS 14

A native SwiftUI frontend for the Azahar 3DS emulator core, built for an iPad 8th
generation on iPadOS 14.7.1: no JIT, no OS upgrade, ad-hoc signed IPA for
TrollStore.

3DS emulation powered by **Azahar**, licensed **GPLv3+**
(https://github.com/azahar-emu/azahar). The emulation engine is used unmodified
from a pinned release tag; this repository contains only the app and its libretro
frontend. See [docs/azahar.md](docs/azahar.md).

## Status

| Milestone step | State |
|---|---|
| iOS 14-safe build pipeline (section 7 gates in CI) | in place, unverified until the first CI run |
| Pinned Azahar core compiled for iOS 14 arm64 and statically linked | wired, unverified |
| Core smoke test (`retro_init` / `retro_get_system_info` on device) | wired, unverified |
| Import `.3ds` / `.cci` / `.zcci`, tile with real title and icon | implemented |
| Launch, on-screen + MFi controls, save state, quit | **not yet** |

The core is deliberately proven on the device before the emulation loop is added:
the previous attempt on this iPad died 0.36 s into launch, before any UI, and the
cheapest way to avoid repeating that is a build that boots first.

## Build contract

Every item here is mandatory and enforced in CI, not by convention.

- Deployment target **14.0** on the app and on the core.
- `-Xlinker -no_fixup_chains` on the final link (Xcode 13.3+ emits chained fixups
  by default; iOS 14's dyld cannot bind them).
- **arm64 only**; `arm64e` excluded, and the packaging step fails if any binary
  carries another slice.
- No bundled `.dylib` or `.framework`. Swift comes from the OS (iOS 12.2+), so
  nothing is embedded - embedding a runtime is how a newer minimum OS gets in.
- Ad-hoc signing last (`codesign --force --sign -`), after packaging.
- `scripts/verify-binaries.sh` fails the build unless every Mach-O shows
  minos <= 14.0 (`otool -l`), no `LC_DYLD_CHAINED_FIXUPS` (`otool -l` and
  `dyld_info`), and an arm64-only slice (`lipo`).

Minimum OS values are never edited to make an install succeed. If a binary needs
a newer OS, that is a build problem.

## How it is built

CI (`macos-15` runner, **Xcode 16.x**): Xcode 16 is used rather than Xcode 26
because Apple's own Xcode 26 deployment-target range starts at iOS 15. The core is
compiled with Azahar's own iOS flags at 14.0, then merged into a single static
archive, because Azahar's build only produces a shared core and iOS cannot load
dylibs.

Locally, on a Mac:

```sh
bash scripts/fetch-azahar.sh     # pinned tag into vendor/ (git-ignored)
bash scripts/build-core.sh       # iOS 14 arm64 core -> vendor-out/libazahar_core.a
brew install xcodegen
xcodegen generate
xcodebuild -project AzaharIPad.xcodeproj -scheme AzaharIPad \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

The IPA is produced by CI and attached to the workflow run; with a
`RELEASE_PAT` repository secret it is also attached to a tagged release published
under the repository owner's account, and without it nothing is published.

## Using it on the device

ROMs go in the app's `Documents/ROMs` folder - drop them in through the Files app
(`UIFileSharingEnabled` is on) or use the import button. Files are copied into the
app container on import.

**System files are required.** No game boots without 3DS system files
(shared font/sysdata and a NAND image); the core stops with `ErrorSystemFiles`
before its first frame. Import them into the app's `Documents/Azahar` directory
(the core's user directory). This is a boot prerequisite, not a feature.

## Performance, stated plainly

The A12 in an iPad 8th gen is the iPhone XS class of silicon. On iOS the core
forces the CPU JIT **and** the shader JIT off, so the ARM11 runs on FastInterp and
the CPU-side shader engine runs interpreted, with PICA shaders still reaching the
GPU through MoltenVK.

Expect roughly: 2D and light 3D (NSMB2, Mario Kart 7, A Link Between Worlds) at or
near full speed; mid-weight titles (Super Mario 3D Land, Ocarina 3D) mostly
90-100% with dips; heavy titles (USUM/SM, Xenoblade, MH4U, DQ7/8, Hyrule Warriors)
40-75% with audio crackle and shader-compile stutter on first encounter.

The 3 GB of RAM is the harder limit. Defaults are 1x native resolution
(400x240) scaled in the presentation layer, hardware shaders on, New 3DS mode on
(many titles refuse to boot otherwise). Higher internal resolution is opt-in and
costs memory.

None of this is measured on this device yet; it comes from upstream's release
notes and the code paths above.

## Repository layout

```
App/            SwiftUI app and the Objective-C++ libretro bridge
scripts/        fetch upstream, build the core, verify the packaged binaries
docs/           upstream provenance, licence and source findings
project.yml     XcodeGen definition (the Xcode project is generated, not committed)
.github/        the macOS build/verify/release workflow
```

`vendor/` and `vendor-out/` are build inputs, never committed.

## Branches and releases

`main` holds working code. Milestone steps land on a feature branch and are merged
by pull request. Releases are tagged and published from the repository owner's
account, with the IPA attached.
