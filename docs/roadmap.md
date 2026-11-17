# Roadmap

What is not in the app yet, in the order it is worth building. Each entry says
what the work is and what it depends on; nothing here is a promise of a date.

Every entry below started as a question answered by reading the pinned core's own
source at tag `2127.0-rc3`, never by guessing what it supports.

## Shipped

- **Region** (`citra_region_value`): a menu row on the Emulation page and a
  per-title override, read at load, defaulting to `Automatic`, which is the core's
  own default. A title that refuses to boot outside its region can be played now.
- **Console model** (`citra_is_new_3ds`): New 3DS or the original, read at load.
  The core's default is **New 3DS**, which is what the app had been getting all
  along by never setting the option.
- **Texture filter** (`citra_texture_filter`): None, Bicubic, ScaleForce, MMPX.
  Two values in the core's own option list are deliberately not offered, because
  the pinned core cannot apply them: `Anime4K` falls back to `NoFilter` whenever
  the graphics API is Vulkan (the only API this app presents through on iOS), and
  the parser compares against `"xBRZ freescale"` while the option list advertises
  `"xBRZ"`.

## 1. Cheats

The core exposes memory reads and writes; a cheat list is a file per title, a
parser for the two common formats, and a toggle per cheat. The risk is not the
UI, it is that a bad write corrupts a save, so it needs an explicit confirm and a
copy of the save before the first write.

Dependency: nothing upstream, but it is the first feature that can destroy user
data.

## 2. Texture packs

A folder per title id, loaded at boot. The core does the work (`citra_custom_textures`
is already in its option list); the frontend has to find the folder, name the
title id, say what was loaded, and offer the dump switch that writes the textures
out. The memory cost on a 3 GB device is the real risk, not the plumbing.

Dependency: `Textures/` layout documented in the core's own source.

## 3. Camera and amiibo

Camera: the core asks for an image; iOS gives one through an AVCaptureSession,
which needs its own usage string and a graceful refusal on a device with no
camera. Amiibo: reads an NFC tag, and on iOS that is CoreNFC with a per-scan
prompt.

Dependency: permissions, and a device to judge. Neither can be verified in CI
beyond compiling.

## 4. Artic Base

Streaming content from a PC instead of copying it to the iPad. The core already
dispatches `articbase://<ip>[:<port>]` in `src/core/loader/loader.cpp`, so the work
is a small client-side pairing UI plus the audio/video session, and the risk is
that it becomes a second way to load a game that drifts from the first.

Dependency: a server to talk to, which means it cannot be finished here.

## 5. A CPU JIT, if the OS ever allows one

FastInterp is what runs now, and it is the reason the CPU side is as fast as it
is without an executable-memory entitlement. A JIT needs
`com.apple.security.cs.allow-jit`, which on this install path is not available.
This entry exists so the absence is a documented decision rather than an
oversight.

Dependency: an install method that grants the entitlement. Until then, nothing.

## Out of scope

**Multiplayer.** Local wireless and online play need a second emulated console, a
network stack in the core and a rendezvous service; that is a different project,
not a phase of this one.

**Stereoscopic 3D.** The core has `citra_render_3d` and `citra_factor_3d`, but the
picture here is composed by this app for a flat display, and a phone-style
anaglyph or cardboard mode is not what an iPad in a case is for.
