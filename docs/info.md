<!---
This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.
You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

CryptoMuse is a hardware music generator that uses cryptography as its creative engine. At its core is a fully serialised implementation of **PRESENT-80** (ISO/IEC 29192-2), one of the lightest block ciphers ever standardised, implemented as a 6-state FSM that processes one nibble per clock cycle through the S-box layer.

The design is broken down into three main hardware modules:

**PRESENT-80 Cipher Engine:**
The cipher accepts an 80-bit key and a 64-bit plaintext, both loaded serially over the `uio_in` and `ui_in` buses one byte at a time. Once the start pulse is received, the FSM executes 31 full rounds of PRESENT encryption — each round consisting of an AddRoundKey step, a 16-nibble S-box substitution layer, a bitwise P-layer permutation, and a key schedule update. After all 31 rounds, a final whitening key XOR is applied and the 64-bit ciphertext is latched. A done flag on `uio_out[0]` signals completion.

**Pentatonic Music Engine:**
Once encryption is complete, the 64-bit ciphertext is interpreted musically. The lowest 3 bits select one of eight notes from a pentatonic scale spanning C4 to E5 (262 Hz to 659 Hz). A PWM square wave generator running at the selected frequency is output on `uio_out[1]`. Bits [11:8] of the ciphertext are checked for low Hamming weight — when two or fewer bits are set, a second PWM oscillator running at an approximate musical fifth produces a chord alongside the melody note, mixing both signals at the output.

**Note Sequencer with Pause/Resume:**
A 24-bit counter driven by `ui_in[0]` (play/pause) advances the note sequence by counting `CLOCKS_PER_NOTE` ticks before triggering a new encryption. When `ui_in[0]` is LOW, the counter freezes, pausing the music. Setting it HIGH resumes playback from where it left off — mirroring the stopwatch-style interface.

## How to test

To physically test this chip once manufactured (or using the Tiny Tapeout Commander app):

**Basic Encryption Test:**
1. Power the Tiny Tapeout board and set the system clock to 10 MHz.
2. Press reset (`rst_n` LOW) to clear all internal registers.
3. Load an 80-bit key serially: assert `uio_in[0]` (key_load) HIGH and clock in 10 bytes on `ui_in[7:0]`, MSB first.
4. Load a 64-bit plaintext serially: assert `uio_in[1]` (pt_load) HIGH and clock in 8 bytes on `ui_in[7:0]`, MSB first.
5. Pulse `uio_in[2]` (start) HIGH for one clock cycle to begin encryption.
6. Poll `uio_out[0]` (done) — it will go HIGH after ~550 clock cycles when encryption is complete.
7. Read back the 64-bit ciphertext: set `uio_in[6:4]` (byte_sel) to 0–7 to select each byte and read `uo_out[7:0]`.

**Music Playback Test:**
1. After encryption completes, set `ui_in[0]` HIGH (play).
2. Connect `uio_out[1]` through an RC low-pass filter (10kΩ + 100nF) to a small speaker or piezo buzzer.
3. A pentatonic melody will play automatically. The note and chord change each time `CLOCKS_PER_NOTE` ticks elapse.
4. Set `ui_in[0]` LOW to pause the melody. Set it HIGH again to resume.

**Golden Vector Verification:**
Using the official PRESENT-80 test vectors (Bogdanov et al., 2007):
- PT=`0x0000000000000000`, KEY=`0x00000000000000000000` → CT=`0x5579C1387B228445`
- PT=`0xFFFFFFFFFFFFFFFF`, KEY=`0xFFFFFFFFFFFFFFFFFFFF` → CT=`0x3333DCD3213210D2`

## External hardware

To use this project you will need:

+ **Tiny Tapeout Demo Board** (or equivalent carrier board) with a 10 MHz clock source.
+ **Speaker or piezo buzzer** connected to `uio_out[1]` through a simple RC low-pass filter (10kΩ resistor + 100nF capacitor) to smooth the PWM square wave into an audible tone.
+ **DIP switch or push-button** connected to `ui_in[0]` to act as the Play/Pause toggle.
+ **Logic analyser or microcontroller** (optional) to load the key and plaintext serially and read back the ciphertext for verification.
