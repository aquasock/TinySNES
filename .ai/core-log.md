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
