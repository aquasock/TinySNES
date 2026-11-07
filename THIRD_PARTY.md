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
  unmodified, and keeps its MIT licence: this repository is GPL-3.0-only, and
  MIT is compatible with it, so a copied file is left saying what it said
  where it came from rather than being relabelled as something it is not.

- **Build tools** — yosys with the slang front end, `nextpnr-himbaechel` and
  `apicula` from the aquasock forks. They are build inputs, not vendored code.

## This repository's own licence

TinySNES is **GPL-3.0-only**. The text is in `LICENSE`, and every file this
repository wrote says so in its `SPDX-License-Identifier` header.

The licence is not a preference here. `fpga/snes/src/` is SNESTang, which is
GPL-3.0, vendored in-tree rather than fetched, and TinySNES's own RTL is
compiled into the same bitstream as it, so the result is a single work and
GPL-3.0 is the only licence that work can carry. `GPL-3.0-only` rather than
`GPL-3.0-or-later` names what is actually granted: the SNESTang sources are
the version 3 as published, with no "or later" in their notices.

The decision was taken on 2026-11-07, replacing the earlier "not yet decided"
state in which this file recorded that a GPL-3.0-compatible licence was the
practical choice. Files carried in from TinyTang or TinyNES — `tools/fs_to_bin.py`
— keep their own MIT licence, which GPL-3.0 permits; the three PLL wrappers are
this repository's own hand-written work and moved with it. Vendored components
keep their own terms: hdl-util's HDMI transmitter stays MIT
(`fpga/snes/hdmi/LICENSE-MIT`).
