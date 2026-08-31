module Aes256_dec_FSM (
    input  wire         clk,
    input  wire         reset,
    input  wire         start,
    input  wire [255:0] key,
    input  wire [127:0] ciphertext,
    output wire [127:0] plaintext,
    output wire         done
);
    wire [3:0]   wire_dec_round_num;
    wire [127:0] wire_dec_round_key;
    wire         wire_key_ready;
    reg          dec_start;

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            dec_start <= 1'b0;
        end else begin
            if (wire_key_ready) begin
                dec_start <= 1'b1;
            end else begin
                dec_start <= 1'b0;
            end
        end
    end

    // Khối Mở Rộng Khóa Giải Mã (Đảo thứ tự Round Key)
    aes256_key_expansion_dec u_key_expansion_dec (
        .clk           (clk),
        .reset         (reset),
        .start         (start),
        .key_in        (key),
        .dec_round_num (wire_dec_round_num),
        .dec_round_key (wire_dec_round_key),
        .ready         (wire_key_ready)
    );

    // Khối FSM Giải Mã
    aes256_data_dec_fsm u_decipher_fsm (
        .clk           (clk),
        .reset         (reset),
        .start         (dec_start),
        .ciphertext    (ciphertext),
        .round_key     (wire_dec_round_key),
        .dec_round_num (wire_dec_round_num),
        .plaintext     (plaintext),
        .done          (done)
    );
endmodule