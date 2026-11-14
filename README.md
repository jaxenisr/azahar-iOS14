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
| iOS 14-safe build pipeline (section 7 gates in CI) | **green**: builds, ad-hoc signs and verifies the IPA |
| Pinned Azahar core compiled for iOS 14 arm64 and statically linked | **green**: app and core both minos 14.0, arm64 only, no chained fixups |
| Core smoke test (`retro_init` / `retro_get_system_info` on device) | wired, **not yet run on the iPad** |
| Import `.3ds` / `.cci`, tile with real title and icon | implemented, **not yet exercised on device** |
| Launch, on-screen + MFi controls, save state, quit | **not yet** |

The core is deliberately proven on the device before the emulation loop is added:
the previous attempt on this iPad died 0.36 s into launch, before any UI, and the
cheapest way to avoid repeating that is a build that boots first.

The IPA is attached to the workflow run and carries `package.log`, the verification
gate's own output for that build.

## Build contract

Every item here is mandatory and enforced in CI, not by convention.

- Deployment target **14.0** on the app and on the core.
- `-Xlinker -no_fixup_chains` on the final link (Xcode 13.3+ emits chained fixups
  by default; iOS 14's dyld cannot bind them).
- **arm64 only**; `arm64e` excluded, and the packaging step fails if any binary
  carries another slice.
- No bundled `.dylib` or `.framework`, with one exception: for targets below iOS 15
  the toolchain embeds Apple's Swift-concurrency back-deployment library at
  `Frameworks/libswift_Concurrency.dylib`. It is allowed only at that exact path,
  because it is arm64 with a minimum OS far below 14.0 and so cannot raise the
  launch floor; any other dylib or framework fails the build.
- Ad-hoc signing last (`codesign --force --sign -`), after packaging, verified with
  `--deep --strict` so nested code is covered.
- `scripts/verify-binaries.sh` fails the build unless every Mach-O shows
  minos <= 14.0 (`otool -l`), no `LC_DYLD_CHAINED_FIXUPS` (`otool -l` and
  `dyld_info`), and an arm64-only slice (`lipo`).

Minimum OS values are never edited to make an install succeed. If a binary needs
a newer OS, that is a build problem.

## How it is built

CI runs on `macos-15` with **two toolchains, deliberately**:

- **the core is built with Xcode 26**, because Azahar's sources use `std::format`
  and the iOS 18 SDK's libc++ routes its floating-point path through `std::to_chars`,
  which Apple marks unavailable below iOS 16.3. Xcode 26's libc++ does not take that
  path, and this is exactly how Azahar's own iOS job builds the same code at
  deployment target 14.0.
- **the app is built and linked with Xcode 16**, whose published deployment-target
  range covers iOS 14. The final image is therefore produced by the conservative
  toolchain.

The core is compiled with Azahar's own iOS flags at 14.0, then merged into a single
static archive, because Azahar's build only produces a shared core and iOS cannot
load dylibs. The app icon is drawn by `scripts/make-icon.py` rather than stored, so
the tree stays text-only.

Locally, on a Mac:

```sh
bash scripts/fetch-azahar.sh     # pinned tag into vendor/ (git-ignored)
bash scripts/build-core.sh       # iOS 14 arm64 core -> vendor-out/libazahar_core.a
python3 scripts/make-icon.py App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
brew install xcodegen
xcodegen generate
xcodebuild -project AzaharIPad.xcodeproj -scheme AzaharIPad \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

With a `RELEASE_PAT` repository secret the IPA is also attached to a tagged release
published under the repository owner's account; without it nothing is published and
the artifact on the workflow run is the way to get the build.

## Using it on the device

ROMs go in the app's `Documents/ROMs` folder - drop them in through the Files app
(`UIFileSharingEnabled` is on) or use the import button. Files are copied into the
app container on import.

**System files are required.** No game boots without 3DS system files (shared
font/sysdata and a NAND image); the core stops with `ErrorSystemFiles` before its
first frame. Import them into the app's `Documents/Azahar` directory (the core's user
directory). This is a boot prerequisite, not a feature.

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
scripts/        fetch upstream, build the core, draw the icon, package and verify
docs/           upstream provenance, licence and source findings
project.yml     XcodeGen definition (the Xcode project is generated, not committed)
.github/        the macOS build/verify/release workflow
```

`vendor/`, `vendor-out/` and the generated icon are build inputs/outputs, never
committed.

## Branches and releases

`main` holds working code. Milestone steps land on a feature branch and are merged
by pull request. Releases are tagged and published from the repository owner's
account, with the IPA attached.
