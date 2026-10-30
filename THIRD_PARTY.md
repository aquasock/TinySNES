# Third-party code carried in this repository

TinySNES vendors the upstream sources it builds rather than patching an
upstream checkout, following the same rule TinyTang's `fpga/desktop/` states:
every source the core needs is in this tree, and no external checkout is
involved in a build.

- **SNESTang** — `fpga/snes/src/` and the file list in `tools/build_tinysnes.sh`
  come from nand2mario's SNESTang at commit `5f0ef19`
  (https://github.com/nand2mario/snestang), GPL-3.0. The SNES machine itself
  derives from srg320's SNES_FPGA and the MiSTer SNES core, as
  `doc/design.md` in that project describes. Twelve files carry small,
  documented modifications for the open flow; each change is marked in place
  with a `TinySNES:` comment.

- **hdl-util/hdmi** — `fpga/snes/hdmi/`, the HDMI transmitter, by Sameer Puri,
  MIT. This copy is TinyTang's (`fpga/desktop/hdmi/`), which has run on this
  board; SNESTang's own copy of the same project does not elaborate in slang.
  Its licence is carried as `fpga/snes/hdmi/LICENSE-MIT`.

- **TinyTang and TinyNES** — the shape of `tools/build_tinysnes.sh`, and the
  three hand-written PLL wrappers in `fpga/snes/pll/`, come from TinyTang's
  `tools/desktop_open/` and `fpga/desktop/pll/` and from TinyNES's
  `tools/build_ae350_soc.sh` (MIT). `tools/fs_to_bin.py` is TinyNES's file,
  unmodified.

- **Build tools** — yosys with the slang front end, `nextpnr-himbaechel` and
  `apicula` from the aquasock forks. They are build inputs, not vendored code.

The licensing of this repository's own additions is not yet decided; the
vendored GPL-3.0 sources mean a GPL-3.0-compatible licence is the practical
choice, and that decision is the user's.
