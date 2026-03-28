`default_nettype none
`timescale 1ns / 1ps
 
module tb ();
 
  // Dump signals to FST
  initial begin
    $display("Force dumping data now");
    $dumpfile("tb.fst");
    $dumpvars(0, tb);
    #1;
  end
 
  // Inputs and outputs
  reg clk;
  reg rst_n;
  reg ena;
  reg [7:0] ui_in;
  reg [7:0] uio_in;
  wire [7:0] uo_out;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;
 
`ifdef GL_TEST
  wire VPWR = 1'b1;
  wire VGND = 1'b0;
`endif
 
  // Instantiate CryptoMuse design
  tt_um_cryptomuse
`ifndef GL_TEST
    #(
        .CLOCKS_PER_NOTE(24'd15)   // Short note duration for fast simulation
    )
`endif
  user_project (
`ifdef GL_TEST
      .VPWR   (VPWR),
      .VGND   (VGND),
`endif
      .ui_in  (ui_in),
      .uo_out (uo_out),
      .uio_in (uio_in),
      .uio_out(uio_out),
      .uio_oe (uio_oe),
      .ena    (ena),
      .clk    (clk),
      .rst_n  (rst_n)
  );
 
endmodule
