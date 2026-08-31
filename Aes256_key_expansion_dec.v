`timescale 1ns / 1ps

// ============================================================================
// Module : aes256_key_expansion_dec
// Mô tả  : Khối Key Expansion cho bộ Giải Mã (Decryption).
//          Tái sử dụng khối aes256_key_expansion gốc và đảo ngược chỉ số khóa.
// ============================================================================
module aes256_key_expansion_dec (
    input  wire         clk,
    input  wire         reset,
    input  wire         start,            // Xung kích hoạt sinh khóa
    input  wire [255:0] key_in,           // Chìa khóa gốc 256-bit
    input  wire [3:0]   dec_round_num,    // Số vòng FSM Giải Mã yêu cầu (0 -> 14)
    
    output wire [127:0] dec_round_key,    // Khóa vòng đã bị đảo ngược trả về cho FSM Giải mã
    output wire         ready             // Cờ báo đã tính xong toàn bộ 15 Round Keys
);

    // Dây chuyển đổi chỉ số vòng: Khi dec_round_num = 0 -> lấy enc_round_num = 14
    wire [3:0] enc_round_num;
    assign enc_round_num = 4'd14 - dec_round_num;

    // Gọi lại (Instantiate) module Key Expansion chuẩn đã viết trước đó
    Aes256_key_expansion_FSM u_key_expansion_core (
        .clk        (clk),
        .reset      (reset),
        .key_mode   (start),
        .key_in     (key_in),
        .round_num  (enc_round_num),      // Truyền chỉ số đã đảo ngược vào đây
        .round_key  (dec_round_key),      // Nhận về khóa tương ứng
        .flag      (ready)
    );

endmodule