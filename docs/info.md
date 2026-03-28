<!---
This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.
You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

The CryptoMuse is a PRESENT-80 Cipher-Keyed Generative Music Engine that produces cryptographically unpredictable melodies through a PWM audio output. The design is broken down into four main hardware modules:

+ **The PRESENT-80 Cipher Engine:** The core cryptographic block implements the ISO/IEC 29192-2 lightweight cipher standard. To stay within the gate budget, the S-Box is serialised, processing only 4 bits per clock cycle rather than all 64 bits in parallel. Over 31 rounds — each performing AddRoundKey, S-Box substitution, and a bitwise P-Layer permutation (pure wiring, zero gate cost) — the engine transforms a 64-bit plaintext under an 80-bit secret key into a ciphertext. One complete encryption takes approximately 512 clock cycles.

+ **The Key & Plaintext Loader:** The 80-bit key and 64-bit plaintext are loaded serially through `ui_in[7:0]`, one byte at a time (MSB first). Holding `uio_in[0]` HIGH shifts each byte into the key register (10 bytes total). Holding `uio_in[1]` HIGH shifts each byte into the plaintext register (8 bytes total). A single clock pulse on `uio_in[2]` starts encryption. The `uio_out[0]` done flag goes HIGH when the ciphertext is ready.

+ **The Generative Music Engine:** After each encryption completes, three slices of the 64-bit cipher state are decoded into music parameters. Bits `[2:0]` index into an 8-entry pentatonic scale ROM (C4 through E5), selecting the melody note. Bits `[7:4]` set the note duration. Bits `[11:8]` feed a Harmonic Collision Detector — when the Hamming weight of these bits is 2 or less, a second PWM channel activates simultaneously to form a chord interval.

+ **The PWM Generator & Clock Divider:** A 16-bit counter and comparator convert the selected pentatonic frequency into a square-wave PWM signal on `uo_out[0]`. A multi-stage clock divider controls how long each note is held before the cipher state advances to the next note. Counting is gated by `ui_in[0]`: when HIGH the melody plays and advances, when LOW the current note freezes on the output — exactly mirroring the stopwatch start/pause behaviour.

Because the cipher's avalanche effect guarantees that even a single bit change in the key scrambles the entire 64-bit output, changing the loaded key produces a completely different, unpredictable melody in real time.

## How to test

To physically test this chip once manufactured (or when using the Tiny Tapeout Commander app):

+ **Power & Clock:** Ensure the Tiny Tapeout board is powered and the system clock is set to 10 MHz.

+ **Reset:** Press the system reset button (pulling `rst_n` LOW) to clear all internal registers. The PWM output should be silent and the done flag LOW.

+ **Load a Key:** Using a microcontroller or DIP switches on `ui_in[7:0]`, shift in 10 bytes (MSB first) while holding `uio_in[0]` HIGH for each byte. This loads your 80-bit secret key.

+ **Load a Plaintext:** Shift in 8 bytes (MSB first) while holding `uio_in[1]` HIGH for each byte. Any 64-bit value works as the starting plaintext.

+ **Start Encryption:** Pulse `uio_in[2]` HIGH for one clock cycle. Wait approximately 512 cycles for `uio_out[0]` (done) to go HIGH.

+ **Play Music:** Flip Input Switch 0 (`ui_in[0]`) to the HIGH (ON) position. The PWM output on `uo_out[0]` will begin producing audible pentatonic tones through the RC filter and speaker.

+ **Pause:** Flip Input Switch 0 to the LOW (OFF) position. The current note freezes on the output.

+ **Resume:** Flip Input Switch 0 back HIGH to continue the melody from where it paused.

+ **Change Key:** Load a new key and re-trigger encryption. The melody will change completely — a live demonstration of the cryptographic avalanche effect.

+ **Hard Reset:** At any time, pressing the reset button will immediately clear all registers and silence the output.

+ **Read Back Ciphertext (optional):** Set `uio_in[6:4]` to a byte index (0–7) to read out the corresponding ciphertext byte on `uo_out[7:1]` for software verification against the official PRESENT-80 test vectors.

## External hardware

To use and hear the output of this project, you will need:

+ **Tiny Tapeout Demo Board** (or equivalent carrier board).
+ **RC Low-Pass Filter:** A 1 kΩ resistor and 100 nF capacitor connected between `uo_out[0]` and your audio output jack (cut-off frequency ≈ 1.6 kHz). This smooths the PWM square wave into a clean, audible tone.
+ **3.5 mm Audio Jack or Small Speaker** connected after the RC filter to produce sound.
+ **A DIP switch or push-button** connected to input pin 0 (`ui_in[0]`) to act as the Play/Pause toggle.
+ **A microcontroller or DIP switch bank** on `ui_in[7:0]` and `uio_in[7:0]` to load the key, plaintext, and control signals. A USB-UART adapter with a simple Python script is sufficient.
+ **An oscilloscope (optional)** to verify that the PWM frequencies match the expected pentatonic scale values (C4 = 262 Hz through E5 = 659 Hz).
