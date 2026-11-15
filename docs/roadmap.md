# Roadmap

What is not in the app yet, in the order it is worth building. Each entry says
what the work is and what it depends on; nothing here is a promise of a date.

## 1. Region override

The core already takes the option (`citra_region_value`: Auto, Japan, USA,
Europe, Australia, China, Korea, Taiwan); the frontend does not set it. The work
is a picker on the Emulation page and per title, plus passing the value at load
with the rest of the options.

Dependency: none. It is the smallest remaining piece of real value, because a
title that refuses to boot outside its region is a title that cannot be played at
all.

## 2. New 3DS mode and the texture filter

Both are core options, and both are only worth exposing if the pinned core
listens to them. The rule from the design pass still holds: a row appears when
the core honours it, and says "Unavailable for now — " with the reason when it
does not. A picker that changes nothing is worse than no picker.

Dependency: reading the pinned core's option list, not guessing it.

## 3. Cheats

The core exposes memory reads and writes; a cheat list is a file per title, a
parser for the two common formats, and a toggle per cheat. The risk is not the
UI, it is that a bad write corrupts a save, so it needs an explicit confirm and a
copy of the save before the first write.

Dependency: nothing upstream, but it is the first feature that can destroy user
data.

## 4. Texture packs

A folder per title id, loaded at boot. The core does the work; the frontend has to
find the folder, name the title id, and say what was loaded. Judged by eye on the
device, not by a number.

Dependency: `Textures/` layout documented in the core's own source.

## 5. Camera and amiibo

Camera: the core asks for an image; iOS gives one through an AVCaptureSession,
which needs its own usage string and a graceful refusal on a device with no
camera. Amiibo: reads an NFC tag, and on iOS that is CoreNFC with a per-scan
prompt.

Dependency: permissions, and a device to judge. Neither can be verified in CI
beyond compiling.

## 6. Artic Base

Streaming content from a PC instead of copying it to the iPad. This is a protocol
between the core's Artic Base client and a server on the other machine, so the
work is a small network client plus a pairing UI, and the risk is that it becomes
a second way to load a game that drifts from the first.

Dependency: a server to talk to, which means it cannot be finished here.

## 7. A CPU JIT, if the OS ever allows one

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
