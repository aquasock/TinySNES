// SPDX-License-Identifier: MIT
//
// Live simulation window for TinySNES.
//
// Modelled on TinyGBA's tools/sim/sim_main.cpp (projectf.io's Verilator+SDL
// recipe): a C++ main() drives the Verilated design, pipes the PPU's pixel
// stream into an SDL texture and presents one window per frame.  The point is
// that a human can watch the machine boot and report what they see, the way
// they would look at the Tang's HDMI output, without a bitstream or a capture
// card -- and OBS can capture this window.
//
// What it shows: the SNES picture, captured at the same point snes2hdmi writes
// its line buffer (a rising DOTCLK with both blankings inactive), scaled 3x.
// A second window carries the GSU's state as text, because this thread exists
// to bring the SuperFX up and the picture alone cannot say what it is doing.
//
// Keys: Q or ESC quits, SPACE pauses, S writes a screenshot to shot-N.ppm.
//
#include <SDL.h>
#include <verilated.h>
#include "Vgsu_tb.h"
#include "Vgsu_tb___024root.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

static const int H_RES = 256;   // SNES visible width
static const int V_RES = 224;   // SNES visible height
static const int SCALE = 3;

struct Pixel { uint8_t r, g, b, a; };

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);

    // +hex is required by the bench; anything else is passed through.
    bool have_hex = false;
    for (int i = 1; i < argc; i++)
        if (strncmp(argv[i], "+hex=", 5) == 0) have_hex = true;
    if (!have_hex) {
        fprintf(stderr, "usage: %s +hex=<rom.hex> [+romtype=N] [+cycles=N]\n", argv[0]);
        return 2;
    }

    Vgsu_tb *dut = new Vgsu_tb;

    if (SDL_Init(SDL_INIT_VIDEO) < 0) {
        fprintf(stderr, "SDL init failed: %s\n", SDL_GetError());
        return 1;
    }

    SDL_Window   *win  = SDL_CreateWindow("TinySNES Sim",
                                          SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
                                          H_RES * SCALE, V_RES * SCALE, SDL_WINDOW_SHOWN);
    SDL_Renderer *ren  = SDL_CreateRenderer(win, -1, SDL_RENDERER_ACCELERATED);
    // The pixel format must match the byte order of `struct Pixel`, which is
    // {r,g,b,a}.  SDL_PIXELFORMAT_RGBA8888 packs A into bits 31:24, so on a
    // little-endian host the bytes in memory are a,b,g,r -- the reverse.  Using
    // it with {r,g,b,a} made the window paint every pixel with r=alpha=255,
    // i.e. a solid red screen, while the PPM written from the same buffer was
    // correctly black.  TinyGBA's harness avoids this by declaring its Pixel as
    // {a,b,g,r}; ABGR8888 is the format that matches our struct instead.
    SDL_Texture  *tex  = SDL_CreateTexture(ren, SDL_PIXELFORMAT_ABGR8888,
                                           SDL_TEXTUREACCESS_STREAMING, H_RES, V_RES);
    if (!win || !ren || !tex) {
        fprintf(stderr, "SDL window/texture failed: %s\n", SDL_GetError());
        return 1;
    }

    // A second window for GSU state.  Text only, redrawn when it changes, so a
    // human reading it during a run can say what the coprocessor was doing.
    SDL_Window *win2 = SDL_CreateWindow("GSU state",
                                        SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
                                        640, 260, SDL_WINDOW_SHOWN);

    std::vector<Pixel> fb(H_RES * V_RES, Pixel{0, 0, 0, 255});
    long long cyc = 0;
    long long pix_captured = 0, pix_nonblack = 0;
    int frames = 0;
    bool paused = false, done = false;
    int shot = 0;

    auto write_shot = [&]() {
        char name[64];
        snprintf(name, sizeof name, "shot-%d.ppm", shot++);
        FILE *f = fopen(name, "wb");
        if (!f) return;
        fprintf(f, "P6\n%d %d\n255\n", H_RES, V_RES);
        for (int y = 0; y < V_RES; y++)
            for (int x = 0; x < H_RES; x++) {
                const Pixel &p = fb[y * H_RES + x];
                fwrite(&p.r, 1, 1, f); fwrite(&p.g, 1, 1, f); fwrite(&p.b, 1, 1, f);
            }
        fclose(f);
        printf("wrote %s\n", name);
    };

    // One master clock: toggle the bench clock and let Verilator settle.
    auto tick = [&]() {
        dut->clk = 1; dut->eval();
        dut->clk = 0; dut->eval();
        cyc++;
    };

    while (!done) {
        // Events
        SDL_Event e;
        while (SDL_PollEvent(&e)) {
            if (e.type == SDL_QUIT) done = true;
            if (e.type == SDL_KEYDOWN) {
                switch (e.key.keysym.sym) {
                case SDLK_ESCAPE: case SDLK_q: done = true; break;
                case SDLK_SPACE: paused = !paused; break;
                case SDLK_s: write_shot(); break;
                }
            }
        }
        if (paused) { SDL_Delay(50); continue; }

        // Run a slice of clocks between frame updates, so the window stays
        // responsive without presenting every cycle.
        bool frame_ready = false;
        for (int n = 0; n < 2000000 && !frame_ready; n++) {
            tick();

            // Honour the bench's own end-of-run.
            //
            // gsu_tb.sv calls $finish once it has printed its report at
            // +cycles, but this harness drives Verilator by hand and never
            // looked at gotFinish(), so $finish was inert here: the always
            // block that prints the report kept firing on every clock.  One
            // run redirected that to a tmpfs file and grew it to ninety
            // million lines -- about six gigabytes of RAM -- until the machine
            // had to be powered off.  Checking gotFinish() is the whole fix;
            // the one-shot guard in the bench is the second lock on the same
            // door.
            if (Verilated::gotFinish()) { done = true; break; }

            // The bench drives reset/enable/rom_type off its own cycle counter,
            // so nothing here has to sequence the boot.
            // X_OUT is {OUT_X, DOT_CLK}: bit 0 is the dot clock and bits 8:1
            // are the column.  Treating X_OUT as a coordinate doubled every x
            // and left half the frame unwritten, which is what "missing
            // scanlines" looked like.  snes2hdmi's own address is
            // {ys[4:0], xs[8:1]} for the same reason.
            if (dut->o_dotclk && dut->o_hblankn && dut->o_vblankn &&
                ((dut->o_x >> 1) < 256) && dut->o_y < 224) {
                int x = dut->o_x >> 1, y = dut->o_y;
                int c = dut->o_rgb;
                Pixel &p = fb[y * H_RES + x];
                pix_captured++;
                // RGB_OUT is BGR555, not RGB555: snes2hdmi builds its 24-bit
                // pixel as {rdata[4:0],rdata[9:5],rdata[14:10]}, so the LOW five
                // bits are red and the HIGH five are blue.  Reading it the
                // obvious way swaps red and blue and makes a red title screen
                // look wrong in a way that reads as a rendering bug.
                p.r = (c & 0x1f) << 3;
                p.g = ((c >> 5) & 0x1f) << 3;
                p.b = ((c >> 10) & 0x1f) << 3;
                p.a = 255;
                if (c) pix_nonblack++;
                // The bench's own end-of-run is the only stop condition it has.
            }
            if (cyc % 2000000 == 0) {
                // Redraw roughly twice a second at simulation speed.
                frame_ready = true;
            }
        }

        SDL_UpdateTexture(tex, nullptr, fb.data(), H_RES * sizeof(Pixel));
        SDL_RenderClear(ren);
        SDL_RenderCopy(ren, tex, nullptr, nullptr);
        SDL_RenderPresent(ren);
        frames++;

        if (win2) {
            char title[256];
            snprintf(title, sizeof title,
                     "GSU go=%d SFR=%04X states=%04X stop=%d | cpu %02X:%04X | mclk %lld",
                     (int)dut->o_go_cnt, (unsigned)dut->o_sfr,
                     (unsigned)dut->o_state_seen, (int)dut->o_stop_seen,
                     (unsigned)dut->o_pbr, ((unsigned)dut->o_pc_hi << 8) | dut->o_pc_lo,
                     cyc);
            SDL_SetWindowTitle(win2, title);
        }

        // Progress plus a periodic screenshot, so a run can be checked without
        // a human watching the window.  The file is overwritten each time; the
        // last one is the picture.
        if (frames % 10 == 0) {
            printf("frame %d, mclk %lld, GSU go=%d states=%04X, pixels=%lld nonblack=%lld\n",
                   frames, cyc, (int)dut->o_go_cnt, (unsigned)dut->o_state_seen,
                   pix_captured, pix_nonblack);
            fflush(stdout);
        }
        if (frames % 20 == 0) {
            FILE *f = fopen("auto.ppm", "wb");
            if (f) {
                fprintf(f, "P6\n%d %d\n255\n", H_RES, V_RES);
                for (int y = 0; y < V_RES; y++)
                    for (int x = 0; x < H_RES; x++) {
                        const Pixel &p = fb[y * H_RES + x];
                        fwrite(&p.r, 1, 1, f); fwrite(&p.g, 1, 1, f); fwrite(&p.b, 1, 1, f);
                    }
                fclose(f);
            }
        }
    }

    write_shot();
    delete dut;
    SDL_DestroyTexture(tex);
    SDL_DestroyRenderer(ren);
    SDL_DestroyWindow(win);
    if (win2) SDL_DestroyWindow(win2);
    SDL_Quit();
    return 0;
}
