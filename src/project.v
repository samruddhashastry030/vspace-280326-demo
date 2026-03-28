`default_nettype none
 
// ============================================================
//  CryptoMuse — PRESENT-Keyed Generative Music Engine
//  Tiny Tapeout submission
//
//  Authors : Samruddha S Shastry, Prasoon Mishra, Varun Shankar
//  Standard: PRESENT-80 (ISO/IEC 29192-2)
//
//  Pin map
//    ui_in[7:0]   serial data bus (key / plaintext bytes, MSB first)
//    uio_in[0]    key_load  : shift ui_in byte into key register
//    uio_in[1]    pt_load   : shift ui_in byte into plaintext register
//    uio_in[2]    start     : pulse 1 clk to begin encryption
//    uio_in[6:4]  byte_sel  : selects which ciphertext byte is on uo_out
//    ui_in[0]     run       : 1=play/advance notes, 0=pause
//    uo_out[0]    pwm_out   : audio PWM
//    uo_out[7:1]  ct_byte   : selected ciphertext byte (read-back)
//    uio_out[0]   done      : high when encryption is complete
// ============================================================
 
module tt_um_cryptomuse #(
    parameter CLOCKS_PER_NOTE = 24'd9_999_999
)(
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);
 
    assign uio_oe      = 8'hFF;
    assign uio_out[7:1] = 7'b0;
 
    wire        key_load = uio_in[0];
    wire        pt_load  = uio_in[1];
    wire        start    = uio_in[2];
    wire [2:0]  byte_sel = uio_in[6:4];
    wire        run      = ui_in[0];
 
    wire        pwm_out;
    wire        done;
    wire [63:0] ciphertext;
 
    wire [7:0] ct_byte = ciphertext[byte_sel*8 +: 8];
 
    assign uo_out     = {ct_byte[6:0], pwm_out};
    assign uio_out[0] = done;
 
    cryptomuse_core #(.CLOCKS_PER_NOTE(CLOCKS_PER_NOTE)) core (
        .clk        (clk),
        .rst_n      (rst_n & ena),
        .data_in    (ui_in),
        .key_load   (key_load),
        .pt_load    (pt_load),
        .start      (start),
        .run        (run),
        .ciphertext (ciphertext),
        .pwm_out    (pwm_out),
        .done       (done)
    );
 
endmodule
 
 
// ============================================================
//  Core: PRESENT-80 cipher + Generative Music Engine
// ============================================================
module cryptomuse_core #(
    parameter CLOCKS_PER_NOTE = 24'd9_999_999
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  data_in,
    input  wire        key_load,
    input  wire        pt_load,
    input  wire        start,
    input  wire        run,
    output reg  [63:0] ciphertext,
    output wire        pwm_out,
    output reg         done
);
 
    // ── Registers ─────────────────────────────────────────────
    reg [79:0] key_reg;
    reg [63:0] pt_reg;
    reg [63:0] state;
    reg [79:0] key_work;
 
    // ── FSM states ─────────────────────────────────────────────
    localparam S_IDLE      = 3'd0;
    localparam S_ADD_KEY   = 3'd1;
    localparam S_SBOX      = 3'd2;
    localparam S_PLAYER    = 3'd3;
    localparam S_KEY_SCHED = 3'd4;
    localparam S_FINISH    = 3'd5;
 
    reg [2:0]  fsm;
    reg [4:0]  round;
    reg [3:0]  nibble_cnt;
 
    // ── Serial key load ────────────────────────────────────────
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)        key_reg <= 80'b0;
        else if (key_load) key_reg <= {key_reg[71:0], data_in};
    end
 
    // ── Serial plaintext load ──────────────────────────────────
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)       pt_reg <= 64'b0;
        else if (pt_load) pt_reg <= {pt_reg[55:0], data_in};
    end
 
    // ── S-Box ──────────────────────────────────────────────────
    function [3:0] sbox;
        input [3:0] x;
        case (x)
            4'h0: sbox=4'hC; 4'h1: sbox=4'h5;
            4'h2: sbox=4'h6; 4'h3: sbox=4'hB;
            4'h4: sbox=4'h9; 4'h5: sbox=4'h0;
            4'h6: sbox=4'hA; 4'h7: sbox=4'hD;
            4'h8: sbox=4'h3; 4'h9: sbox=4'hE;
            4'hA: sbox=4'hF; 4'hB: sbox=4'h8;
            4'hC: sbox=4'h4; 4'hD: sbox=4'h7;
            4'hE: sbox=4'h1; 4'hF: sbox=4'h2;
            default: sbox=4'h0;
        endcase
    endfunction
 
    // ── P-Layer ────────────────────────────────────────────────
    function [63:0] p_layer;
        input [63:0] s;
        integer i;
        reg [63:0] o;
        begin
            o = 64'b0;
            for (i=0; i<64; i=i+1)
                o[(i/4) + 16*(i%4)] = s[i];
            p_layer = o;
        end
    endfunction
 
    // ── Key Schedule ───────────────────────────────────────────
    function [79:0] key_sched;
        input [79:0] k;
        input [4:0]  rnd;
        reg [79:0] k2;
        begin
            k2         = {k[18:0], k[79:19]};   // rotate left 61
            k2[79:76]  = sbox(k2[79:76]);         // S-box top nibble
            k2[19:15]  = k2[19:15] ^ rnd;         // XOR round counter
            key_sched  = k2;
        end
    endfunction
 
    // ── Encryption FSM ─────────────────────────────────────────
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fsm        <= S_IDLE;
            round      <= 5'd1;
            nibble_cnt <= 4'd0;
            state      <= 64'b0;
            key_work   <= 80'b0;
            ciphertext <= 64'b0;
            done       <= 1'b0;
        end else begin
            case (fsm)
 
                S_IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        state      <= pt_reg;
                        key_work   <= key_reg;
                        round      <= 5'd1;
                        nibble_cnt <= 4'd0;
                        fsm        <= S_ADD_KEY;
                    end
                end
 
                // AddRoundKey: XOR state with top 64 bits of key
                S_ADD_KEY: begin
                    state <= state ^ key_work[79:16];
                    fsm   <= S_SBOX;
                end
 
                // S-Box layer: one nibble per cycle, 16 cycles
                S_SBOX: begin
                    state[nibble_cnt*4 +: 4] <= sbox(state[nibble_cnt*4 +: 4]);
                    if (nibble_cnt == 4'd15) begin
                        nibble_cnt <= 4'd0;
                        if (round == 5'd31)
                            fsm <= S_KEY_SCHED;  // skip P-layer, go to final key sched
                        else
                            fsm <= S_PLAYER;
                    end else begin
                        nibble_cnt <= nibble_cnt + 4'd1;
                    end
                end
 
                // P-Layer
                S_PLAYER: begin
                    state <= p_layer(state);
                    fsm   <= S_KEY_SCHED;
                end
 
                // Key Schedule
                S_KEY_SCHED: begin
                    key_work <= key_sched(key_work, round);
                    if (round == 5'd31)
                        fsm <= S_FINISH;        // final round: next is whitening
                    else begin
                        round <= round + 5'd1;
                        fsm   <= S_ADD_KEY;
                    end
                end
 
                // Final whitening key XOR then done
                S_FINISH: begin
                    ciphertext <= state ^ key_work[79:16];
                    done       <= 1'b1;
                    fsm        <= S_IDLE;
                end
 
                default: fsm <= S_IDLE;
            endcase
        end
    end
 
    // ── Note frequency lookup (PWM period at 10 MHz) ──────────
    reg [15:0] pwm_period;
    always @(*) begin
        case (ciphertext[2:0])
            3'd0: pwm_period = 16'd19084;  // C4  262 Hz
            3'd1: pwm_period = 16'd17007;  // D4  294 Hz
            3'd2: pwm_period = 16'd15152;  // E4  330 Hz
            3'd3: pwm_period = 16'd12755;  // G4  392 Hz
            3'd4: pwm_period = 16'd11364;  // A4  440 Hz
            3'd5: pwm_period = 16'd9560;   // C5  523 Hz
            3'd6: pwm_period = 16'd8518;   // D5  587 Hz
            3'd7: pwm_period = 16'd7588;   // E5  659 Hz
        endcase
    end
 
    // ── PWM melody generator ───────────────────────────────────
    reg [15:0] pwm_cnt;
    reg        pwm_reg;
 
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pwm_cnt <= 16'b0;
            pwm_reg <= 1'b0;
        end else if (done) begin
            if (pwm_cnt >= pwm_period) begin
                pwm_cnt <= 16'b0;
                pwm_reg <= ~pwm_reg;
            end else begin
                pwm_cnt <= pwm_cnt + 16'd1;
            end
        end else begin
            pwm_cnt <= 16'b0;
            pwm_reg <= 1'b0;
        end
    end
 
    // ── Note clock divider ─────────────────────────────────────
    reg [23:0] note_counter;
    reg [63:0] next_pt;
 
    wire note_tick = (note_counter == CLOCKS_PER_NOTE);
 
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            note_counter <= 24'b0;
            next_pt      <= 64'b0;
        end else if (done && run) begin
            if (note_tick) begin
                note_counter <= 24'b0;
                next_pt      <= next_pt + 64'd1;
            end else begin
                note_counter <= note_counter + 24'd1;
            end
        end
    end
 
    // ── Chord detection (low Hamming weight on bits [11:8]) ───
    wire [3:0] harm_bits   = ciphertext[11:8];
    wire chord_active =
        (harm_bits == 4'b0000) | (harm_bits == 4'b0001) |
        (harm_bits == 4'b0010) | (harm_bits == 4'b0100) |
        (harm_bits == 4'b1000) | (harm_bits == 4'b0011) |
        (harm_bits == 4'b0101) | (harm_bits == 4'b1001) |
        (harm_bits == 4'b0110) | (harm_bits == 4'b1010) |
        (harm_bits == 4'b1100);
 
    wire [15:0] chord_period = {1'b0, pwm_period[15:1]};
    reg [15:0]  chord_cnt;
    reg         chord_reg;
 
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            chord_cnt <= 16'b0;
            chord_reg <= 1'b0;
        end else if (done && chord_active) begin
            if (chord_cnt >= chord_period) begin
                chord_cnt <= 16'b0;
                chord_reg <= ~chord_reg;
            end else begin
                chord_cnt <= chord_cnt + 16'd1;
            end
        end else begin
            chord_cnt <= 16'b0;
            chord_reg <= 1'b0;
        end
    end
 
    assign pwm_out = pwm_reg | (chord_active & chord_reg);
 
endmodule
