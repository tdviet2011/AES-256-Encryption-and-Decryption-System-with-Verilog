// ============================================================================
// Module : aes256_enc_dec_top
// Description : This module selects the operating mode: Encryption or Decryption.
//
// Mode selection signal:
//   mode = 1'b0 : Encryption (Data_in = Plaintext  --> Data_out = Ciphertext)
//   mode = 1'b1 : Decryption (Data_in = Ciphertext --> Data_out = Plaintext)
// ============================================================================
module aes256_enc_dec_top (
    input  wire         clk,          // clock signal 
    input  wire         reset,        // Reset signal (Active LOW)
    input  wire         start,        // Active signal
    input  wire         mode,         // 0: Encrypt, 1: Decrypt
    input  wire [255:0] key,          // key 256-bit
    input  wire [127:0] data_in,      // input signal (Plaintext hoặc Ciphertext)

    output wire [127:0] data_out,     // output signal (Ciphertext hoặc Plaintext)
    output wire         done          // Indicates completion.
);

    // ------------------------------------------------------------------------
    // Tín hiệu nội bộ nối tới khối Mã hóa
    // ------------------------------------------------------------------------
    wire         enc_start;
    wire [127:0] enc_ciphertext;
    wire         enc_done;

    // ------------------------------------------------------------------------
    // Tín hiệu nội bộ nối tới khối Giải mã
    // ------------------------------------------------------------------------
    wire         dec_start;
    wire [127:0] dec_plaintext;
    wire         dec_done;

    // ------------------------------------------------------------------------
    // Bộ giải mã tín hiệu kích hoạt (Demux Start)
    // ------------------------------------------------------------------------
    assign enc_start = (mode == 1'b0) ? start : 1'b0;
    assign dec_start = (mode == 1'b1) ? start : 1'b0;

    // ------------------------------------------------------------------------
    // 1. Instantiation Khối Mã hóa (Encryption Core)
    // ------------------------------------------------------------------------
    Aes256_FSM u_enc_top (
        .clk        (clk),
        .reset      (reset),
        .start      (enc_start),
        .key        (key),
        .plaintext  (data_in),
        .ciphertext (enc_ciphertext),
        .done       (enc_done)
    );

    // ------------------------------------------------------------------------
    // 2. Instantiation Khối Giải mã (Decryption Core)
    // ------------------------------------------------------------------------
    Aes256_dec_FSM u_dec_top (
        .clk        (clk),
        .reset      (reset),
        .start      (dec_start),
        .key        (key),
        .ciphertext (data_in),
        .plaintext  (dec_plaintext),
        .done       (dec_done)
    );

    // ------------------------------------------------------------------------
    // Bộ lựa chọn đầu ra (Multiplexer Output)
    // ------------------------------------------------------------------------
    assign data_out = (mode == 1'b0) ? enc_ciphertext : dec_plaintext;
    assign done     = (mode == 1'b0) ? enc_done       : dec_done;

endmodule