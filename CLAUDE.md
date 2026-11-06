# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

DISKTEST is a disk-performance benchmark for the **Sprinter** (ZX Spectrum-compatible, Z84C15/Z80) running the **DSS** DOS. It is a single Z80 assembly program (`disktest.asm` plus small includes) assembled with **sjasmplus** into `DISKTEST.EXE`. Related sources live next to this repo: `../../Estex-DSS` (DSS), `../../sprinter_bios` (BIOS), `../../sprinter_ai_doc/manual` (architecture notes — AI-written, verify against the sources when they disagree).

## Build

```sh
sjasmplus --lst=disktest.lst --lstlab disktest.asm
```

- Output is written by the `savebin` directive at the end of `disktest.asm` → `DISKTEST.EXE` in the repo root. The `.exe` is committed; rebuild and commit it alongside source changes.
- `make.bat` is the Windows equivalent. `make_image.bat` (Windows only; needs OSFMount and `%SPRINTER_EMULATOR%`) copies `image/dss_image.img` to `build/disktest.img`, puts `DISKTEST.EXE` in `X:\DISKTEST\`, and copies the image to the ZXMAK2 emulator. `build/` and `*.lst` are git-ignored.
- `make test` runs assembled Z80 code under the host interpreter (`tests/run.js`). Hardware/emulator acceptance is still needed for WAIT timing, real IRQs and SRAM. The `ASSERT EXEend <= IM2_DEFAULT` at the end of `disktest.asm` guards the memory layout below.

## Current benchmark changes (0.8)

- See `README.md` for modes and verification limits. `/R 1|3|5` defaults to 3;
  `series.asm` performs one validating warmup, alternates paired implementations,
  sorts 32-bit elapsed samples. `compact.asm` prints median/minimum/maximum
  KiB/s in one row per size, with paired metrics side by side; `/V` prints
  detailed time and speed lines. Only Esc cancels; other keys are ignored.
- `/M` pairs file reads with FAT-mapped BIOS reads (`fatmap.asm`); `/C` runs ATA
  from SRAM. Default mode includes both. `verify.asm` checks the full file
  pattern or CRC32 of the full raw pass, outside measured intervals.
- `ata_core.asm` is included in DRAM and with DISP 0200h in SRAM. `cache.asm`
  probes, backs up, installs/verifies and restores the current SRAM range.
  The default IM2 target is now `DefaultHandler`, not a direct JP 0038h.
- Creation uses exclusive `Creat_N`; `FileOwned` and `FileOpen` are separate
  flags (handle zero is valid). Pattern generation is outside accumulated CTC write intervals;
  close/reopen flushes metadata. Write returns success through CF; never use
  its DE as a byte count. Check the completed 32-bit length through Move_FP
  (B=1, zero offset, result HL:IX) outside the timed writes. Never delete before creation. On FILE_EXISTS only, try DISKT000.$$$ through
  DISKT999.$$$; cleanup and FAT mapping use the successfully created name.
- Map pages use WIN1; buffers remain in WIN3. Raw BIOS/ATA start at PartStart;
  mapped BIOS reads the file's exact cluster chain. Invalid maps are skipped.
- ATA recovery drains DRQ before DSS. A permanently busy/non-quiescent device
  causes a red-border halt after SRAM/timer cleanup; it cannot safely return
  to DOS. MULTIPLE is restored and verified, including count zero.
- `/D` (`TEST_SRAM_IO`) runs SRAM code -> a 512-byte SRAM receive ring at
  3E00h. Default ATA series rotate DRAM/DRAM, SRAM/DRAM, SRAM/SRAM. `PeerNow=2`
  selects the third implementation; compact `SS` reports its median and `/V`
  its full range. Every untimed sector is hashed before the ring is reused.
- SRAM kernel and ring backups live in distinct DSS pages, with WIN1 restored
  after copying. `CacheDeinit` restores the ring first, then the kernel; both
  paths also work in fatal recovery without DSS calls.
- `ATA_FULL_UNROLL` is an optional build define; normal EXE retains 16×INI.

## Architecture

- `disktest.asm` — EXE header, entry, argument parser, file-system tests, result printing, strings. Includes:
  - `dss_equ.asm` — DSS syscall numbers (`Dss.*`), `FileMode.*`.
  - `spr_equ.asm` — CMOS/RTC port addresses.
  - `bios_equ.asm` — `ToBIOS` (RST 8), `Bios.DrvRead`, DSS driver gate (`ToDssDrv` RST 0x18, `DssDrv.*`), CTC ports.
  - `timer.asm` — CTC/IM2 millisecond timer (`TimerInit/Deinit/Calibrate/Start/Read`), `CMOSWait`.
  - `biosread.asm` — raw sector read test through BIOS (`BiosTestPrepare`, `TestBiosRead`).
  - `atatest.asm` — direct IDE-port stand, no BIOS: IDENTIFY, then the five block sizes with `READ SECTORS` and again with `READ MULTIPLE` (`AtaTests`, `TestAtaRead`). Port protocol copied from the BIOS: channel via `out (#BC)` (`#21`/`#01`), LBA28 registers (devices without LBA, IDENTIFY word 49 bit 9, are skipped), status polling with BSY masking the other bits, 512 × `INI` from `#0050` with B as counter. ERR counts only after a command (`AtaWaitDone`/`AtaWaitDrq`), not in `AtaWaitReady` before one. Device-control register (nIEN) is never touched.
  - `muldiv.asm` — `div32` (HLDE/BC → DE, remainder HL; needs HL < BC), `Mul16x16` (HL×DE → HLDE), `div512`.
  - `PRNUM.ASM` — `PRNUM`/`PRNUM0` number-to-text.
- **EXE format**: `DEVICE ZXSPECTRUM128`, `org 0x80EA`; `EXEhead` is the 22-byte DSS EXE header (+16 load, +18 start, +20 SP), `EntryExec` the entry point. On entry `(ix-3)` is the handle of the running EXE file, which is closed immediately; `hl` (after `pop`) points to the command line.
- **Syscalls**: DSS — function in `C`, `rst 0x10`; BIOS — function in `C`, `rst 0x08`; DSS drive driver gate — `A` = drive (0 = A:), `C` = function, `rst 0x18`. **Carry set = error** everywhere. Strings are zero-terminated and printed with `Dss.PChars`.
- **Memory layout (window 2 = the program's only page)**: code/data from `0x8100`, must end below `0xBBBB`; `0xBBBB` holds `JP DefaultHandler` (target of every non-CTC IM2 vector → DSS's IM1 handler keeps scanning the keyboard); `0xBC00..0xBD00` is the 257-byte IM2 table (`I = 0xBC`); SP starts at `0xBFFF`. The I/O `Buffer` is `0xC000` — a page obtained with `Dss.GetMem` and mapped into window 3 with `Dss.SetWin3` at startup (a `#8100` EXE gets window 2 only; window 3 otherwise holds DSS's shared page). BIOS requires the stack outside window 3 and the buffer not to cross `0xFFFF`.
- **Timer**: CTC channel 3 (timer mode, prescaler 256, TC 27 ≈ 1 kHz at 7 MHz) raises IM2 interrupts counted in `Ticks`; the table/handlers stay mapped during DSS and BIOS calls, so no ticks are lost during disk I/O. `TimerCalibrate` measures `TicksPerSec` against one RTC second (`CMOSWait`), so the actual CTC clock (turbo or not) does not matter; if fewer than 100 ticks arrive it falls back to RTC seconds (`TimerMode = 1`). `TimerDeinit` (from `Exit`) stops the channel and restores IM1/`I`. Channel 0 belongs to the DSS mouse driver — never touch it. Drivers that transfer with interrupts disabled (the DSS floppy driver) lose ticks, so `TimerStart` also records RTC seconds and `PrintResult` switches to them (printing `(RTC)`) when the RTC shows more than ticks + 1 s.
- **Keyboard polling** inside timed loops goes through `PollKey` (one `Dss.ScanKey` per 32 KiB transferred, `KeyCount` reset before each test) so the file and BIOS tests carry the same, negligible overhead.
- **Units**: `FileBlocks` is the test length in **512-byte blocks** (default `0x1000` = 2 MiB); `BiosSectors` is the same clamped to the partition size.
- **Self-modifying code**: `FileReadPass` patches the immediate of `ld de,...` via `.buferSize: equ $-2` to set the read-block size. Keep that `ld de` instruction directly before the label.
- Test routines return CF=1 with `A` = 0 canceled (any key, polled via `Dss.ScanKey`), 1 disk error, 2 message already printed; `SomeErrors` dispatches on that.
- Comments are mixed English/Russian; keep the existing style when editing.
