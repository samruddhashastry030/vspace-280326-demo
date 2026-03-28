<!---
Tiny Tapeout project datasheet
-->

# CryptoMuse — PRESENT-Keyed Generative Music Engine

- **Author:** Samruddha S Shastry, Prasoon Mishra, Varun Shankar
- **Description:** A PRESENT-80 lightweight cipher (ISO/IEC 29192-2) whose encrypted output drives a pentatonic music engine, producing cryptographically unpredictable melodies via PWM audio.
- **Language:** Verilog
- **[GitHub repository](https://github.com/your-repo/cryptomuse-tt)**

## What it does

CryptoMuse is a dual-function chip:

**Block 1 — PRESENT-80 cipher.** Encrypts a 64-bit plaintext under an 80-bit secret key in 31 rounds using a serialised 4-bit/cycle datapath to minimise gate count. Output is verified against the four official test vectors (Bogdanov et al., 2007).

**Block 2 — Generative Music Engine.** Decodes slices of the live 64-bit cipher state into pentatonic notes, durations, and optional chords, then drives a PWM square-wave audio output. Because the cipher's avalanche effect ensures a 1-bit key change scrambles the entire state, the resulting melody changes completely and unpredictably — a live demonstration of cryptographic strength.

## How to test

### Simulation
```bash
cd src
iverilog -o sim cryptomuse.v tb.v && vvp sim
```

### Cocotb (Tiny Tapeout flow)
```bash
cd test && make
```
Five test phases run automatically:
1. Reset behaviour (PWM and done must be low)
2. Golden vector verification (all 4 official PRESENT-80 vectors)
3. PWM toggle check (music engine active after encryption)
4. Pause / Resume (mirrors stopwatch button behaviour)
5. Avalanche effect (1-bit key change → ≥16-bit output change)

### Hardware demo
1. Connect `uo_out[0]` → 1 kΩ resistor → 100 nF cap → audio jack (RC low-pass, f_c ≈ 1.6 kHz).
2. Load 80-bit key: 10 bytes MSB-first on `ui_in[7:0]`, hold `uio_in[0]` high each byte.
3. Load 64-bit plaintext: 8 bytes on `ui_in[7:0]`, hold `uio_in[1]` high each byte.
4. Pulse `uio_in[2]` for one clock → encryption starts.
5. Wait for `uio_out[0]` (done) to go high (~512 cycles).
6. Set `ui_in[0]=1` to start music. Change the key to hear a completely different melody.

## External hardware

| Component | Value | Purpose |
|---|---|---|
| Resistor | 1 kΩ | RC low-pass filter |
| Capacitor | 100 nF | RC low-pass filter |
| 3.5 mm audio jack / speaker | — | Audio output |
| Oscilloscope (optional) | — | Verify PWM frequencies |

## IO

### Inputs

| Signal | Pin | Description |
|---|---|---|
| `data_in[7:0]` | `ui_in[7:0]` | Serial byte bus — key and plaintext loaded here |
| `run` | `ui_in[0]` | 1 = play / advance notes, 0 = pause (same as stopwatch btn) |

| Signal | Pin | Description |
|---|---|---|
| `key_load` | `uio_in[0]` | High: shift `data_in` into 80-bit key register (10 bytes) |
| `pt_load` | `uio_in[1]` | High: shift `data_in` into 64-bit plaintext register (8 bytes) |
| `start` | `uio_in[2]` | Pulse high 1 clock to begin encryption |
| `byte_sel[2:0]` | `uio_in[6:4]` | Selects which ciphertext byte appears on `uo_out[7:1]` |

### Outputs

| Signal | Pin | Description |
|---|---|---|
| `pwm_out` | `uo_out[0]` | PWM audio output — connect to RC filter + speaker |
| `ct_byte[6:0]` | `uo_out[7:1]` | Ciphertext byte selected by `byte_sel` |
| `done` | `uio_out[0]` | High when encryption is complete and ciphertext is valid |

## Internal architecture

### PRESENT-80 cipher (serialised)

Processes **4 bits per clock** through the S-Box (16 cycles per round × 31 rounds ≈ 512 cycles total). Each round:

1. **AddRoundKey** — XOR 64-bit state with top 64 bits of key register.
2. **S-Box layer** — 16 nibbles substituted, serialised 4 bits/cycle.
3. **P-Layer** — 64-bit bitwise permutation, pure wiring (zero gate cost).
4. **Key schedule** — rotate 80-bit key left 61 bits, S-Box top nibble, XOR round counter into bits [19:15].

### Music engine

| Cipher bits | Music parameter |
|---|---|
| `[2:0]` | Note index into 8-entry pentatonic ROM (C4–E5) |
| `[7:4]` | Note duration (clock divider reload value) |
| `[11:8]` | Hamming weight ≤ 2 → chord (second PWM at ~fifth above) |

The `run` input gates note advancement, exactly mirroring the stopwatch start/pause button so the chip can be paused and resumed at will.

### Gate budget

| Block | Est. gates |
|---|---|
| State register (64-bit) | ~90 |
| Key register + schedule | ~110 |
| S-Box × 4 (serialised) | ~120 |
| P-Layer (wiring only) | 0 |
| Control FSM | ~80 |
| AddRoundKey XOR | ~70 |
| Pentatonic ROM | ~80 |
| Harmonic Detector | ~30 |
| PWM Generator | ~80 |
| Key/seed shift register | ~60 |
| Clock Divider | ~60 |
| Synthesis overhead | ~120 |
| **TOTAL** | **~900 / 1000** |

## Design rule compliance (Tiny Tapeout limits)

| Constraint | Limit | This design |
|---|---|---|
| Digital tile | 8×4 = 1400×500 µm ≈ 50 k cells | ~900 gates ✓ |
| IOs used | 24 max (8 in + 8 out + 8 bidir) | 8+8+1 ✓ |
| Metal 5 | Not allowed | Not used ✓ |
| IO clock bandwidth | ~50 MHz | Serial load, well within limit ✓ |
| Round-trip latency | ~20 ns | Latency-insensitive serial protocol ✓ |
