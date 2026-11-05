# Cartridge validation sweep — 2026-11-05

Record of a listening-and-watching sweep run on a single bitstream. The operator
booted nothing themselves; every cartridge was loaded with
`tools/load_snes_rom.py` and judged by eye and ear on the board's HDMI output.
This file is the durable evidence behind core-log entry 15.

- Core source: `87d3399`
- Bitstream: `build/echoaddr/tinysnes.bin`,
  SHA-256 `445e5c02da7dfd9d7566d2a2e4fe5f1a868915d5aded571efa8dddea8dd72c75`
- Deployed to `/root/cores/console138k/tinysnes-dbg.bin`
- No source was changed during the sweep.

## Results

Verdicts are the operator's words, quoted. "Clean" means the operator reported
no defect; it does not mean an automated comparison was run.

| Cartridge | Size / mapper | Coprocessor | Verdict |
|---|---|---|---|
| Zelda: A Link to the Past | 1 MiB LoROM, SRAM | — | clean |
| Super Mario Kart | 512 KiB HiROM, FastROM, SRAM | DSP-1 | clean |
| F-Zero | 512 KiB LoROM | — | clean |
| Super Metroid | 3 MiB LoROM, SRAM | — | clean |
| Space Invaders | 256 KiB LoROM | — | clean |
| Super Castlevania IV | 1 MiB LoROM | — | clean |
| Chrono Trigger | 4 MiB HiROM, FastROM, SRAM | — | tile gap in the swinging pendulum, otherwise clean |
| Super Mario World | 512 KiB LoROM | — | low-frequency filter artefact in the intro, otherwise clean |
| Donkey Kong Country | 4 MiB HiROM, FastROM | — | tile gap in the shrinking logo, otherwise clean |
| Donkey Kong Country 2 | 4 MiB HiROM, FastROM | — | tile gap in the shrinking logo; low-frequency artefact on title-select drum beats |
| Vortex | 512 KiB LoROM | GSU ($14) | clean |
| Stunt Race FX | 1 MiB LoROM | GSU ($13) | clean |
| Star Fox 2 | 1 MiB LoROM | GSU2 | clean |
| Doom | 2 MiB LoROM | GSU2 | clean |
| Winter Gold | 2 MiB LoROM, PAL | GSU2 | stops at its region lockout screen, as expected |

Star Fox and Yoshi's Island were confirmed on this same bitstream in the
previous cycle and are recorded in core-log entry 14.

Every cartridge booted. None hung, none showed a blank screen, and no boot
produced ROM timeouts. `PAL = 1'b0` in `snestang_top.v` is the reason Winter
Gold stops at its region check: the core cannot present itself as PAL, so the
title refuses to run. That is a design limit, not a fault.

## Defect 1 — tile gap in a scaled or rotated background

Three sightings, two engines:

- Donkey Kong Country: the shrinking logo
- Donkey Kong Country 2: the shrinking logo
- Chrono Trigger: the swinging pendulum

DKC and DKC2 share an engine, so they are one data point seen twice. Chrono
Trigger is the independent sighting and carries the weight.

Mode 7 is ruled out. F-Zero is Mode 7 on every scanline and is clean, so the
Mode 7 matrix path is not the cause. All three affected scenes draw a
transformed background through something else.

Candidates, in the order worth checking:

1. HDMA-driven per-line register writes. All three scenes animate a transform
   that updates once per scanline rather than scrolling a tilemap, so a
   one-line-late or one-line-dropped HDMA transfer would show exactly as a
   seam that moves with the animation.
2. The offset-per-tile / per-tile scroll path.
3. Colour math or mosaic applied to a transformed background.

Not investigated. Nothing was changed.

## Defect 2 — low-frequency artefact

Two titles, both described the same way by the operator:

- Super Mario World: "TINY filter issue with low freq sounds in the intro"
- Donkey Kong Country 2: "filter issue again at title select screen, its low
  drum beats it seems"

Everything else on both titles is clean, so the fault is content-selective: it
needs low pitch and high amplitude together. A kick drum is the loudest, lowest
thing a BRR stream carries.

This is distinct from the pops, which are broadband impulses and appear on every
title regardless of content.

Strongest candidate is the BRR decoder's four filters. Filters 1 and 2 have real
low-frequency response, and a wrong coefficient or a wrong tap history distorts
loud low content most and quiet high content least, which is the observed
pattern. Gaussian interpolation at low pitch is the second candidate but fits
the amplitude dependence less well.

Not investigated. The way to judge it is a reference capture through
`tools/ref_emu.py --core /usr/lib/x86_64-linux-gnu/libretro/bsnes_mercury_accuracy_libretro.so`
on the same passage, comparing the low band sample by sample, not more reading
of `dsp.v`.

## Instrumentation notes — read before quoting any counter

Three separate mistakes were made against the debug bank during this sweep. They
are recorded because each one produced a confident wrong statement, and because
the bank is usable once the traps are known.

**`uptime` is a 32-bit mclk counter that wraps.** At 21.484 MHz it wraps every
199.9 seconds, so after roughly three and a half minutes it is no longer
monotonic and no longer measures time since configuration.

**`GO time` is computed as a percentage of `uptime`, so it is wrong after that
wrap.** `go_time` counts only clocks where the GSU asserts GO, so it takes far
longer than 200 seconds to wrap and does not wrap on the same boundary. Once
`uptime` rolls over, `go_time ÷ uptime` reads above 100 percent. Doom reported
101.6 percent, and the two counters are individually correct; the ratio is not.
The absolute `GO starts`, `SFR` and `PC` readings are unaffected.

**`GSU_GO_CNT` and the debug bank's GSU counters are on different reset
domains.** `main.v` is instantiated with `resetn & ~loading`, so `GO_CNT` clears
on every ROM load. `tinysnes_dbg` is instantiated with `resetn` alone, so its
counters survive a load and accumulate since FPGA configuration. Quoting `GO
starts` next to `stops` as if they described the same span describes nothing;
each number alone is valid.

The earlier claim that the debug counters were broken, made during the sweep and
retracted here, was the third mistake: the counters are sound, the derived
percentage is not.

## Not covered

Deliberately out of scope for this sweep, listed so the next one can pick up:

- Hi-res modes 5 and 6. `PSEUDOHIRES` and `HIRES` exist in `ppu.v` and nothing
  here exercised 512-pixel output. Candidates: Rendering Ranger R2, Jurassic
  Park, RPM Racing.
- Interlace. Logic present, never exercised.
- Super Scope, mouse and multitap. `config.v` wires ordinary pad inputs; the
  pointer path is a different decoder. Candidates: Battle Clash, Yoshi's
  Safari, Super Scope 6, Mario Paint, Super Bomberman.
- Unbuilt coprocessors. `config.v` defines `CHIP_DSPn` and `CHIP_GSU` only, so
  SA-1, CX4, S-DD1 and SPC7110 titles (Super Mario RPG, Kirby Super Star,
  Kirby's Dream Land 3, Mega Man X2/X3, Star Ocean, Street Fighter Alpha 2)
  cannot run. Worth one boot to confirm they fail visibly rather than hang.
- PAL operation. Blocked by `PAL = 1'b0`; not testable without a source change.
