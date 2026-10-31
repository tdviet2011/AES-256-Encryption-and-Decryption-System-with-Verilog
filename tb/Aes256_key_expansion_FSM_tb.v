`timescale 1ns / 1ps

module tb_key_expansion;

reg         clk;
reg         reset;
reg         key_mode;
reg  [255:0] key_in;
reg  [3:0]  round_num;

wire [127:0] round_key;
wire         flag;

integer i;

//======================================================
// DUT
//======================================================
Aes256_key_expansion_FSM dut (
    .clk(clk),
    .reset(reset),
    .key_mode(key_mode),
    .key_in(key_in),
    .round_num(round_num),
    .round_key(round_key),
    .flag(flag)
);

//======================================================
// Clock
//======================================================
initial begin
    clk = 0;
    forever #5 clk = ~clk;
end

//======================================================
// Test
//======================================================
initial begin

    reset     = 0;
    key_mode  = 0;
    round_num = 0;
    key_in    = 0;

    #20;
    reset = 1;

    //--------------------------------------------------
    // AES-256 NIST Key
    //--------------------------------------------------
    key_in = 256'h603DEB1015CA71BE2B73AEF0857D77811F352C073B6108D72D9810A30914DFF4;

    #10;
    key_mode = 1;

    //--------------------------------------------------
    // Wait Key Expansion Done
    //--------------------------------------------------
    wait(flag == 1);

    #20;

    $display("");
    $display("==========================================");
    $display(" AES-256 ROUND KEYS");
    $display("==========================================");

    for(i=0;i<15;i=i+1) begin
        round_num = i;
        #10;
        $display("RK%0d = %032h", i, round_key);
    end

    $display("==========================================");

    #20;
    $finish;

end

endmodule