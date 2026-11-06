# DISKTEST 0.8.1

Read-performance comparisons for Sprinter/DSS. Build with `make build` (sjasmplus).
`make test` executes the assembled Z80 instructions with mocked DSS, BIOS, ATA,
SRAM and RTC interfaces. Node.js is needed only for these host tests.

```
DISKTEST.EXE C: /S 2M /R 3
DISKTEST.EXE C: /M /R 5
DISKTEST.EXE C: /A
DISKTEST.EXE C: /C
```

- `/S 512K|1M|2M|4M|8M`: amount to read; default 2 MiB.
- `/R 1|3|5`: measured reads after one untimed warmup; default 3. Reports median,
  minimum and maximum speed. The default compact table puts paired results
  on one line per block size: `FILE 512B median [min..max] | BIOS ...`.
  Values are KiB/s; `*` means coarse RTC timing, `-----` means unavailable time.
  `/V` retains detailed elapsed times and separate median/minimum/maximum lines.
  For three-way ATA comparisons, `SS` is a third median-speed column; `/V` also
  shows its complete range. No extra result rows are required.
- `/F`: file test only, including a write measurement. Generation of the pattern
  is excluded; write I/O intervals are accumulated using CTC. If CTC timing is
  unavailable or loses ticks, write speed is omitted.
- `/M`: file reads paired with BIOS reads of the same file sectors.
- `/B`: BIOS reads from the start of the partition.
- `/A`: direct ATA READ SECTORS and READ MULTIPLE in DRAM.
- `/C`: the same ATA core in SRAM CACHE, with its destination buffer in DRAM.
- `/D`: ATA code in SRAM CACHE and a 512-byte receive ring in SRAM at 3E00h.
  READ SECTORS and READ MULTIPLE retain the same 1/4/8/16/32-sector commands.
  Each sector reuses the ring; command size is not the size of resident data.
  Warmup hashes each sector before it is overwritten; measured passes do not.
  The ring is distinct from the kernel at 0200h and is saved/restored separately.
- `/V`: verbose output; default is compact, sized for an 80x32 screen.
- `/H`, `/?`: help. The last mode switch wins.

Esc cancels preparation, verification and measured passes at the next keyboard
poll (once per 32 KiB). Other keys are consumed and ignored. Device waits still
finish or time out before cancellation, so exit does not interrupt an ATA exchange.

Default execution includes all modes. With SRAM and both backup pages available,
ATA rotates three implementations on each measured pass: DRAM code/DRAM buffer,
SRAM code/DRAM buffer, SRAM code/SRAM ring. Each implementation gets /R samples
and its own untimed verification. Otherwise the available implementations run.
In each file/BIOS or DRAM/SRAM pair,
measured order alternates AB, BA, AB (and BA, AB for five samples). BIOS raw
reads remain a separate reference. The five request sizes are 512 B, 2, 4, 8
and 16 KiB. Mapped BIOS requests also split at cluster boundaries, like DSS.

The temporary file is created exclusively with `Creat_N`, filled with a
reproducible logical-sector pattern, closed, and reopened read-only. A name
collision selects an unused name DISKT000.$$$..DISKT999.$$$ without overwriting
or deleting any existing file. Creation retries only DSS FILE_EXISTS (#07). Cleanup
removes only the file successfully created by this invocation. After writing, a zero-offset Move_FP from the current position checks the
32-bit written length outside the timed intervals. Write success is determined
by CF; DE returned by Write is ignored. An unexpected written length, unaligned
reads and premature EOF fail the test.

Every file and mapped-BIOS warmup checks every byte against the pattern. Raw
BIOS/ATA warmups compute CRC32 over every byte and compare against the first
raw warmup. That first pass explicitly reports that it establishes a reference,
not independent verification. CRC equality is a corruption check, not proof
of byte identity. No checksum or pattern scan runs in measured passes. Warmups explicitly say
`checking full data`; raw verification uses a 1 KiB CRC32 table and prints a
progress dot for each 128 KiB on the current line in compact mode. A dot is untimed verification activity, not a
performance sample. Large verified runs can still take appreciable time on Z80.

FAT12/16/32 mapping uses `F_First`, the partition BPB and the FAT chain. It
honors the active FAT32 and handles fragmented files, FAT12 entries crossing a
sector, and map page transitions. Four DSS pages hold up to 16384 cluster LBAs
(64 KiB); WIN1 is restored after each mapped pass. The exact expected chain
length and EOC are checked, rejecting cycles, reserved/bad clusters, truncation
and overlong chains. Invalid metadata or allocation failure explicitly skips
the pair. No FAT metadata is written by the mapper.

CTC channel 3 is calibrated against RTC. RTC synchronization has a bounded
watchdog. Unavailable time or zero elapsed time produces no speed. RTC-derived
results are marked coarse, including when lost interrupts force RTC fallback.

SRAM starts at 0200h in the current SRAM bank; ROM_RG is unchanged. The code
probes independence from normal WIN0, saves the occupied range, verifies the
copy and restores it at exit. Kernel and ring backups each use a separate
DSS page mapped temporarily in WIN1; the previous WIN1 mapping is restored. The IM2 default bridge disables CACHE for the DSS
interrupt handler; the CTC handler, stack and parameters remain in WIN2. DSS
calls occur with CACHE off. Nested DSS interrupts keep CACHE disabled until
the outer handler returns. ATA waits use ten RTC second transitions, with a
separate finite watchdog if RTC stops. BSY masks the other status bits; DF and
ERR fail commands, and an erroneous DRQ block is drained. MULTIPLE restoration
includes disabled mode (word 59 = 0100h), followed by IDENTIFY verification.

If an ATA controller cannot be brought idle even after bounded recovery, the
program restores SRAM, stops its timer and halts with a red border. Reset is
required in that exceptional case: returning to DOS with an active exchange
would be unsafe. The temporary file can remain after such a halt.

The default transfer loop retains 16×INI. To build the separate full-unroll
experiment, use `sjasmplus -DATA_FULL_UNROLL disktest.asm`; this changes both
DRAM and SRAM bodies together. Rebuild normally before distributing the normal
EXE. BIOS and ACEX are not modified.

## Verification limits and hardware run

Host tests exercise real assembled instructions but mock the hardware. They do
not reproduce ACEX WAIT timing, electrical SRAM behavior, ATA interrupt timing
or DSS's actual interrupt handler. Do not infer hardware speedups from them.

On hardware, run the default suite with `/R 5` with and without turbo, keeping
BIOS/DSS/ACEX and the card unchanged. Require all data checks to pass; record
medians and ranges. Exercise keyboard cancellation during both ATA modes and
verify ordinary DSS commands after exit. Repeat with the full-unroll EXE as a
separate experiment. Hardware/emulator timing acceptance remains to be done.

`tests/Z80core.js` is Molly Howell's MIT-licensed interpreter, copied from the
adjacent ZXFDISK test suite; its license is in `tests/LICENSE.Z80core`.

## Plan coverage after code review

The software portions of the plan are implemented: exclusive file ownership,
actual file length checks and short-write rejection, sector patterns and full
untimed verification, bounded RTC calibration, repeat/median/range reporting,
alternating paired order, FAT12/16/32 mapping, shared DRAM/SRAM ATA code,
error draining and MULTIPLE restoration, and an optional full-unroll build.

Review fixed nested-IRQ CACHE restoration, LBA28/32-bit overflow checks,
reserved FAT cluster acceptance, active-FAT address overflow, absolute
partition-end overflow, invalid SysTime handling, and shared RTC provenance
between paired implementations. It also restored the missing write benchmark.

Two scope distinctions remain: raw disk data is checked by full-stream CRC32
rather than byte-for-byte against an independent stored image; the first raw
pass establishes that reference. The 64KiB map is allocated as four pages even
for small files. These are documented implementation choices.

Hardware acceptance remains open: actual DSS/BIOS/ACEX interrupts, SRAM byte
restoration after cancellation/error, turbo/non-turbo measurements, and measured
performance of the full-unroll experiment. Host models and a successful build
cannot close those plan items. No ROM or ACEX changes are included.

Creation/write failures report the exact stage (create, write, close, reopen)
and the DSS error code. A written-length mismatch reports the current file position and expected
32-bit length separately; it never interprets DE returned by Write as a count. This avoids conflating an exclusive-name conflict, full
media, a handle error, and a failed data-length check as a generic disk panic.

Map skips report their stage instead of labeling the disk FAT invalid:
1 = file information/size, 2 = BPB/volume geometry, 3 = map allocation/mapping,
4 = cluster chain. A skipped pair does not establish disk corruption; the
ordinary file and raw-read modes can still run.

The SRAM receive variant removes DRAM writes for bulk PIO data, but it is not
a completely DRAM-free benchmark: parameters, stack, callbacks outside timed
transfer, and CTC handler remain in WIN2. Reusing a 512-byte receive ring adds
pointer reset/control overhead per sector. The same ATA core source is used
for all implementations; BIOS/ACEX are unchanged. A real-machine run is still
required to establish the performance of SRAM-to-SRAM transfers.

## 0.8.1 hardware hang fix

WIN1 (4000h..7FFFh) is selected through port A2h, not 82h (WIN0).
SRAM kernel/ring backup and FAT-map paging now use the named WIN1_PORT
constant, matching Estex-DSS SP2000.inc SLOT1 and API/SetWin.asm.
The incorrect restore could replace the system WIN0 mapping immediately
after the raw BIOS results, before ATA identification. The host model now
keeps WIN0/WIN1 selectors independent and checks WIN0 on DSS calls; backup
page writes cover every allocated host page rather than only the first four.
A regression verifies both selectors and complete SRAM restoration.

The separate map-stage 01 message means directory lookup or file-size
validation failed before FAT paging. This fix does not claim to diagnose
that earlier message from a photograph. Real-hardware confirmation of the
hang fix remains pending.
