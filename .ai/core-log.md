## 1 COMMIT Unreleased 2026-11-04T11:34:06-07:00

#### Coming From:

Unreleased 2cfeb96

#### Purpose:

Roll the active log over at the user's request and hand off the live project state in one entry.

#### Outcome:

The previous log, entries 1 to 93 from 2026-10-30 to 2026-11-04, was archived unchanged as `.ai/archived_logs/core-log_2026-11-04T113406-0700.tar.gz`, SHA-256 `56f32b88a4187030b3352abf21a65bc2e5fb7101ffe8bd4330acefb97b02fe78`, holding `core-log.md` at its root, and the active log was cleared; per `.ai/core.md` that archive is not to be consulted without the user's approval. TinySNES is nand2mario's SNESTang SNES core ported to the open flow for the Tang Console 138K, built by `tools/build_tinysnes.sh` with yosys and slang, nextpnr-himbaechel and the apicula fork at `/run/media/vash/GIT/apicula-mathieufro`. The current build is a synthesis run followed by place and route with `TINYSNES_CLK_FIRST=dbg.clk TINYSNES_SEED=2 TINYSNES_ALLOW_HOLD=1 TINYSNES_ALLOW_UNMEASURED_CLOCKS=1` and a `TINYSNES_BUILD_DIR`; seed 2 has been the board-tested seed throughout the SuperFX work, and the flow's step `1b`, `tools/clock_edge_check.py`, refuses netlists that mix true negedge flops with LUT-inverted clocks (TCL-020). The board runs `build/rc39/tinysnes.bin`, SHA-256 `4c86ac26038165e2cd203cb7dfa26a741f2a8c8d8a547654f1da012fc9b6e582`, placed as `/root/cores/console138k/tinysnes-dbg.bin` by `tools/tang_deploy.py` in two-wire mode on `/dev/ttyACM0`; the user's script `/home/vash/Desktop/reboot_in 2_wire.py` reboots the Tang into two-wire mode, after which it runs its default core and the debug core must be redeployed. Cartridges are unzipped from `/run/media/vash/MiSTer_Data/games/SNES/` into `/tmp` and sent with `tools/load_snes_rom.py`. The build carries the debug endpoint `fpga/snes/src/tinysnes_dbg.v`, driven by `tools/tinysnes_dbg.py`, whose `status`, `knob`, `trace` and `analyze` commands report GSU state, override the GSU's ROM wait and check traced ROM latches against the cartridge; its counters are not cleared on a cartridge load, its ROM timeout counter is meaningless during GSU bursts because `sd_wait_age` in `snestang_top.v` resets only when no read is pending, and its peek commands read zero. WRAM and BSRAM are block RAM, and the cartridge ROM is SDRAM reached through a request and acknowledge handshake that returns a word in a variable six to ten master clocks. The GSU's ROM wait in `GSU.v` is 3 when `CLS` is 0 and 9 when `CLS` or `TURBO` is set, a blind count with no ready signal; on the board 2 and 3 suffice at 10.7 MHz, while at 21.4 MHz instruction-cache fills read stale bytes at 6 and are correct at 8. Confirmed on the board are the plain cartridges Space Invaders, Zelda, Super Mario Kart, Donkey Kong Country, Super Castlevania IV and Chrono Trigger, and the SuperFX titles Star Fox at full intro speed, Yoshi's Island with its intro figures and title water correct, Stunt Race FX, Dirt Trax FX, Vortex, Star Fox 2 and Doom; Winter Gold is PAL and stops at its region check. Input is a Wii Classic Controller through `wii_pad.sv` on USB-A port 2, sound reaches HDMI and a Pmod I2S2 through `i2s_out.sv`, and saves work within a session but are lost on power cycle because nothing writes BSRAM to the card. The simulation bench is `tools/sim/run_gsu_sim.sh` with `tools/sim/gsu_tb.sv`, which takes cartridge latency options, `+romcyc`, `+golog`, `+ramlog`, `+mmiolog` and frame dumps and can substitute MiSTer's reference GSU built by `tools/sim/gsu_ref/build_ref.sh`; `tools/ref_emu.py` gives snes9x reference frames, `tools/sim/run_board_sim.sh` runs the board-level bench, and the capture card is `/dev/video0`, read with `ffmpeg -f v4l2 -input_format mjpeg -video_size 1280x720`, with its recovery tools in `tools/capture/`. No engineering file changed in this cycle. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was not changed, confirmed the archive's `core-log.md` is byte-identical to the committed log it replaces, and validated this entry as entry 1 with six sections, a one-sentence Purpose, prose, `N/A` Status values and a count of one against the 100-entry limit.

#### Next Steps:

Replace the GSU's fixed ROM wait with a ready signal from the cartridge port so each read waits for its own word, which should let the 21.4 MHz SuperFX games run faster than at 9 and may cure Yoshi's Island's lagging coin sound; propose the design to the user first. Then investigate the audio cuts and missing channels in Yoshi's Island and the small pops heard in every game, SuperFX or not, which belong to the general audio path. Smaller open items are Yoshi's Island's remaining minor glitches, a check that its map and Kamek's room now draw full width, its black text box, the GSU stall once seen at `09:FEFE`, clearing the debug counters on cartridge load and fixing `sd_wait_age`. Larger parked items are the on-screen menu through the unused `textdisp` in `iosys_bl616.v`, save persistence to the card, the ExHiROM mode decode in `smc_parser.v`, and coprocessors with no source in the tree such as S-DD1, SA-1, SPC7110 and CX4.

#### Files Modified:

None.

#### Status:

- Build: N/A
- Deployment: N/A
- User Test: N/A

---

## 2 COMMIT Unreleased 2026-11-04T12:36:23-07:00

#### Coming From:

Unreleased 101160a

#### Purpose:

Replace the GSU's blind ROM wait count with a ready signal from the cartridge port so each GSU ROM read waits for its own SDRAM word.

#### Outcome:

`GSU.v` gains a `ROM_RDY` input, plumbed through `GSUMap.v` and `main.v` from `rom_ready` in `snestang_top.v`; its LOAD, FETCH and CACHE states latch `ROM_DI` only once a minimum count, now 1 at both speeds and still overridable by the debug knob, has run out and `ROM_RDY` is high, and the 3-or-9 `CLS`/`TURBO` split is gone. The work found that the controller's arrival toggle `cpu_dout_tog` in `sdram_cl2_2ch.v` was never driven, so it now toggles on the `cycle[4]` edge that registers a CPU-port read, the only change to that controller. Because the controller acknowledges at `cycle[1]` but registers the word at `cycle[4]`, the port can post the next address before the previous word's arrival is seen, so `rom_ready` counts posted reads not yet arrived in `rom_rd_out` and is high only when that count is zero, `rom_addr_sd` equals `rom_addr` and no load is running; nothing times this out, so a lost toggle would hold the GSU in a wait state. Two further defects were fixed: `GSU.v` drove `PBR:R15` onto the ROM bus in `ROMST_CACHE_DONE`, costing a wasted SDRAM read between cache bytes, and now keeps the fill address there, and `sd_wait_age` now restarts on every post so the debug ROM timeout counter times single reads during bursts. `tools/sim/gsu_tb.sv` models `ROM_RDY` from a stable address for the configured latency, with `+nordy` for the old behaviour; the other benches and reference-GSU wrappers gained the port, `tools/sim/run_board_sim.sh` gained `--arg`, `tools/sim/test_loader.sv` holds 4 MiB so Yoshi's Island loads, and `tools/tinysnes_dbg.py` describes the new knob default. In 300M-cycle bench runs at latency 4 against the old counts of 3 and 9, GSU busy time per job fell about 10% in both Star Fox and Yoshi's Island, Star Fox completing 1723 jobs to 1648 in the same 843 frames and Yoshi's Island ending on an identical frame; the board-level bench with the real controller ran Star Fox with all 1024 traced ROM latches and cache opcodes matching the cartridge and no ROM timeouts, while Yoshi's Island never started its GSU there with or without this change, a bench limitation. The seed-2 build `build/rdy1` passed timing with dbg.clk at 30.6 MHz against 21.5, fclk 255.3 against 64.5, hclk 131.3 against 74.25 and the GSU cache clock 172.3 against 65, passed the clock-edge check with no driver conflicts, and `build/rdy1/tinysnes.bin`, SHA-256 `5f205939fabf59470f17ea94e2b6384c0dc25290ec3ef402f65dc9caf0a15191`, was deployed as `/root/cores/console138k/tinysnes-dbg.bin`. The user passed Star Fox, Yoshi's Island with perfect graphics, Stunt Race FX, Dirt Trax FX and Super Mario Kart on the board, the debug endpoint showing no ROM timeouts and no GSU stuck waiting; the remaining faults are audio only, with small pops in every game that grow with sound complexity, Dirt Trax FX's simple intro music sounding clean, and Yoshi's Island's chimes and coins sounding like a buzzing "brrrt", its coin sounds lagging and some channels missing. The core-syntax audit re-read `.ai/core-syntax.md`, confirmed `.ai/core.md` was not changed, and validated this entry as entry 2 with six sections in order, a one-sentence Purpose, prose Outcome and Next Steps, permitted Status values, no self-referencing hash and a count of two against the 100-entry limit.

#### Next Steps:

Investigate the general audio path, starting with the pops that grow with sound complexity and Yoshi's Island's buzzing chimes and coins, lagging coin sounds and missing channels, which persist after this change and so do not come from the GSU's ROM timing. Optional GSU follow-ups are reusing the 16-bit word already fetched when the next ROM byte shares it, which needs the user's approval, and finding why Yoshi's Island never starts its GSU in the board-level bench. Smaller open items are Yoshi's Island's minor glitches, its black text box, the GSU stall once seen at `09:FEFE` and clearing the debug counters on cartridge load. Larger parked items are the on-screen menu, save persistence to the card, the ExHiROM decode in `smc_parser.v` and the missing coprocessors.

#### Files Modified:

- fpga/snes/src/chip/GSU/GSU.v
- fpga/snes/src/chip/GSU/GSUMap.v
- fpga/snes/src/main.v
- fpga/snes/src/sdram_cl2_2ch.v
- fpga/snes/src/snestang_top.v
- tools/sim/gsu_ref/gsu_port_wrap.v
- tools/sim/gsu_ref/gsu_ref_wrap.v
- tools/sim/gsu_tb.sv
- tools/sim/maptype_tb.sv
- tools/sim/run_board_sim.sh
- tools/sim/test_loader.sv
- tools/tests/main_hde_tb.sv
- tools/tinysnes_dbg.py

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 3 COMMIT Unreleased 2026-11-04T16:47:52-07:00

#### Coming From:

Unreleased c2ce59d

#### Purpose:

Fix the audio faults left after entry 2, namely Earthworm Jim 2's broken sound and the pops on both the Pmod I2S2 and HDMI audio outputs.

#### Outcome:

Three fixes were made. In `dsp.v` a BRR block with its end bit set now raises `BRR_END` instead of `ENDX_BUF`, as MiSTer's `DSP.vhd` does, because the next `VS_VOLR` step rebuilds `ENDX_BUF` from `ENDX | BRR_END` and the old write was lost, so games polling ENDX such as Earthworm Jim 2 never saw a voice end; the fix was found with new `tools/sim/gsu_tb.sv` options `+wav`, `+dsplog`, `+apulog`, `+apufrom`, `+aputo` and `+aramdump`, which also applies the ROM type at cycle 1, and on the board the seed-2 build `build/endx1` restored Earthworm Jim 2's intro accordion and vocals, which had sounded horrendous, and the user passed it and Super Mario Kart. The Pmod pops came from `i2s_out.sv` assuming the S-DSP's nominal 32,222 samples/s while the per-frame pause that holds 60 Hz HDMI makes about 32,127/s in bursts, so its bang-bang rate trim underran the FIFO about 87 times a second; the module now has a 64-entry FIFO, a PI servo on the fill level with `KP_SHIFT` 19, `KI_SHIFT` 4 and the integrator clamped to 0.75 percent, the nominal ratio `RATIO_NUM`/`RATIO_DEN` 99804511/130483747, a `running` gate so it waits for half full before reading, and `dbg_overwritten` and `dbg_underrun` counter ports not yet wired to the debug bus; the new bench `tools/sim/run_i2s_out.sh` with `tools/sim/i2s_out_tb.sv` and `tools/sim/raw2wav.py` drives it with bursty production, and `tools/tests/i2s_tb.sv` was updated for the extra latency and checks underruns. HDMI audio clicked about 20 times a second because `snes2hdmi.v` read its 16-entry FIFO with a fixed `clk_audio` of 32,004 Hz, 74.25 MHz divided by 2320, against the same 32,127/s production, dropping about 120 samples a second; the divider was replaced by the new module `hdmi_audio_clock.v`, a 32-bit phase accumulator on hclk whose step is steered by the FIFO's read-side level, a new `rlevel` port on `dual_clk_fifo.v`, through a PI servo around 8 entries with `KP_SHIFT` 8, `KI_SHIFT` 4 and the integrator clamped to about 0.9 percent, with the error and step registered so the servo stays off the critical path, so every sample is sent exactly once and the HDMI core's ACR packet, which measures `clk_audio` to produce CTS, tells the sink the real rate while the infoframe still says 32 kHz; this was chosen with the user over a 48 kHz interpolating resampler as the lighter, bit-exact option, accepting that a strict sink might reject the 0.4 percent offset. The new bench `tools/sim/run_hdmi_audio.sh` with `tools/sim/hdmi_audio_tb.sv` passed over 3 s at 0 and plus or minus 300 ppm with no drops, repeats, overflows or underruns, the level between 5 and 9 and the rate between 32,120 and 32,130 Hz, and `hdmi_audio_clock.v` was added to `tools/build_tinysnes.sh` and `tools/sim/run_board_sim.sh`. The seed-2 build `build/i2s1` with the Pmod fix passed timing and the user called the Pmod basically perfect, with a rare tiny pop judged acceptable. The first HDMI build `build/hda1`, without the registered error and step, passed but cut hclk to 99.8 MHz with the servo on the critical path, and on the board its capture-card recording fell from 157 clicks over 12 sigma in 8 s to 3 and the user reported HDMI and Pmod both sounding perfect; the final seed-2 build `build/hda2` passed timing with dbg.clk at 28.4 MHz against 21.5, fclk 229.0 against 64.5, hclk 131.8 against 74.25 with the HDMI TMDS encoder again the critical path, and the GSU cache clock 289.8 against 65, passed the clock-edge check, used 43,599 LUT4 or 31 percent and 212 of 340 BSRAM, and `build/hda2/tinysnes.bin`, SHA-256 `7cf1ecbbd2bf4caddd14c99974b220f316f0a9a2bb9da576150a5bfe0492a1b1`, was deployed as `/root/cores/console138k/tinysnes-dbg.bin`, after which an 8 s capture of RetroRegen's 440 Hz tone through the Guermok USB capture card showed 1 click over 12 sigma, 60 Hz at minus 118 dBFS and no 30 Hz sidebands, and the user accepted it. The remaining large events, about one every 4 s and also present before the fix, look like the capture card slipping one 32 kHz sample against its own clock, but that is not proven. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, confirmed `.ai/core.md` was not changed, inspected the `.ai/` diff as this entry alone, and validated it as entry 3 with six sections in order, a one-sentence Purpose, prose Outcome and Next Steps, permitted Status values, no self-referencing hash and a count of three against the 100-entry limit.

#### Next Steps:

Check the remaining audio faults, Yoshi's Island's buzzing chimes and coins, lagging coin sounds and missing channels, and Star Fox's sound cutouts, against these fixes, then confirm both servos under PAL, where the frame pause and production rate differ and nothing has been tested. Wiring the `i2s_out.sv` and HDMI FIFO underrun counters to the debug bus would prove whether the residual capture-card events come from the core, and the `i2s_out.sv` header still describes the old 41,947 Hz rate and no FIFO. If a TV rejects the off-nominal HDMI audio rate, the fallback is a 48 kHz interpolating resampler on hclk. Earlier open items carry over, including Yoshi's Island's minor glitches and black text box, the GSU stall once seen at `09:FEFE`, clearing debug counters on cartridge load, the on-screen menu, save persistence, the ExHiROM decode in `smc_parser.v` and the missing coprocessors.

#### Files Modified:

- fpga/snes/src/dsp.v
- fpga/snes/src/dual_clk_fifo.v
- fpga/snes/src/hdmi_audio_clock.v
- fpga/snes/src/i2s_out.sv
- fpga/snes/src/snes2hdmi.v
- tools/build_tinysnes.sh
- tools/sim/gsu_tb.sv
- tools/sim/hdmi_audio_tb.sv
- tools/sim/i2s_out_tb.sv
- tools/sim/raw2wav.py
- tools/sim/run_board_sim.sh
- tools/sim/run_hdmi_audio.sh
- tools/sim/run_i2s_out.sh
- tools/tests/i2s_tb.sv

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 4 COMMIT Unreleased 2026-11-04T17:22:43-07:00

#### Coming From:

Unreleased 46a280a

#### Purpose:

Play-test the audio fixes of entry 3 across the usual test cartridges and the top-rated SNES games to find what still fails.

#### Outcome:

No file changed and nothing was rebuilt; every test ran on the entry-3 build `build/hda2/tinysnes.bin`, SHA-256 `7cf1ecbbd2bf4caddd14c99974b220f316f0a9a2bb9da576150a5bfe0492a1b1`, already deployed as `/root/cores/console138k/tinysnes-dbg.bin`, with each cartridge sent by `tools/load_snes_rom.py` from `/run/media/vash/MiSTer_Data/games/SNES/`, from `/run/media/vash/GIT/TinySNES/build/rom/` or, for Super Mario World, from `/home/vash/Desktop/Super Mario World (USA).zip`. The user passed every cartridge for video and for the pops, which are gone everywhere. Star Fox and Earthworm Jim 2 sounded and looked perfect, the user saying Earthworm Jim 2 is indistinguishable from a real SNES. Yoshi's Island's buzzing chimes and coins are fixed, but its missing sound channel is more noticeable than before. Zelda: A Link to the Past is perfect except that the bush-throw sound and the item-get fanfare are completely silent, which the user judged the same fault as Yoshi's Island. Super Mario Kart sounds perfect but still shows its known vertical stripe at the left edge of the screen. F-Zero seemed perfect, though the user does not know the game and suspects it too is missing channels. Since Metacritic has almost no scores for original SNES games, the top-ten list came from GameRankings averages as cited by focusfuturemagazine.com, and of it Super Metroid, Chrono Trigger (4 MB), Final Fantasy III (US release of VI), Super Mario World both alone and on Super Mario All-Stars plus Super Mario World (2.5 MB), Donkey Kong Country 2 and the original Donkey Kong Country all passed as perfect; Star Ocean, which needs the absent S-DD1, and Fire Emblem: Thracia 776 are not on the MiSTer drive and were not tried. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, confirmed `.ai/core.md` was not changed, inspected the `.ai/` diff as this entry alone, and validated it as entry 4 with six sections in order, a one-sentence Purpose, prose Outcome and Next Steps, permitted Status values, no self-referencing hash and a count of four against the 100-entry limit.

#### Next Steps:

Find why some sound effects never play, as heard in Zelda's bush throw and item-get fanfare and in Yoshi's Island's missing channel, likely a shared S-DSP or SPC700 fault such as key-on, key-off, ENDX, echo-buffer or voice-steal handling made more visible by the entry-3 ENDX change; reproduce it in the `tools/sim/gsu_tb.sv` bench with `+dsplog` and `+wav` against a reference and then propose a fix. Super Mario Kart's left-edge stripe, the PAL behaviour of both audio servos, wiring the audio FIFO counters to the debug bus, the stale `i2s_out.sv` header and the open items carried in entry 3 remain.

#### Files Modified:

None.

#### Status:

- Build: N/A
- Deployment: N/A
- User Test: PASS

---

## 5 COMMIT Unreleased 2026-11-04T18:14:09-07:00

#### Coming From:

Unreleased 74329ee

#### Purpose:

Find and fix the sound effects and instrument that never play in Yoshi's Island and Zelda: A Link to the Past.

#### Outcome:

The fault is in the SPC700 microcode inherited unchanged from upstream SNESTang, not in the entry-3 ENDX change: a 260-million-clock Yoshi's Island simulation with and without that change produced bit-identical audio and DSP logs, and both lacked the sound snes9x (`tools/ref_emu.py`) plays at 1.3 to 1.8 seconds. The DSP log showed the driver keying on voice 6, whose registers it never wrote, and the new `+spctrace` and `+spcbus` options in `tools/sim/gsu_tb.sv` showed why: in `LSR !a` the read-modify-write step shifted the temporary register T, left over from the previous read-modify-write, instead of the byte just read, because its busCtrl field was `10000` where `ASL !a`, the direct-page forms and MiSTer's `MCode.vhd` all select the data bus with `00000`. `ROL !a` and `ROR !a` carried the same error. Those three rows were corrected in `fpga/snes/src/spc700/mcode.vh`, rows 355, 611 and 867, which is the table the build compiles, and in its source `mcode.txt`. In simulation the 1.3-second sound returned at RMS 1223 against snes9x's 1224, the music's first chord keyed two voices instead of one, and the 6-to-12-second envelope correlation with snes9x rose from 0.90 to 0.98. The build `build/spc1/tinysnes.bin`, seed 2 with `TINYSNES_CLK_FIRST=dbg.clk`, SHA-256 `27ff58dfe50c758e44acbf8d35d4b7a828fdfe7228e09912b981340b9fc18562`, was deployed by `tools/tang_deploy.py` as `/root/cores/console138k/tinysnes-dbg.bin`, and the user reported every audio issue resolved. The build needs `APICULA_FORK=/run/media/vash/GIT/apicula-mathieufro` when run from a worktree outside `/run/media/vash/GIT`, since the script's default path is relative to the checkout and otherwise falls back to the stock apycula, whose pack fails. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, confirmed `.ai/core.md` was not changed, inspected the `.ai/` diff as this entry alone, and validated it as entry 5 with six sections in order, a one-sentence Purpose, prose Outcome and Next Steps, permitted Status values, no self-referencing hash and a count of five against the 100-entry limit.

#### Next Steps:

Super Mario Kart's left-edge stripe, the PAL behaviour of both audio servos, wiring the audio FIFO counters to the debug bus, the stale `i2s_out.sv` header and the open items carried in entry 3 remain.

#### Files Modified:

- fpga/snes/src/spc700/mcode.vh
- fpga/snes/src/spc700/mcode.txt
- tools/sim/gsu_tb.sv

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 6 COMMIT Unreleased 2026-11-04T18:49:02-07:00

#### Coming From:

Unreleased c1a189f

#### Purpose:

Find and fix the sound effects in Star Fox, such as the training-mode ring chime and possibly the lasers, that played seconds late.

#### Outcome:

A lockstep differential test ran this SPC700 against MiSTer's (srg320's VHDL from the MiSTer SNES core, converted with GHDL using `--latches`) on identical random 64 KB programs, comparing registers at every opcode fetch, every memory write and the cycle count of every instruction, and it found eight defects in the inherited core. In `fpga/snes/src/spc700/mcode.vh`, the table the build compiles, `8E POP PSW` had its last two rows swapped so the stack was never read into PSW, `0F BRK` pushed PSW to the program-counter address without decrementing SP, `6E DBNZ d,r` updated N and Z, `0E TSET1 !a` and `4E TCLR1 !a` took N and Z from an AND instead of the compare A minus memory, `CA MOV1 m.b,C` combined the carry bit with SP instead of the byte read, `5A CMPW YA,d` took five cycles instead of four and `8A EOR1 C,m.b` four instead of five. The TSET1 and TCLR1 rows now use a new ALU control 34 in `mcode.v` that compares without touching C, `spc700.v` now selects the carry-to-bit mask with T on the source bus and moves the CMPW 16-bit zero combine to state 3, and `muldiv.v` now performs DIV with the chip's nine-step rotate-and-subtract, which gives the hardware's results when Y is at least twice X, where the old restoring divider saturated A to FF; those results match bsnes. The changed rows were mirrored in `mcode.txt`. After the fixes 2,300 random programs, 300 of them with random RDY stalls, ran without a register, write or cycle mismatch, and a four-second Star Fox simulation showed its sound driver executing DBNZ, EOR1, TSET1, TCLR1 and DIV. The build `build/spc2/tinysnes.bin`, seed 2 with `TINYSNES_CLK_FIRST=dbg.clk`, SHA-256 `e2e09c4c4ed2313620a57e98534ad8c6d4e30fc672ca91207d79dd4f60a384f4`, met timing, was deployed by `tools/tang_deploy.py` as `/root/cores/console138k/tinysnes-dbg.bin` and redeployed after a board reboot, and the user reported Star Fox's sound as perfect. The differential bench lived only in `/tmp/mspc` and was not committed. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, confirmed `.ai/core.md` was not changed, inspected the `.ai/` diff as this entry alone, and validated it as entry 6 with six sections in order, a one-sentence Purpose, prose Outcome and Next Steps, permitted Status values, no self-referencing hash and a count of six against the 100-entry limit.

#### Next Steps:

Committing the SPC700 differential bench as a reproducible tool alongside `tools/sim/gsu_ref`, checking F-Zero for missing channels, Super Mario Kart's left-edge stripe, the PAL behaviour of both audio servos, wiring the audio FIFO counters to the debug bus, the stale `i2s_out.sv` header and the open items carried in entry 3 remain.

#### Files Modified:

- fpga/snes/src/spc700/mcode.vh
- fpga/snes/src/spc700/mcode.txt
- fpga/snes/src/spc700/mcode.v
- fpga/snes/src/spc700/spc700.v
- fpga/snes/src/spc700/muldiv.v

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 7 COMMIT Unreleased 2026-11-04T19:42:58-07:00

#### Coming From:

Unreleased 35423b3

#### Purpose:

Find and fix the fixed vertical stripe near Super Mario Kart's left screen edge that cut a column out of sprites passing through it.

#### Outcome:

The stripe reproduced in the Verilator simulation of `fpga/snes/src/main.v` with ROM type 129 as each kart of the title intro entered from the left, and the snes9x reference showed none, so the fault lay in the core rather than the game. In the sprite range engine of `fpga/snes/src/ppu.v`, the test that ends a sprite's tile fetch once a tile reaches the right screen edge, `(TILE_X + 8) >= 256`, was evaluated at 32 bits because of the unsized literal, so when a sprite started one to seven pixels left of the screen its first tile's end exceeded 511 instead of wrapping to the left edge, the fetch stopped after that tile and the following eight pixels of the sprite were never drawn. MiSTer's VHDL evaluates the same sum in nine bits, where it wraps and the fetch continues, and the line was inherited unchanged from upstream SNESTang. The fix computes the tile's end in a nine-bit `TILE_X_END` and tests its bit 8. In simulation of frames 320 to 720 the karts entered whole, and the only pixels that changed were the previously missing columns in the frames where a kart sat one to seven pixels past the left edge. The build `build/ppu1/tinysnes.bin`, seed 2 with `TINYSNES_CLK_FIRST=dbg.clk`, SHA-256 `a8b4cac1e85f5d015e94049f187d489b86751d94cede675f59d8f9b6110f392b`, met timing, was deployed by `tools/tang_deploy.py` as `/root/cores/console138k/tinysnes-dbg.bin`, and the user reported the stripe gone. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, confirmed `.ai/core.md` was not changed, inspected the `.ai/` diff as this entry alone, and validated it as entry 7 with six sections in order, a one-sentence Purpose, prose Outcome and Next Steps, permitted Status values, no self-referencing hash and a count of seven against the 100-entry limit.

#### Next Steps:

Committing the SPC700 differential bench as a reproducible tool alongside `tools/sim/gsu_ref`, checking F-Zero for missing channels, the PAL behaviour of both audio servos, wiring the audio FIFO counters to the debug bus, the stale `i2s_out.sv` header and the open items carried in entry 3 remain.

#### Files Modified:

- fpga/snes/src/ppu.v

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 8 COMMIT Unreleased 2026-11-04T21:01:22-07:00

#### Coming From:

Unreleased 293d5a3

#### Purpose:

Begin the emulator UI by drawing TinyTang's TinyDesk overlay over the SNES picture and toggling it with a tap of the Wii Classic HOME button, as TinyNES and TinyGBC do.

#### Outcome:

The new `fpga/snes/src/desk_layer.v` draws TinyTang's 80 by 45 character desk over the whole 1280 by 720 picture in 16 by 16 pixel cells, each an 8 by 8 glyph from the new `fpga/snes/src/desk_font.hex` doubled in both directions, with its cell store written on the pixel clock from a toggle handshake so it has a single clock, a four-pixel lead so its output lines up with the rest of the picture in `snes2hdmi.v`, and a shown flag that switches only at the start of row 720 so a frame is never split. `fpga/snes/src/iosys/iosys_bl616.v` accepts TinyTang's desk frames, 0x13 for the cell cursor, 0x14 for five-byte cells and 0x15 for the desk enable, shows the desk only while both 0x15 and the 0x08 overlay toggle are set, holds the game's pads idle while it is shown, and now sends the joypad report in TinyTang's pad word as TinyNES does, with LB raised only for a tap of HOME, which `fpga/snes/src/wii_pad.sv` now outputs. The first build of this design failed the 74.25 MHz `hclk` gate at 71.99 MHz, and seeds 3, 4 and 5 reached only 71.96, 74.05 and 71.44 MHz, because the critical path was the HDMI encoder's serial `q_m` chain into its disparity accumulator, made sixteen levels deep by the new placement; `fpga/snes/hdmi/tmds_channel.sv` was therefore replaced by TinyNES's version, also used by TinyGBC, which builds `q_m` as a prefix tree and registers it, delaying the TMDS stream by one pixel clock, and a disposable bench found it identical to the old encoder delayed by one clock over 200,000 random cycles in every mode on all three channels, while a version of the bench without the delay reported mismatches. `tools/tests/desk_tb.sv` with `tools/tests/run_desk_tb.sh`, the extended `tools/tests/bootscreen_tb.sv` and `tools/sim/dbg_link_tb.sv` pass, and `tools/build_tinysnes.sh` and `tools/sim/run_board_sim.sh` include the new layer. The build `build/desk2/tinysnes.bin`, seed 2 with `TINYSNES_CLK_FIRST=dbg.clk`, SHA-256 `1300fc64d686fdfe677a2cb3726c5e8324c796742986a7f0f20321a3a41195e9`, met every clock with `hclk` at 105.3 MHz, was deployed by `tools/tang_deploy.py` as `/root/cores/console138k/tinysnes-dbg.bin` alongside TinyTang firmware `7c44fb3-dirty.1491160`, which lets a pad tap open the desk while its layer is off and records the overlay state a loader's 0x08 frame sets, and with Super Mario Kart loaded the user reported the desk opening and closing on HOME, including the first tap after a load, F12 still working, game input blocked while the desk is shown and the picture unchanged. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, confirmed `.ai/core.md` was not changed, inspected the `.ai/` diff as this entry alone, and validated it as entry 8 with six sections in order, a one-sentence Purpose, prose Outcome and Next Steps, permitted Status values, no self-referencing hash and a count of eight against the 100-entry limit.

#### Next Steps:

Building out the rest of the UI on the desk, such as the ROM browser and core menu TinyNES and TinyGBC provide, comes next; PAL support is deferred by the user, and committing the SPC700 differential bench, wiring the audio FIFO counters to the debug bus, the stale `i2s_out.sv` header and the open items carried in entry 3 remain.

#### Files Modified:

- fpga/snes/hdmi/tmds_channel.sv
- fpga/snes/src/desk_font.hex
- fpga/snes/src/desk_layer.v
- fpga/snes/src/iosys/iosys_bl616.v
- fpga/snes/src/snes2hdmi.v
- fpga/snes/src/snestang_top.v
- fpga/snes/src/wii_pad.sv
- tools/build_tinysnes.sh
- tools/sim/dbg_link_tb.sv
- tools/sim/run_board_sim.sh
- tools/tests/bootscreen_tb.sv
- tools/tests/desk_tb.sv
- tools/tests/run_bootscreen_tb.sh
- tools/tests/run_desk_tb.sh

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 9 COMMIT Unreleased 2026-11-04T22:29:11-07:00

#### Coming From:

Unreleased 768f6ff

#### Purpose:

Hand off the proposed design for SNES battery saves to the Tang's SD card, written on a HOME plus Minus exit as TinyNES and TinyGBC do, before any of it is implemented.

#### Outcome:

No engineering file changed in either repository. Since entry 8 the UI work moved to TinyTang at `/run/media/vash/GIT/TinyTang`, whose `main` at `83d6058` is pushed and in sync with `origin`: a TinySNES desk app in `ports/bl616/tinysnes_app.cpp` loads `/root/cores/console138k/tinysnes.bin` and streams a cartridge through `ports/bl616/tang_snes_load.c` while the core shows colour bars, and the Wii Classic format-0 controller fix is in, with the board running firmware SHA-256 prefix `af4ea73d` and the user confirming the controller works after leaving a game; that repository's `third_party/tinydesk` carries uncommitted changes that are not this project's and must stay out of its commits. The user set ZIP cartridges aside and chose battery saves, noting that SRAM already survives a game restart until the core is reloaded, and specified TinyNES and TinyGBC's behaviour: no Stop button, the player saves in the game, and holding HOME with Minus stores SRAM to the card and returns to the desktop, as `pad_quit()` does in TinyGBC's `firmware/apps/gb_bench/main.cpp` at lines 935 to 940. Because TinySNES has no CPU, the proposal puts the work on the BL616. In the core, `iosys_bl616.v` would set pad-word bit `0x8000` while HOME and SELECT, which is Minus, are both held, which already clears the HOME-tap detection; it would gain frame 0x18 to write a block of BSRAM from a 24-bit address and frame 0x19 to read up to 251 bytes back in a reply carrying a CRC, both refused unless `rom_loading` holds the core in reset, using a new TX state since `send_state` is four bits and `send_idx` only seven, and keeping 0x19 replies within the BL616's 256-byte frame payload; `snestang_top.v` would mux the 128 KiB BSRAM port near lines 1987 to 1994 to iosys while `loading`, adding no block RAM to a design already at 340 of 340. In TinyTang, `tang_pad.h` would gain `TANG_PAD_EXIT`, `tang_fpga_link.h` and `fpga_frames.h` the two frame types, and `tang_snes_load.c` would size the save from the header, battery when the low nibble of byte 0x16 is 2, 5, 6, 9 or 0xA and 1 KiB shifted by byte 0x18, using the expansion RAM byte at 0x7FBD or 0xFFBD for SuperFX cartridges whose byte 0x18 is zero and capping at 128 KiB, then restore `/sd/root/saves/snes/<stem>.sav` with verified 0x18 blocks after the ROM drains and before reset is released, doing nothing when no file exists because a fresh configuration zeroes BSRAM. `tinysnes_app.cpp` would drop the Stop button and `stop_task`, keep `launch_task` polling `tang_fpga_joypad` about every 50 ms, and on the exit bit raise the load hold, read SRAM out, write a `.part` file, read it back and rename it over the `.sav` as the AE350 save path in `tang_fpga_uart.c` does, record the overlay and load the desktop core; a core-load counter in `tdsh_tang_flash.c`'s `tang_core_load` would let the task end without saving if another core replaced TinySNES. The plan was presented and the user asked for this handoff before approving it. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, confirmed `.ai/core.md` was not changed, inspected the `.ai/` diff as this entry alone, and validated it as entry 9 with six sections in order, a one-sentence Purpose, prose Outcome and Next Steps, `N/A` Status values, no self-referencing hash and a count of nine against the 100-entry limit.

#### Next Steps:

Get the user's approval of the battery-save plan, then implement the core half with `tools/sim/dbg_link_tb.sv` covering the exit bit and both frames, build and deploy the bitstream as `tinysnes.bin`, implement the firmware half with host tests in `tools/tests/tb_snes_load.c` and TinyTang's `tools/tests/run_all.sh` gate, flash the firmware, and have the user save in Zelda, exit with HOME plus Minus, confirm the `.sav` in `/root/saves/snes` and confirm it loads on relaunch; the SuperFX save size in 0x7FBD for Yoshi's Island, believed to be 32 KiB, is unverified, and `smc_parser.v` maps 64 KiB for every GSU cartridge. Zip cartridges and the items carried in entry 8 remain.

#### Files Modified:

None.

#### Status:

- Build: N/A
- Deployment: N/A
- User Test: N/A

---

## 10 COMMIT Unreleased 2026-11-05T08:59:45-07:00

#### Coming From:

Unreleased 7e366b8

#### Purpose:

Do the tooling and hygiene cycle left open by entries 3 through 8 -- commit the SPC700 differential bench that entry 6 recorded as lost, wire the audio FIFO fault counters to the debug bus, correct the stale `i2s_out.sv` header, and record F-Zero -- and stop leaving scratch files in a tmpfs.

#### Outcome:

Four items, one of which found a defect older than the bench that caught it. The SPC700 differential bench is committed as a tool under `tools/sim/spc_ref` and `tools/sim/spc_diff_tb.sv`: entry 6 built it in `/tmp/mspc` and it did not survive, so this is a reconstruction rather than a copy, and its reference is regenerated from MiSTer SNES at pinned `901a172c` by `tools/sim/spc_ref/build_ref.sh`, which fetches `rtl/SPC700` and converts it with GHDL `--synth --latches` because `AddrGen.vhd`'s `NewAL`/`NewAH` and `ALU.vhd`'s `tIntR` are inferred latches that GHDL refuses by default; unlike the GSU no file uses both clock edges, so no split pass is needed. MiSTer's SPC700 exposes no debug port, so `tools/sim/spc_ref/export_regs.py` appends seven outputs driven from the wires GHDL already emits, and it asserts that each source wire exists and that the ports landed inside the port list, because the first version of that transformation inserted them after the port list and the second assumed the last `);` in the file was the header -- both would have produced a bench comparing constant zeros while appearing to pass. The bench runs both cores lockstep on identical memory and compares PC, A, X, Y, SP, PSW and the write count at every instruction boundary, sampled the clock after the retire pulse rather than on it, because on the edge itself the two cores disagree about when an instruction commits: on the first random program that showed as a two-boundary difference in A while every other register agreed, and the next boundary agreed on A as well. It stops at three findings that are not defects to chase: `DIV` overflow, where this core implements the chip's nine-step rotate-and-subtract that entry 6 matched against bsnes and MiSTer's reference is a restoring divider that saturates the quotient to `FF`; `STP` (`0xEF`), which ends a random program and after which MiSTer's keeps pulsing its last-cycle signal so it would otherwise read as 129 instructions of drift; and one real defect. That defect is in `fpga/snes/src/spc700/spc700.v` and predates this bench: the core runs the power-on interrupt sequence twice, pushing `00->FF->FE->FD` and reading `$FFFE`, then pushing again `FD->FC->FB->FA` and reading `$FFFE` a second time before the first cartridge instruction executes, where MiSTer's pushes three bytes and leaves SP at `FD`. A probe inside the bench shows it at clock granularity, STATES 1 to 7 for the first sequence and STATES 8 to 15 for the second, so a program that reads its own stack can later diverge in A or in flags through no fault of its own. It is recorded as an **open defect**, not fixed: the reset path is a microarchitectural change outside this cycle and needs its own approval, build and hardware check. The bench measures the resulting SP offset at the first instruction boundary, holds SP to that constant for the rest of the run, excludes the 256-byte stack page from the final image compare while counting and naming it, and reports a run where the defect fired as `DIVERGE`, never `PASS`, with the sweep counting those separately so a green summary cannot absorb them. Two further bugs were found in the bench itself and fixed rather than worked around: its mismatch printout labelled the concatenated fields wrongly, so it read a PSW difference as `a` and an SP difference as `x`, which is why the first reading of the reset fault pointed at A; and its minimum-sample guard counted a legitimate `STP` halt after a dozen instructions as a failure, which manufactured 442 phantom failures in one sweep. Sensitivity is proven rather than asserted: reverting the `LSR !a` bus-control fix of entry 5 makes the bench fail at instruction 1, and so does dropping the `POP PSW` stack read of entry 6. The registration sweep over 2300 independent random programs, with 12 run in parallel, gives 1873 passed, 0 failed, 417 skipped as too short to be evidence and 10 divergent through the reset defect, comparing 8,953,137 instructions; no failure is left unclassified. Second, the audio FIFO counters are on the debug bus. `i2s_out.sv` already counted samples taken, samples lost to a full FIFO and resampler underruns, and `tools/tinysnes_dbg.py` reported them as not yet wired; `snes2hdmi.v` now reduces an overflow and an underrun to a toggle each, so the underrun -- which happens on the pixel clock -- crosses into the bank's mclk domain as one bit rather than a counter, and `tinysnes_dbg.v` counts those edges through a three-flop synchroniser and carries `i2s_out`'s own 16-bit counters through unchanged, at `0x050` for HDMI overflow, `0x054` for HDMI underrun, `0x058` for Pmod `{lost, taken}` and `0x05c` for Pmod underruns. The taken count free-runs and saturates at 65535 in about twenty seconds, so it is a delta and the header says so; the board read 65535 there as predicted. Third, the `i2s_out.sv` header described a 32,180 Hz input, a 41,947 Hz output, a 1.517x upsample and "no FIFO is needed", all of which the code had outgrown, and a second stale block was found only after the first rewrite claimed the file was corrected: the clock-generation comment still said `sys_clk` and a nominal 21.477 MHz, where the counters run on `mclk` at the PLL's 21.505376 MHz, SCLK is `mclk/8` and 64 SCLKs make LRCK, so Fs is 42,003 Hz rather than 41,947 and the real input is about 32,127 a second because `snes2hdmi` halts the machine once per frame. Fourth, `/tmp` on this machine is tmpfs, so capture frames written there are resident RAM; a prior cycle left 9.1 GB of it, which was cleared at the user's direction, and the tools that wrote there now write under the gitignored `build/` on the working drive -- `tools/onewire.sh` and `tools/capture/reboot_trial.sh` to `build/capture`, `tools/audio_probe.py` and the three bench runners to `build/tmp` -- with their `TINYSNES_CAPTURE_DIR` overrides intact. F-Zero (USA) is 524,288 bytes at `bf16c3c867c58e2ab061c70de9295b6930d63f29f81cc986f5ecae03e0ad18d2`, header at `0x7FC0`, map mode `$20`, cart type `$02`, rom size `$09`, and the user confirmed its picture and audio on the board on 2026-11-05, closing the check entry 4 opened when they suspected it of missing channels. The build is `build/acnt/tinysnes.bin`, SHA-256 `6dd9e8afa89987df484f711ae508fcccd75cd46ce24c55737a94454396484610`, seed 2 with `TINYSNES_CLK_FIRST=dbg.clk`, passing every gate at dbg.clk 29.536 against 21.505 MHz, fclk 219.298 against 64.516, hclk 100.573 against 74.250 and the GSU cache clock 225.785 against 65.000, with zero `Driver-driver conflict` lines, the clock-edge check passing, and the new counters confirmed present in the netlist as `dbg.audio_ovf` with its full adder chain rather than assumed -- a build that passes every gate and a simulation that agrees with itself are both compatible with a bitstream that cannot work, which is entry 85's lesson. It was deployed by `tools/tang_deploy.py` to `/root/cores/console138k/tinysnes-dbg.bin` with all three verification points matching over 5,222,380 bytes, reporting `tangload: core loaded`. Two edits landed after that build and both are comment-only, the `i2s_out.sv` clock comment above and a note in `tinysnes_dbg.v` about the taken count saturating; the four registers themselves are in the deployed bitstream by direct evidence, since the board returned `0x050` 51, `0x054` 0, `0x058` 65535 and `0x05c` 0. With F-Zero running at 170,571 frames the Pmod reads zero overflow and zero underrun and the HDMI overflow is flat at 51 since power-up, so the servos are locked and that count is a priming transient rather than an ongoing fault, which is the reading entry 3 could not take because the counters were unreachable. `README.md` was corrected where the merged log had invalidated it: the tested-cartridge list gained Chrono Trigger and F-Zero, the SuperFX entry now names all seven running GSU titles instead of claiming Vortex and Yoshi's Island untested, the TinyDesk overlay has a status entry, the bench section documents the SPC700 differential bench, and the Known gaps entry that still called the OSD the last untested surface now points at the tied-off overlay behind TinyDesk. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was not changed, confirmed entries 1 to 9 were not rewritten, and validated this entry as entry 10 with six sections in order, a one-sentence Purpose, prose Outcome and Next Steps, eligible Files Modified paths with no generated artifacts, permitted Status values, no self-referencing hash and a count of ten against the 100-entry limit.

#### Next Steps:

The SPC700 reset defect is the first thing the next cycle should take, and it is now bounded rather than speculative: `tools/sim/run_spc_diff.sh --seed 153` reproduces it in seconds, the probe that showed it is described above, and a fix must make the power-on sequence push three bytes once instead of twice while keeping `IsResetInterrupt` set, after which the bench's whole offset apparatus should be deleted rather than left in place, since `sp_off` becomes zero and the `DIVERGE` class should disappear from the sweep -- if it does not, the fix is incomplete. That is a microarchitectural change to the SPC700 and needs its own approved cycle, a build and a hardware check on a title that leans on its sound driver, and it should not be folded into a hygiene commit. Everything else this cycle opened is closed. Two limits worth carrying: the bench compares at instruction boundaries, so an instruction that takes the wrong number of cycles but reaches the right architected state is invisible to it, and entry 6's cycle-count checks were a separate mechanism that this tool does not replace; and 417 of 2300 random programs stopped at `STP` within a dozen instructions and prove nothing, so a future sweep should be read by its compared-instruction count rather than by how many seeds it ran. The audio counters are now permanent instruments: `tools/tinysnes_dbg.py status` reports them, they should read zero on a healthy build once the priming transient has passed, and a rising Pmod underrun or overwrite count is the first thing to check before suspecting the resampler, since entry 3's four I2S fixes were each measured and should not be reopened on a hunch. Saves to the card remain the largest designed-but-unbuilt item, with entry 9's plan still awaiting approval, and the deferred items carried from entry 8 -- the ExHiROM mode decode in `smc_parser.v` and the coprocessors with no source in the tree -- are unchanged.

#### Files Modified:

- README.md
- fpga/snes/src/i2s_out.sv
- fpga/snes/src/snes2hdmi.v
- fpga/snes/src/snestang_top.v
- fpga/snes/src/tinysnes_dbg.v
- tools/audio_probe.py
- tools/capture/reboot_trial.sh
- tools/onewire.sh
- tools/sim/dbg_link_tb.sv
- tools/sim/run_dbg_link_sim.sh
- tools/sim/run_spc_diff.sh
- tools/sim/spc_diff_tb.sv
- tools/sim/spc_ref/build_ref.sh
- tools/sim/spc_ref/export_regs.py
- tools/tests/probe_tb.sh
- tools/tinysnes_dbg.py

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 11 COMMIT Unreleased 2026-11-05T09:40:54-07:00

#### Coming From:

Unreleased eefebac

#### Purpose:

Fix the SPC700 power-on defect that entry 10 found and recorded as open, so the core pushes the interrupt frame once instead of twice and the bench's offset apparatus can be deleted.

#### Outcome:

The root cause was not the reset path, which is where the symptom appeared, but the microcode ROM's addressing. `mcode.v` reads `MCODE0[{IR, STATE[2:0]}]`, dropping `STATE[3]`, so a state of 8 or more wraps back onto rows 0 to 7 and re-executes the opcode's own microcode instead of stopping. MiSTer's table carries sixteen rows per opcode with the upper eight all `"XX"` and its state control resolves `"XX"` to zero, so state 7 is terminal there; this core's `mcode.vh` carries eight rows and has no such padding, so the sequence kept going. The trigger is a second-order fault and explains why the defect survived every earlier SPC700 test: at power-on `STATE` is 0 and the branch decoder samples `D_IN`, the byte at whatever address the bus holds rather than an instruction, so a value like `$50` (BVC) sets `JumpTaken` before any opcode has been fetched; BRK never reassigns `JumpTaken`, so it survives to BRK's last row, whose state control is `2'b10`, which then branches to state 8. States 8 to 15 re-enter rows 0 to 7 and push PCH, PCL and PSW a second time, shrinking SP to `$FA` where MiSTer leaves `$FD` and reading `$FFFE` twice. It fires on 10 of 2300 random programs because it depends on the byte at `$0000` resembling a taken branch. The fix is four lines in `spc700.v`: after the existing state-control case, `if (STATE[3] && IR != 8'h9E && IR != 8'hCF) NextState = 4'b0000;`. DIV and MUL are excluded because they legitimately use states 8 to 15 and their upper rows already terminate themselves through state control `2'b10`, so they need no forcing; every other opcode now ends at state 7, which reproduces MiSTer's padding exactly and costs at most the one redundant state MiSTer also spends. Verification is the bench entry 10 built, and it reports the fix three ways. The registration sweep over 2300 independent random programs, 12 in parallel, gives 1884 passed, 0 failed, 416 skipped as too short and **0 divergent**, comparing 8,958,332 instructions; zero divergent is the specific result entry 10 recorded as proof the fix was complete, because `DIVERGE` was the class only a run with the defect could reach. Reverting only the four new lines makes the bench fail at instruction 0 with `spfa` against `spfd`, so it detects the original defect as an ordinary `FAIL` rather than a special case. The two microcode mutants entry 10 used as its sensitivity check still fail at instruction 1. Because the offset apparatus existed only to tolerate this defect, it has been deleted rather than left in place, as entry 10's Next Steps committed to: `sp_off`, `known_reset` and the stack-page exclusion are gone, SP is compared directly, the stack page is back inside the full 64 KiB image compare, and the `DIVERGE` class no longer exists in either the bench or `run_spc_diff.sh`; the bench's header records the history so a future reader knows why. The DIV and MUL exclusion was checked rather than assumed: `fill=cf` runs 22,222 instructions clean, and non-overflow DIV is reached by 6 of 60 random seeds for 204 executions, measured with a temporary counter, because the directed `fill=9e` run stops at the overflow case that is already a documented divergence and so proves nothing about the common path. The build is `build/spcfix/tinysnes.bin`, SHA-256 `108c204f22e86d9e31e172dea6b33dce72ac7e8f8037f5096620067020127f3b`, seed 2 with `TINYSNES_CLK_FIRST=dbg.clk`, passing every gate at dbg.clk 28.991 against 21.505 MHz, fclk 217.202 against 64.516, hclk 98.319 against 74.250 and the GSU cache clock 317.561 against 65.000, with zero `Driver-driver conflict` lines and the clock-edge check passing. It was deployed by `tools/tang_deploy.py` with all three verification points matching over 5,225,142 bytes, and the user confirmed F-Zero, Super Mario World 2: Yoshi's Island and Earthworm Jim 2 each sound and look correct on it. The regression benches all pass unchanged: `dbg_link`, `probe_tb`, `i2s_out` at zero underrun and zero overflow, and `hdmi_audio` at zero drops, zero repeats, zero underflows and a rate between 32,120 and 32,130 Hz. Two corrections to entry 10 are recorded rather than quietly fixed. Entry 10 called the Pmod I2S underrun counter a usable health instrument; it is not, because `i2s_out`'s `running` flag is sticky -- it sets when the FIFO first reaches half full and clears only on core reset -- so a cartridge load, which holds the machine in reset while no samples arrive, drains an empty FIFO at the full output rate and saturates the count at 65535 within about 1.5 seconds, after which it can no longer report anything; the HDMI counters are unaffected because that FIFO is reset-per-write and its `clk_audio` servo idles with it. Entry 10 also attributed the saturated count to a transition artefact, which was too loose a reading of the same behaviour. Separately, a real audio fault is open and was found during this cycle's testing, not caused by it: on the Pmod output Zelda: A Link to the Past alternates between what the user describes as split mono and real stereo, while Yoshi's Island and Earthworm Jim 2 are perfect on the same build and the same DAC, and the user reports it on the pre-fix build as well, so it predates this change. What was ruled out with evidence: `i2s_out`'s channel routing, by a new directed probe that decodes the real serial stream against LRCK with a sign-flipping input on both channels and reports 0 left-versus-right mismatches over 840 frames, which the existing `i2s_out_tb` could never see because it dumps only left samples and never decodes the wire; `VS_VOLL` and `VS_VOLR`, the echo buffer addressing and the `STEP 24`/`25` FIR accumulation guard, the `EOUT` masks and `VS_NON`, all of which match MiSTer's `DSP.vhd` at `901a172c`; the echo-register clearing asymmetry, where `EVOLL` clears nothing and `EVOLR` clears four registers, which looked like a defect until MiSTer was read and found to do exactly the same; and two same-named `reg LR` declarations, which are block-local inside named `always` blocks and therefore legal. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was not changed, confirmed entries 1 to 10 were not rewritten, and validated this entry as entry 11 with six sections in order, a one-sentence Purpose, prose Outcome and Next Steps, eligible Files Modified paths with no generated artifacts, permitted Status values, no self-referencing hash and a count of eleven against the 100-entry limit.

#### Next Steps:

The Zelda stereo fault is the next thing to chase and it should start from a measurement rather than another line-by-line diff of `dsp.v` against MiSTer, which has now been done for the voice volume, echo, `EOUT` and `NON` paths without finding the cause. `tools/ref_emu.py` drives a headless snes9x through retroarch, which is installed on this machine now, so the differential that found nine SPC700 defects can be applied to the S-DSP: capture the board's or the bench's `AUDIO_L`/`AUDIO_R` for a deterministic stretch of Zelda, capture the same stretch from the reference, and compare the two channels sample by sample instead of describing the difference by ear. `tools/sim/gsu_tb.sv` already writes every S-DSP sample through `+wav`, so the bench half needs no new instrument. The discriminating question is whether the fault follows the content or the transport: Yoshi's Island and Earthworm Jim 2 being perfect on the same Pmod narrows it to something Zelda's sound driver does that theirs do not, which points at the echo path, at non-linear mixing, or at the sample-rate servo reacting to a denser mix, and none of those has been excluded yet. Do not re-open the four I2S fixes of entry 3 or the SPC700 opcode fixes of entries 5 and 6, which are each measured. Separately, the Pmod underrun counter should not be treated as a health check until `i2s_out`'s `running` flag is made to drop when the FIFO stays empty, and the board still holds F-Zero, Yoshi's Island and Earthworm Jim 2 as freshly re-confirmed on the fixed core. Saves to the card remain the largest designed-but-unbuilt item with entry 9's plan still awaiting approval, and the deferred items from entry 8 -- the ExHiROM decode in `smc_parser.v` and the coprocessors with no source in the tree -- are unchanged.

#### Files Modified:

- fpga/snes/src/spc700/spc700.v
- tools/sim/run_spc_diff.sh
- tools/sim/spc_diff_tb.sv

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 12 COMMIT Unreleased 2026-11-05T10:55:29-07:00

#### Coming From:

Unreleased adaa0bf

#### Purpose:

Chase the audio fault the user reported on the Pmod output, where stereo imaging collapses toward mono and reopens on Zelda's intro and Earthworm Jim 2's Puppy Love, and record the result honestly whether or not it was fixed.

#### Outcome:

The fault was not found and both fixes attempted this cycle were wrong, which is the substance of this entry rather than a preamble to it. The symptom was first measured rather than described: with the Pmod line-out on the PC's line-in, Zelda's intro gives a side-over-mid ratio that swings from 0.006 to 0.50 while mid RMS holds near 1100, and a later HDMI check by the user established that the Pmod and HDMI outputs sound identical, both carrying the pops and both carrying the stereo fault. That last observation is the cycle's most useful fact and it took the investigation somewhere no earlier reasoning had gone, because HDMI and the Pmod are separate paths after the S-DSP and can only share a defect that is upstream of both. Everything else about the cycle is a record of hypotheses that did not survive. The first fix released `O_sdram_cke`, which was constrained to W20 and therefore to PMOD1_IO1, Digilent pin 7, on the reasoning that the Console's SDRAM module ties CKE high itself and the machine boots with the signal nowhere near the SDRAM connector; it made the audio markedly worse, with large cutouts, and was reverted, so that inference was wrong and the pin is load-bearing. The second fix moved ARAM from the SDRAM controller's port to block RAM, on the reasoning that the S-DSP has no stall input and that an SDRAM read of 5 to 10 master clocks against a DSP step of about 5 was marginal; the arithmetic was wrong by a factor of four, because a DSP step is four CE periods at 5.21 mclk, about 21 mclk, so the read had two to four times the budget it needed, and the build changed nothing the user could hear. Both changes were reverted and nothing of either remains in the tree. The cycle did establish a set of exclusions with evidence behind each: `i2s_out` preserves stereo through the resampler when replayed real captured content, with side over mid going 0.080 to 0.068 and 0.098 to 0.086; its channel routing is not swapped, which a directed probe showed by decoding the serial stream against LRCK with a sign-flipping input and finding zero left-versus-right mismatches over 840 frames; the S-DSP genuinely produces stereo, since Zelda writes different per-voice volumes at `VxVOLL` and `VxVOLR` (voice 0 at 30 and 33, voice 1 at 15 and 8, voice 2 at 134 and 106) and enables echo with `EON` 0xff and `EFB` 0x14, which also corrects entry 11's claim that echo was off, itself drawn from a register trace that only covered 2.79 seconds of boot; voice volume, echo addressing, the `STEP 24`/`25` FIR accumulation guard, the `EOUT` masks, `VS_NON` and the `VOLL`/`EVOLR` clearing asymmetry all match MiSTer's `DSP.vhd` at `901a172c` line for line; and the ARAM bus has one master, the DSP, which schedules the SMP's accesses through its own `RS_SMP` state, so there is no bus collision by design. The cycle also found why the simulation kept agreeing with itself while the board did not, and this is worth carrying: `tools/sim/gsu_tb.sv` models the cartridge, WRAM, VRAM, ARAM and battery SRAM as plain arrays, and its own header states that modelling them "takes the SDRAM capture out of the experiment so a failure here is the core's", so the user's listening test of the bench's `+wav` output -- which sounded perfect and which this session had treated as clearing the S-DSP -- cleared only the arithmetic and not the machine. Two measurement routes were attempted and both failed for environmental reasons rather than technical ones: the Pmod line-in is held open by PipeWire and returns device-busy, and the Guermok capture card's audio endpoint returns silence at peak 0 even with the video stream open and after the user replugged it, so the board's own audio could not be captured and every diagnosis after the first listening test was inference rather than measurement. One real defect was found that is unrelated to audio and was deliberately not fixed: `fpga/snes/tinysnes.cst` constrains all eight PMOD0 pins as `led`, which `snestang_top.v` drives to `8'hff` through an inverting assignment so the pads sit at logic low, and the user's RYLR998 LoRa module occupies PMOD0 Digilent pins 9 through 12, so the core holds the module's TX and RX lines (G22 and E18) low and the module cannot transmit while a TinySNES core is loaded. The board was left on `build/spcfix/tinysnes.bin`, SHA-256 `108c204f22e86d9e31e172dea6b33dce72ac7e8f8037f5096620067020127f3b`, the build the user has confirmed across F-Zero, Yoshi's Island, Earthworm Jim 2 and Donkey Kong Country, with Zelda loaded and running at 4,483 frames and no ROM timeouts. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was not changed, confirmed entries 1 to 11 were not rewritten, and validated this entry as entry 12 with six sections in order, a one-sentence Purpose, prose Outcome and Next Steps, `None.` under Files Modified because every engineering change this cycle was reverted, permitted Status values, no self-referencing hash and a count of twelve against the 100-entry limit.

#### Next Steps:

The audio fault is open and the next cycle should begin by building an instrument rather than proposing a fourth hypothesis, because three have now failed. `fpga/snes/src/tinysnes_dbg.v` already owns block RAM trace buffers and `tools/tinysnes_dbg.py` already dumps them over the BL616 link, so the cheapest board-side measurement is to accumulate mid and side energy over a short sample window there and store the ratio history, which is exactly the quantity this cycle could only compute offline from recordings it could not obtain; eight seconds of history fits the existing RAM. With that, the comparison against the bench becomes direct and the question "does the board produce the samples the simulation does" is answered by a dump instead of by ear. Two things must not be repeated without new evidence: do not move ARAM again, since the timing argument for it was arithmetically false, and do not release `O_sdram_cke`, which is load-bearing and whose release produced cutouts. Do not treat a passing simulation as clearing the S-DSP on this board, because the bench substitutes arrays for the SDRAM-backed cartridge, WRAM, VRAM and ARAM and that substitution is the whole difference under investigation; entry 11's Next Steps repeated that mistake and this entry corrects it. The LoRa pin conflict is independent of the audio work, is cheap, and should be fixed on its own: `led` should not be constrained to PMOD0 pins 9 and 10 while a module occupies them, and the same check should be made for pins 11 and 12. Everything committed earlier stands: the SPC700 reset fix of entry 11 is deployed and user-confirmed, the differential bench and audio counters of entry 10 are in the tree, and the Pmod underrun counter remains unreliable as a health indicator for the reason entry 11 records.

#### Files Modified:

None.

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: FAIL

---

## 13 COMMIT Unreleased 2026-11-05T11:20:52-07:00

#### Coming From:

Unreleased 4c96e77

#### Purpose:

Move ARAM from the SDRAM controller's port to block RAM, because entry 12 left the audio fault open and the capture card came back to life, which allowed the change to be judged by measurement instead of by ear.

#### Outcome:

Entry 12 called this change a failure on the strength of a listening test and an arithmetic argument, and both were wrong. The change is real and it is measured. The error in the argument was that a DSP step is four CE periods of 5.21 mclk, about 21 mclk, and not the 5 mclk entry 12 assumed, so the claim that an SDRAM read of 5 to 10 clocks was marginal was arithmetically false and was withdrawn at the time; what this cycle adds is the measurement that entry 12 never had, because the Guermok capture card's audio endpoint had been returning silence and the operator repaired it. ARAM now lives in a 64 KiB block RAM array in `snestang_top.v`, written on `aram_wr` and read synchronously on the next mclk, which is exactly what `tools/sim/gsu_tb.sv` models, and the controller's ARAM port is tied off rather than carrying live traffic whose acknowledge was discarded. BSRAM goes from 223 to 255 of 340 and the routed netlist puts `aram_mem` on 32 `DP` cells, so the array is block RAM and not a synthesis illusion. The evidence is a capture of the HDMI output through the capture card, aligned against the same passage played in the bench: with ARAM in SDRAM the board's envelope correlated 0.900 with the simulation and its side-over-mid ratio differed by 0.212 on mean and 0.129 at the median, and with ARAM here those become 0.971, 0.140 and 0.112, with near-mono half-second windows falling from 30 percent to 11. The passage the operator named as worst, Zelda's intro from 6.5 to 9.7 seconds where the simulation holds 0.4 to 0.7, read 0.06 to 0.13 on the old build and now reads 0.49 to 0.58. This does not cure the fault. Eleven percent of windows still read near-mono, and the numbers above are single captures each, which the operator's own repeatability check bounds: two captures of the same build differ by 0.088 mean on the same statistic, so the aggregate 30-to-11 figure is softer than it appears and the time-aligned intro comparison is the part to trust. The cycle also settled a question that had been open and had produced two contradictory readings earlier. Capturing the Pmod line-out and the HDMI output simultaneously on the same build, and after the operator pointed out that the capture card delays HDMI relative to the Pmod, a lag search over ten seconds found the two streams correlate 0.999 at a 0.22 second offset, so they carry the same audio and the earlier "Pmod loses stereo that HDMI keeps" reading came from comparing two different runs of different music and is withdrawn. Aligned properly, over 61 half-second windows, HDMI reads a median side-over-mid of 0.149 against the Pmod's 0.113, with a mean difference between them of 0.037 and a maximum of 0.080 and no window where the two diverge, so the Pmod path is not the fault and neither transport is meaningfully worse than the other. That is consistent with what the operator reported from listening and it means the residual near-mono passages are shared content, in the S-DSP's own output, not a transport artefact. The build is `build/aram2/tinysnes.bin`, SHA-256 `c4ec877e1a5a8cb666173cb66694495739d78c4f83fc41135961ce8a273310f6`, seed 2 with `TINYSNES_CLK_FIRST=dbg.clk`, passing every gate at dbg.clk 30.035 against 21.505 MHz, fclk 260.213 against 64.516, hclk 100.271 against 74.250 and the GSU cache clock 326.584 against 65.000, with the clock-edge check passing; it is bit-identical to `build/aram`, which was built before the source was reverted and re-applied, so the committed source reproduces the measured bitstream exactly. It was deployed by `tools/tang_deploy.py` and the operator has Zelda running on it. Regressions pass unchanged: `dbg_link`, `probe_tb`, `i2s_out` at zero underrun and zero overflow, and the SPC700 differential bench at 9,137 instructions with no mismatch. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was not changed, confirmed entries 1 to 12 were not rewritten, and validated this entry as entry 13 with six sections in order, a one-sentence Purpose, prose Outcome and Next Steps, one eligible Files Modified path, permitted Status values, no self-referencing hash and a count of thirteen against the 100-entry limit.

#### Next Steps:

The audio fault is reduced and not closed, and the residual is now localized: both transports carry the same near-mono passages at the same times, so what remains is in the S-DSP's output rather than in `i2s_out` or the HDMI packet path. Do not reopen either transport, and do not reopen ARAM, which is where it belongs now. The next instrument should be the bench rather than the board, because the board is no longer the only place the observation can be made: `tools/sim/gsu_tb.sv` already writes every S-DSP sample through `+wav`, and the comparison that produced this cycle's evidence was against exactly that, so a change made in the DSP can be judged before it is built. The remaining candidates worth measuring, in the order this cycle would take them, are the echo path under the machine's per-frame pause, which the bench does not model at all because it holds `enable` high from cycle 100 and never drops it while the board halts once per frame; the `VOLL` and `VOLR` ordering against `BRR_END` and `KON_CNT` within a step, where MiSTer and this core were compared line by line but never with a signal-level equivalence check; and `VS_NON`, the soft-clip table, which a dense mix reaches more often than a sparse one and which would tie the remaining effect to the titles the operator reports as worst. Two operational facts are worth carrying. The capture card's audio returns silence unless the card has been recently replugged, and the Pmod line-in is claimed by PipeWire until released, so a capture that reads peak zero is a rig problem and not a finding; both were mistaken for findings this session. And the HDMI output lags the Pmod by about 0.22 seconds through the capture card, which must be corrected for before any cross-transport comparison or the two streams will appear unrelated. Everything from earlier cycles stands: the SPC700 reset fix of entry 11 is deployed and confirmed, the differential bench and audio counters of entry 10 are in the tree, and the LoRa conflict on PMOD0 pins 9 and 10 remains unfixed and independent of the audio work.

#### Files Modified:

- fpga/snes/src/snestang_top.v

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 14 COMMIT Unreleased 2026-11-05T15:50:22-07:00

#### Coming From:

Unreleased 92a0b97

#### Purpose:

Fix the S-DSP echo path, whose fault entry 13 had measured and left open, after the operator reported that they had always doubted the earlier ENDX work.

#### Outcome:

The bug was one signal that this core assigned and never read. `ECHO_ADDR` is set once per sample at `VS_ADSR1` when `VS.V == 0`, and MiSTer's `DSP.vhd` addresses all four echo RAM accesses from it; this core instead recomputed every one of them from the live `ECHO_POS`. `VS_ESA` advances `ECHO_POS` by four at STEP 24, which sits between the echo read at STEP 22/23 and the echo write at STEP 29/30, so the read and the write addressed slots four bytes apart and the delay line never read back what it wrote. The fix is four expressions in `dsp.v`, replacing `{TESA,8'h00} + ECHO_POS` with `ECHO_ADDR` in both echo-read and both echo-write calculations. It was found by measurement rather than by reading: the operator's remark that they had always suspected the earlier ENDX change pointed at `dsp.v`, `git log -- fpga/snes/src/dsp.v` showed that only one commit had ever touched that file, and checking the echo path against MiSTer turned up `ECHO_ADDR` as an assigned-but-unused signal, which is the signature of an incomplete port. The measurement that preceded it was built on two independent emulators rather than one: snes9x and bsnes-mercury-accuracy, run through the existing `tools/ref_emu.py` harness with `--core`, agree on Zelda's stereo to 77.1 percent of samples being bit-identical between channels in both, with identical per-second patterns and a waveform correlation of 0.87, which establishes that the game genuinely alternates mono and stereo passages and that the earlier reading of snes9x as downmixing was wrong. Against bsnes, before the fix, the board matched to within 1.0 to 1.1 times wherever the game is genuinely stereo (side over mid 0.43 to 0.44 against 0.37 to 0.40) and emitted between 289 and 3681 times too much left-minus-right wherever the game is mono, reaching side over mid 0.510 where the correct answer is 0.000. After the fix, with each capture aligned independently by envelope correlation, the mono passages fall to 0.054, 0.057, 0.063 and 0.071 side over mid and the stereo passages are unchanged at 0.426, 0.418 and 0.409, so the change removes two to nine times the phantom width without touching correct stereo. A register trace over 18.7 seconds, long enough to reach the intro music rather than stopping at the title screen as the earlier 14-second one had, shows the game writing sharply asymmetric voice volumes from 13 seconds onward (voice 0 at 1e/0f, voice 1 at 21/08, voice 3 at 04/2a, voice 4 at 0a/28, voice 7 at 09/13) where every voice was symmetric for the first 12 seconds, which is why the boot screen is properly mono and the music is properly not. A separate alignment established that the residual correlates with nothing obvious: echo off gives bit-identical channels on 100.0 percent of samples with a left-minus-right RMS of exactly zero, and echo on gives 0.0 percent identical with an RMS of 2144, so the whole phantom lives in the echo path and nowhere else. The build is `build/echoaddr/tinysnes.bin`, SHA-256 `445e5c02da7dfd9d7566d2a2e4fe5f1a868915d5aded571efa8dddea8dd72c75`, seed 2 with `TINYSNES_CLK_FIRST=dbg.clk`, passing every gate at dbg.clk 27.865 against 21.505 MHz, fclk 220.313 against 64.516, hclk 104.789 against 74.250 and the GSU cache clock 290.360 against 65.000, with zero `Driver-driver conflict` lines and BSRAM at 255 of 340. It was deployed by `tools/tang_deploy.py` with all three verification points matching over 5,267,320 bytes, and the operator confirmed three cartridges on it: Zelda, where they reported hearing stereo at the start and mono once the story begins, which is what the reference does; Star Fox, reported flawless, with the GSU at 26.6 percent GO time and no ROM timeouts; and Super Mario World 2: Yoshi's Island, reported flawless, with 23058 GSU stops and 622 million cartridge reads. The operator's verdict on the residual is that only the pops remain and the audio is otherwise close to perfect. `tools/ab_capture.sh` is committed alongside, because every measurement in this entry depends on it: it reloads the core, starts both recorders, then loads the ROM in one fixed sequence, which is what makes two captures comparable, and without the core reload a capture opens on the tail of whatever cartridge was already running. One instrument was built and discarded. A DSP-only testbench, `dsp_echo_tb.sv`, was written to drive the register interface directly and compare `ECHO_BUF[0]` against `ECHO_BUF[1]` cycle by cycle; it compiles and runs but never sounds a voice, because key-on needs the BRR header's loop bit set with the end bit clear (`TBRRHDR[1:0] == 2'b01`) for `KON_CNT` to load, and a single-block loop-and-end sample as a cartridge would use does not satisfy that. It was removed rather than committed, so the tree holds no instrument that reports zero differences on a silent DSP. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was not changed, confirmed entries 1 to 13 were not rewritten, and validated this entry as entry 14 with six sections in order, a one-sentence Purpose, prose Outcome and Next Steps, two eligible Files Modified paths, permitted Status values, no self-referencing hash and a count of fourteen against the 100-entry limit.

#### Next Steps:

The pops and crackles are the one audio symptom the operator still reports, on every cartridge, and they are not addressed by this change: the echo fix corrected the stereo image and left the impulse noise alone. They should be attacked with the instrument that finally worked here, which is an emulator reference rather than more reading of `dsp.v`: `tools/ref_emu.py --core /usr/lib/x86_64-linux-gnu/libretro/bsnes_mercury_accuracy_libretro.so` produces a reference with the same harness and the same headless capture, and a pop is easy to detect objectively because it is a sample far from the midpoint of its neighbours while those neighbours are close to each other, which is a test that percussion fails and a stale read does not. Do not repeat the approach that failed: a DSP-only bench needs the key-on path understood first, specifically that `KON_CNT` loads only when `TBRRHDR[1:0] == 2'b01`, that the BRR header must therefore have loop set and end clear, and that writes issued while `RST_FLG` is set are held in reset. A residual of 0.054 to 0.071 side over mid remains in passages that should be pure mono; it is five to seven percent of the width that was there before, it was not audible to the operator, and it should be left alone unless a cartridge is found where it is. The measurement rig has three traps that cost most of this session's wasted cycles and are worth carrying: a capture that reads peak zero is a rig fault and not a finding, because the capture card's audio endpoint dies until the card is replugged and the Pmod line-in is claimed by PipeWire; the HDMI output lags the Pmod by about 0.22 seconds through the capture card; and a capture must reload the core before loading a ROM or it opens on the previous game. Everything from earlier cycles stands: the SPC700 reset fix of entry 11, the differential bench and audio counters of entry 10, and ARAM in block RAM from entry 13. The LoRa conflict on PMOD0 pins 9 and 10 remains unfixed and independent of the audio work.

#### Files Modified:

- fpga/snes/src/dsp.v
- tools/ab_capture.sh

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 15 COMMIT Unreleased 2026-11-05T16:29:03-07:00

#### Coming From:

Unreleased 87d3399

#### Purpose:

Re-validate the cartridge compatibility record on the echo-fix bitstream, so that every title the project claims runs is confirmed against one build rather than carried over from earlier ones.

#### Outcome:

No source was changed. The cycle re-ran the compatibility record against `build/echoaddr/tinysnes.bin`, SHA-256 `445e5c02da7dfd9d7566d2a2e4fe5f1a868915d5aded571efa8dddea8dd72c75`, the bitstream built and deployed in entry 14, so Build and Deployment are `N/A` here and the user test is what this entry records. Fifteen cartridges were booted from the operator's own library with `tools/load_snes_rom.py`, each held in reset across the transfer and released on the last byte, and judged by eye and ear on the board's HDMI output while the operator watched and listened; the results are recorded cartridge by cartridge, with the operator's words verbatim, in `docs/cart-sweep-2026-11-05.md`, which is the durable evidence for this entry. Eleven came back with no defect reported: Zelda, Super Mario Kart, F-Zero, Super Metroid, Space Invaders, Super Castlevania IV, Vortex, Stunt Race FX, Star Fox 2, Doom, and Winter Gold, the last stopping at its region lockout screen exactly as `PAL = 1'b0` predicts, which confirms the PAL limit is a design boundary and not a crash. Star Fox and Yoshi's Island were already confirmed on this same bitstream during entry 14 and were not re-run. Every cartridge booted, none hung, none showed a blank picture after the region check, and no boot reported a ROM timeout. Two defects were found and neither was touched. The first is a tile gap in a background that is scaled or rotated: Donkey Kong Country's shrinking logo, Donkey Kong Country 2's shrinking logo, and Chrono Trigger's swinging pendulum. DKC and DKC2 share an engine, so the two are one data point seen twice, leaving Chrono Trigger as the independent sighting. Mode 7 was the first candidate and is now ruled out, because F-Zero is Mode 7 on every scanline and is clean; what the three affected scenes share instead is a transform updated once per scanline rather than a scrolling tilemap, which points at the HDMA-driven per-line register path first, offset-per-tile second, and colour math or mosaic on a transformed background third. The second defect is a low-frequency artefact, heard on Super Mario World's intro and again on Donkey Kong Country 2's title-select drum beats, in both cases with everything else on the title clean, so the fault is content-selective and needs low pitch and high amplitude together; the BRR decoder's four filters are the strongest candidate because filters one and two carry the low-frequency response and a wrong coefficient or tap history would distort loud low content and leave quiet high content alone, and the way to settle it is a bsnes reference capture through `tools/ref_emu.py` on the same passage rather than more reading of `dsp.v`. The cycle also produced three corrections to statements made while it was running, all recorded in the sweep document because the debug bank is quoted by future cycles: `uptime` in `tinysnes_dbg.v` is a 32-bit mclk counter that wraps every 199.9 seconds, so it stops measuring time since configuration after about three and a half minutes and a status reading cannot be trusted as an absolute after that; the `GO time` percentage is `go_time` divided by `uptime`, and because `go_time` counts only clocks where the GSU asserts GO it wraps far later, so the ratio reads above 100 percent once `uptime` has rolled over, which is what produced a 101.6 percent reading on Doom even though both counters were individually correct; and `GSU_GO_CNT` lives in `main.v`, instantiated with `resetn & ~loading`, so it clears on every ROM load, while `tinysnes_dbg` is instantiated with `resetn` alone and accumulates since FPGA configuration, which makes any pairing of `GO starts` with `stops` meaningless even though each number alone is valid. An earlier claim during the sweep that the counters themselves were broken is withdrawn; the counters are sound and the derived percentage is not. Two defects established in earlier cycles remain open and unchanged: the pops, which are broadband impulses on every title and are independent of content, and the residual mono-passage width of 0.054 to 0.071 side over mid that entry 14 measured and judged inaudible. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was not changed, confirmed entries 1 to 14 were not rewritten, and validated this entry as entry 15 with six sections in order, a one-sentence Purpose, prose Outcome and Next Steps, one eligible Files Modified path, permitted Status values, no self-referencing hash and a count of fifteen against the 100-entry limit.

#### Next Steps:

Two defects have earned work and neither has been started. The low-frequency artefact is the cheaper of the two to settle because the instrument already exists and the fault may already be localized: run `tools/ref_emu.py` with `--core /usr/lib/x86_64-linux-gnu/libretro/bsnes_mercury_accuracy_libretro.so` on Super Mario World's intro and on Donkey Kong Country 2's title-select screen, band-limit both the reference and a board capture below a few hundred hertz, and compare them sample by sample, because if the board's low band is distorted where the reference is clean then the BRR filters are confirmed and the fix is a coefficient or tap-history comparison against MiSTer, and if it is not then the artefact is somewhere further down the chain and the Gaussian table becomes the candidate. The tile gap needs a different instrument and should not be attacked by reading `ppu.v`: the three affected scenes all animate a transform through per-line updates rather than scrolling, so the thing to build is a comparison that renders the same animation on the bench and in a reference emulator and diffs the per-line register writes, which `tools/sim/board_tb.sv` and the `trace` subcommand of `tools/tinysnes_dbg.py` are already shaped to do. Do not trust the `GO time` percentage reported by `tools/tinysnes_dbg.py` after approximately 200 seconds of uptime, and do not quote it against `uptime`; the tool should take `go_time` as an absolute and it is worth fixing before the next GSU cycle rather than working around. The sweep deliberately excluded five areas and they are listed in `docs/cart-sweep-2026-11-05.md`: hi-res modes five and six, interlace, the Super Scope and mouse and multitap input paths, the unbuilt SA-1 and CX4 and S-DD1 and SPC7110 coprocessors, and PAL operation, and each of those is a candidate for its own cycle rather than a gap in this one. Everything from earlier cycles stands unchanged: the S-DSP echo fix and its measurement in entry 14, the SPC700 reset fix in entry 11, the differential bench of entry 10, and ARAM in block RAM from entry 13. The LoRa conflict on PMOD0 pins 9 and 10 remains unfixed and independent of everything above.

#### Files Modified:

- docs/cart-sweep-2026-11-05.md

#### Status:

- Build: N/A
- Deployment: N/A
- User Test: PASS

---

## 16 COMMIT Unreleased 2026-11-05T18:15:02-07:00

#### Coming From:

Unreleased 94dc0de

#### Purpose:

Fix the tile gap that entry 15 recorded in scaled and rotated Mode 7 backgrounds, after the operator identified all three affected surfaces as Mode 7 planes and measured the seam period.

#### Outcome:

The fault was a clock-enable boundary in `ppu.v`, and the fix moves five signals inside it. Mode 7's sample position `M7_VRAM_X/Y` was computed combinationally in `bg_addr_gen` while the three fields taken from it — `M7_TILE_N`, `M7_TILE_COL` and `M7_TILE_ROW` — were latched on every master clock, outside the `DOT_CLKR_CE` enable, so they updated four times per Dot; `M7_TILE` arrives from the VRAM read with latency behind it, so the character number and the 3-bit in-character column taken from `M7_VRAM_X[10:8]` could describe different screen positions within one Dot, and the pixel address `{M7_TILE_N, M7_TILE_ROW, M7_TILE_COL}` mixed a character from one position with a row and column from the next. MiSTer's `PPU.vhd` registers `M7_VRAM_X/Y` at `DOT_CLKR_CE` and latches the tile number and row/column at that same enable, so every field of the address describes one position; the fix does the same, and also widens `M7_TEMP_X/Y` and `M7_VRAM_X/Y` from 24-bit to 27-bit signed with the truncation mask and outside test adjusted to match, which is what upstream declares and which this core had narrowed. Two builds were made and deployed. The first, `build/m7wide/tinysnes.bin`, SHA-256 `4bf983ee355387a9fb17fadd643642aed41040d227fdfd854d41f7e8cefb4e29`, carried the widening alone and did not change the symptom, which is recorded here because it is the measurement that separates the two halves of the change: the width was not the fix. The second, `build/m7pipe/tinysnes.bin`, SHA-256 `1ff104073dc24794dfe37106e51fd8668bde600efe20e15c448289ea4a40f6d7`, carries both and is the one the operator accepted; it was built with `TINYSNES_CLK_FIRST=dbg.clk TINYSNES_SEED=2 TINYSNES_ALLOW_HOLD=1 TINYSNES_ALLOW_UNMEASURED_CLOCKS=1`, passing every gate at dbg.clk 31.764 against 21.505 MHz, fclk 283.688 against 64.516, hclk 102.617 against 74.250 and the GSU cache clock 431.406 against 65.000, with the clock-edge check passing and both the SuperFX and cartridge DSP asserts satisfied. The clock-plane gate reports `main.genblk5.GSUMap.GSU.cache.0.0_CLKB` reaching no spine tap, which is the condition entry 1 records for every board-tested build and which the allow flag admits; it is unchanged by this cycle and remains a caveat on GSU behaviour rather than on this fix. It was deployed by `tools/tang_deploy.py` with all three verification points matching over 5,225,142 bytes, and a fresh configuration was confirmed by the debug bank reading uptime 8.81 s with zero frames before any cartridge was loaded. The operator confirmed all three surfaces on that bitstream: Chrono Trigger's pendulum clean, Zelda's Mode 7 map clean, and Donkey Kong Country's shrinking logo clean, which closes the defect entry 15 left open. The diagnosis came from the operator's measurement rather than from reading the code. The three seam positions were read by eye from a screenshot of the pendulum at x = 908.5, 938 and 968 in a 1280-wide capture, a spacing of 29.5 and 30 screen pixels; the game area spans 956 screen pixels for 256 SNES pixels, or 3.734 screen pixels per SNES pixel, and 29.75 divided by 3.734 is 7.97, so the seams repeat every 8 SNES pixels and therefore every character cell, which is what pointed at the character-boundary fields rather than at sub-texel precision. This entry also corrects entry 15 and `docs/cart-sweep-2026-11-05.md`, both of which recorded that Mode 7 was ruled out because F-Zero is clean. That conclusion was wrong and the test behind it was invalid: F-Zero magnifies the Mode 7 plane, so consecutive output pixels step less than one texel and a position error that only crosses a texel boundary under minification or rotation cannot appear there, which makes it a test that could not fail; the three non-Mode-7 candidates listed in entry 15 — HDMA per-line writes, offset-per-tile and colour math or mosaic — were therefore all wrong, and the build spent on the widening-first attempt was the cost of that error. The sweep document retains its original text with the correction appended rather than rewritten, and the Mode 7 hypothesis is recorded as withdrawn. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was not changed, confirmed entries 1 to 15 were not rewritten, and validated this entry as entry 16 with six sections in order, a one-sentence Purpose, prose Outcome and Next Steps, two eligible Files Modified paths, permitted Status values, no self-referencing hash and a count of sixteen against the 100-entry limit.

#### Next Steps:

The low-frequency artefact is now the only defect the sweep found that is still open, and it is the next cycle. Entry 15 records its shape: Super Mario World's intro and Donkey Kong Country 2's title-select drum beats, everything else on both titles clean, so the fault needs low pitch and high amplitude together, which is what a kick drum is and what the BRR filters act on most. Judge it the way this cycle's defect was judged, with a measurement that can fail rather than a listening impression: capture a board run and a bsnes run of the same passage through `tools/ref_emu.py --core /usr/lib/x86_64-linux-gnu/libretro/bsnes_mercury_accuracy_libretro.so`, band-limit both below a few hundred hertz, and compare sample by sample, because a distorted low band on the board against a clean one in the reference confirms the filters while a clean low band sends the search to the Gaussian table. Two lessons from this cycle are worth carrying. A test whose geometry cannot exhibit the defect is not evidence, which is what the F-Zero check was, and the first question of any negative result should be whether the setup could have produced a positive one. And an operator's hand measurement of three feature positions can be more informative than an automated detector: the seam period of 8 pixels was what identified the field boundary, while a gradient scan over the same screenshot returned spacings scattered from 3 to 27 because it picked up the texture's own banding. The pops remain open and independent, broadband impulses on every title with no content dependence, and were not touched here. Everything from earlier cycles stands: the S-DSP echo fix of entry 14, the SPC700 reset fix of entry 11, the differential bench of entry 10 and ARAM in block RAM from entry 13. The unmeasured GSU cache clock, the five sweep areas listed as not covered in `docs/cart-sweep-2026-11-05.md`, and the LoRa conflict on PMOD0 pins 9 and 10 are all unchanged and independent of this fix.

#### Files Modified:

- fpga/snes/src/ppu.v
- docs/cart-sweep-2026-11-05.md

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 17 COMMIT Unreleased 2026-11-05T20:34:12-07:00

#### Coming From:

Unreleased 28a6d18

#### Purpose:

Expose the cartridge SRAM to the BL616 so TinySNES can keep battery saves on the card, and refuse at build time the multiple-driver fault that made the first attempt fail silently.

#### Outcome:

The core now answers two frames the firmware needs to persist a save. `iosys_bl616.v` gained 0x18, which carries a 24-bit address in its first three payload bytes and then a run of data bytes to store from there, and 0x19, which carries the same address and a byte count and replies with that many bytes followed by a CRC-16 over its type byte and data. A 0x19 reply is capped at 250 data bytes, which with the four-byte frame header and the two CRC bytes is the largest that fits the BL616's 256-byte payload. Both are refused unless `rom_loading` is non-zero, and a refusal to a read is a reply carrying no data bytes rather than silence, so the host can tell a refusal from a timeout; the gate is in the core rather than in the firmware because the core is what knows whether the 65816 and the GSU are idle, and while `loading` is set they are both held in reset and the array has no other master. `snestang_top.v` muxes the block-RAM array's address, write enable and data to that window while `loading` is set, which adds no block RAM to a design already at 340 of 340 and leaves the game owning the port exactly as before when no load is running. The pad word gained bit 15 while HOME and SELECT are both held, which is the save-and-exit gesture the operator specified for TinyNES and TinyGBC; SELECT being down means the desk's tap detector never arms, so the gesture does not open the desk on its way out. `send_idx` widened from seven to eight bits because a 250-byte reply does not fit the old range, and the two states whose type byte is above the state range now take it from a mux instead of the one special case that was there. `tools/sim/dbg_link_tb.sv` covers the exit bit and both frames: a read while the core is running is refused, 16 bytes written and read back byte-exact, a block at 0x1FF00 so an address carrying only its low byte fails, a 250-byte maximum, a zero-length read refused, the bytes confirmed present in the model array rather than only through the read path, and the exit bit reported as 0x8000 with no LB. Two runs of three builds were needed because the first was wrong on hardware in a way simulation could not see. `sav_addr` was assigned in two `always` blocks -- the write path in the receive handler and the read increment in the sender -- which yosys does not reject: it keeps one assignment and drops the other. On the board the address therefore never advanced, so a 16-byte read returned the same byte sixteen times, with a correct reply length and a correct CRC, and the bench and the firmware's host test both passed because both check framing rather than the path. The fix gives each direction its own register, `sav_wr_addr` written by the receive handler and `sav_rd_addr` by the sender, muxed onto the port, so 0x19 latches its base when the reply starts and advances its own counter. The bench had a matching flaw and it was fixed rather than left: it derived the expected `frame_len` from the header instead of from the request, so a header two bytes short agreed with an expectation two bytes short; it now checks the header against the request and fails on the old sender with `frame_len 18, want 19` and a bad CRC, which was verified by putting the fault back. Because neither the bench nor the host test can see a multiple driver at all, the build gained `TINYSNES_STAGE=lint`, which runs yosys `check` over the same read commands as synthesis and passes the log to `tools/multi_driver_check.py`; that tool fails on any conflicting name that is not in `tools/multi_driver_baseline.txt`, whose seven entries are all function-local temporaries that yosys reports because it reuses a function's variable names for each inlined copy, and it names the signal and says what to do. Verified both ways: the committed tree exits 0, and a deliberately reintroduced second driver on `sav_rd_addr` exits 1 naming `iosys.sav_rd_addr`. The build is `build/save3/tinysnes.bin`, SHA-256 `1265d20f0c3bfa39c656e972f51037a4aadc4e5fcc327bfd85d37447df0fbd9f`, seed 2 with `TINYSNES_CLK_FIRST=dbg.clk`, passing every gate at dbg.clk 29.991 against 21.505 MHz, fclk 258.465 against 64.516, hclk 103.541 against 74.250 and the GSU cache clock 269.542 against 65.000, with the clock-edge check passing, both chip assertions satisfied, zero `multiple conflicting drivers` lines naming `sav_`, and BSRAM unchanged; its synthesis log has 230 conflicting-driver warnings in total, the same set the pre-save build `build/m7pipe` had, so the seven baseline names are the whole story and nothing new arrived. It was deployed by `tools/tang_deploy.py` to `/root/cores/console138k/tinysnes.bin`, the path the desk app loads, with all three verification points matching over 5,222,380 bytes. Hardware evidence was taken before the operator used it, because the previous claim rested on simulation and was wrong: a 16-byte write-then-read returned the pattern byte-exact with a matching CRC, which the same test had returned as sixteen copies of the last byte on the broken build; an 8 KiB round trip matched in all 33 blocks; and after the firmware restored a known pattern with `snesload`, holding the core in reset and reading the array back returned that pattern with SHA-256 `1f5a16c4` matching the file on the card, which is the whole path the desk app uses on every launch. The operator then confirmed the result end to end: a save written from the desktop survived a reboot of the Tang, and the file read back off the card is 8,192 bytes with twelve distinct byte values and real data at the offsets where Zelda's three save slots live, against the single repeated byte the broken build wrote. The firmware half is the TinyTang repository's entry 7, and this entry cannot be read on its own without it. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was not changed, confirmed entries 1 to 16 were not rewritten, and validated this entry as entry 17 with six sections in order, a one-sentence Purpose, prose Outcome and Next Steps, six eligible Files Modified paths, permitted Status values, no self-referencing hash and a count of seventeen against the 100-entry limit.

#### Next Steps:

The lint stage is the durable result of this cycle and should be run in the standard recipe from now on, because it catches a class of fault that no other gate here can see: a register with two drivers synthesises to whichever assignment yosys keeps, and the netlist is then wrong in a way that simulation, the host tests and the protocol checks all pass. It cannot be folded into place and route, since synthesis is cached by the presence of `tinysnes.json`; it is a separate stage that costs seconds. Every name that appears in the baseline should be revisited if the RTL around it changes, because the list is a claim about function locals and a real fault hidden behind a familiar name would pass. The SuperFX save size remains unverified against a real cartridge: Yoshi's Island is predicted at 32 KiB through the expansion byte at 0x7FBD, the rule is right on seven other cartridges, and none of them takes that path, so it belongs with the next SuperFX cycle. The low-frequency artefact that entry 15 recorded is still the only defect the sweep found that is untouched and it is still scoped there as a bsnes band-limited comparison rather than more reading of `dsp.v`; the pops remain open and independent. The GSU cache clock still reaches no spine tap, which is unchanged by this cycle and is the condition every board-tested build has run under. Everything from earlier cycles stands: the Mode 7 address fix of entry 16, the S-DSP echo fix of entry 14, the SPC700 reset fix of entry 11, the differential bench of entry 10 and ARAM in block RAM from entry 13, with the LoRa conflict on PMOD0 pins 9 and 10 unchanged and independent.

#### Files Modified:

- fpga/snes/src/iosys/iosys_bl616.v
- fpga/snes/src/snestang_top.v
- tools/build_tinysnes.sh
- tools/sim/dbg_link_tb.sv
- tools/multi_driver_baseline.txt
- tools/multi_driver_check.py

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 18 COMMIT Unreleased 2026-11-05T21:43:58-07:00

#### Coming From:

Unreleased d217d83

#### Purpose:

Close the one claim entry 17 left unverified, the SuperFX expansion-byte save size, which the operator tested on a real Yoshi's Island cartridge.

#### Outcome:

No source changed. Entry 17 recorded that the sizing rule was right on seven cartridges but that none of them took the SuperFX branch, where a cartridge leaves header byte 0x18 zero and puts its real SRAM size in the expansion byte three bytes before the header, and named a Yoshi's Island save as the test that path needed. The operator took it: `Super Mario World 2 - Yoshi's Island (USA) (Rev 1)` saved from the desk app and the firmware wrote `/sd/root/saves/snes/Super Mario World 2 - Yoshi's Island (USA) (Rev 1).sav` at 32,768 bytes, which is the predicted size and is not the 1 KiB a zero 0x18 would give without the fallback. Read back off the card the file has 256 distinct byte values and 7,877 nonzero bytes spread from offset 0 to 32,379, so it is a real save and not the repeated-byte garbage the broken core of entry 17 wrote, and no `.part` file was left behind, so the read-back verify and the rename both completed. `fpga` then reported the desktop core answering, which means the exit gesture returned to the desk rather than leaving the game held in reset. This also closes the same claim in the TinyTang repository's entry 7, whose Next Steps named it, and it is recorded here rather than by rewriting either settled entry. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai/` diff, confirmed `.ai/core.md` was not changed, confirmed entries 1 to 17 were not rewritten, and validated this entry as entry 18 with six sections in order, a one-sentence Purpose, prose Outcome and Next Steps, `None.` under Files Modified because no engineering file changed, permitted Status values, no self-referencing hash and a count of eighteen against the 100-entry limit.

#### Next Steps:

Every part of the battery-save path is now hardware-proven and no part of it needs re-testing: the sizing rule on both the ordinary and the SuperFX branch, the 250-byte block write with its per-block CRC, the `.part` and CRC-32 verify and rename, the restore from card to cartridge SRAM, and persistence across a reboot, which the operator confirmed twice. The two files the broken core wrote remain on the card as `Zelda-bad.sav` and `ADnD-bad.sav` and can be deleted whenever the operator wants the space. The next cycle is the desktop window's tabs, which is TinyTang's work and is not in this repository. What is still open here is unchanged: the low-frequency artefact of entry 15, scoped there as a bsnes band-limited comparison rather than more reading of `dsp.v`; the pops, which are broadband and independent of content; the GSU cache clock reaching no spine tap, which every board-tested build has run under; and the LoRa conflict on PMOD0 pins 9 and 10. The lint stage added in entry 17 should be in the standard recipe from now on, since it is the only gate here that can see a register with two drivers.

#### Files Modified:

None.

#### Status:

- Build: N/A
- Deployment: N/A
- User Test: PASS

---
