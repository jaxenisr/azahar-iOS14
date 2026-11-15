# Upstream: Azahar

Azahar is the 3DS emulation engine. It is a dependency, not a fork.

| | |
|---|---|
| Repository | https://github.com/azahar-emu/azahar |
| Pinned tag | `2127.0-rc3` |
| Fetched by | `scripts/fetch-azahar.sh` into `vendor/azahar` (git-ignored) |
| Edited by us | never |
| Licence | GPLv3 or later (`LICENSE` holds the canonical licence text) |

Bumping: change `AZAHAR_TAG` in `scripts/fetch-azahar.sh`, delete `vendor/azahar`,
run the fetch script, rebuild. Save states are stamped with the core version, so a
bump invalidates them - tell the user before bumping.

## Why `2127.0-rc3` and not something older

2127.0 replaces the DynCom interpreter with **FastInterp**, the first interpreter
that is usable on iOS/tvOS where JIT is impossible. Everything before 2127.0 is
either unusably slow on this device or needs JIT.

2127.0 final was not tagged at the time of writing; `-rc3` is the newest tag.

## Licence consequences (read before distributing)

2127.0 changed Azahar from GPLv2+ to **GPLv3+**. Because the core is statically
linked into the app, the IPA is a GPLv3 combined work:

- every release must be accompanied by the complete corresponding source
  (this repository, at the release tag);
- the app's own code must remain GPLv3-compatible;
- upstream copyright headers and the licence text stay exactly as they are.

The README credits Azahar as "3DS emulation powered by Azahar, GPLv3+". Do not
describe it as GPLv2+; that was the pre-2127.0 licence.

Azahar also ships `AI-POLICY.md`, reproduced here as `docs/azahar-ai-policy.md`,
which restricts AI-written contributions **to their repository**. We consume the
code and never submit to it, so the policy does not apply to this project. If an
upstream fix were ever needed, the repository owner would have to author and
submit it personally.

## Facts established by reading the pinned source

These shaped the design; keep them in mind before changing anything.

### Artic Base is already in the core

`src/core/loader/loader.cpp` dispatches on the content *path*:

- `articbase://<ip>[:<port>]` -> `Apploader_Artic` (default port **5543**)
- `articinio://<ip>` / `articinin://<ip>` -> Artic *Setup Tool* mode, which pulls
  console-unique system files (SecureInfo_A, LocalFriendCodeSeed_B, movable.sed,
  OTP) from a real console over the network

`Apploader_Artic` owns `Network::ArticBase::Client`
(`src/network/artic_base/artic_base_client.cpp`), forwards filesystem requests to
the console, and registers the remote save-data / extdata / NCCH / system-save
archives. The libretro entry point is scheme-agnostic - `retro_load_game()`
forwards `info->path` to `Core::System::Load()` - so streaming needs no core
patch, no core option, and no fork. The frontend only has to hand over the
pseudo-path.

Not yet wired into the UI; it is a library-entry decision, not an engine change.

### iOS is forced JIT-less inside the core

`src/citra_libretro/core_settings.cpp`:

- `use_cpu_jit = false` on `IOS` (the option is not even exposed)
- `use_shader_jit = false` on `IOS`
- `use_fastinterp` defaults to enabled

So the ARM11 runs on FastInterp and the CPU-side shader engine runs interpreted.

### Rendering on iOS is Vulkan through MoltenVK

`CMakeLists.txt` links the bundled `MoltenVK.xcframework/ios-arm64/libMoltenVK.a`
and `ENABLE_OPENGL` defaults to off on Apple platforms. The core presents through
`retro_video_refresh_t` with `RETRO_HW_FRAME_BUFFER_VALID` and the libretro Vulkan
HW-render interface, so a frontend must implement that interface (negotiation,
device creation, image supply, presentation).

### Upstream iOS build flags (mirrored in `scripts/build-core.sh`)

```
-DENABLE_LIBRETRO=ON -DIOS=ON -DCMAKE_SYSTEM_NAME=iOS
-DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 -DCMAKE_OSX_ARCHITECTURES=arm64
-DCMAKE_C_FLAGS=-DIOS -DCMAKE_CXX_FLAGS=-DIOS
-DCITRA_USE_PRECOMPILED_HEADERS=OFF -DENABLE_OPT=OFF
-DCMAKE_POSITION_INDEPENDENT_CODE=ON
```

Azahar's own CI builds this on a macOS runner, which is why the *engine* is
treated as solved. What is not solved by that is packaging it into an iOS 14 app.
