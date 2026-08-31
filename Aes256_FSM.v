`timescale 1ns / 1ps

module Aes256_FSM (
    input               clk,          // Xung xung nhịp hệ thống
    input               reset,        // Tín hiệu Reset (Active High)
    input               start,        // Tín hiệu kích hoạt bắt đầu mã hóa
    input   [255:0]     key,          // Chìa khóa bí mật 256-bit
    input   [127:0]     plaintext,    // Dữ liệu đầu vào 128-bit

    output  [127:0] ciphertext,   // Dữ liệu mã hóa đầu ra 128-bit
    output           done          // Báo hiệu mã hóa đã hoàn thành
);

    // ------------------------------------------------------------------------
    // 1. Khai báo các dây liên kết nội bộ (Internal Wires)
    // ------------------------------------------------------------------------
    wire [3:0]   wire_round_num;      // Số vòng FSM yêu cầu (0 -> 14)
    wire [127:0] wire_round_key;      // Khóa vòng tương ứng trả về từ Key Expansion
    wire         wire_key_ready;      // Cờ báo khối Key Expansion đã sinh khóa xong
    reg          cipher_start;        // Tín hiệu kích hoạt FSM Mã hóa

    // ------------------------------------------------------------------------
    // 2. Tự động chuyển tiếp điều khiển (Control Logic)
    // ------------------------------------------------------------------------
    // FSM Cipher sẽ bắt đầu chạy ngay khi khối Key Expansion báo đã tạo xong khóa
    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            cipher_start <= 1'b0;
        end else begin
            if (wire_key_ready) begin
                cipher_start <= 1'b1;  // Cho phép Cipher chạy
            end else begin
                cipher_start <= 1'b0;
            end
        end
    end

    // ------------------------------------------------------------------------
    // 3. Khởi tạo & Kết nối Khối Mở rộng Khóa (Key Expansion)
    // ------------------------------------------------------------------------
    Aes256_key_expansion_FSM u_key_expansion (
        .clk        (clk),
        .reset      (reset),              // Nhận xung start từ Top
        .key_in     (key),                // Nhận key 256-bit từ Top
        .round_num  (wire_round_num),     // Nhận yêu cầu vòng từ Cipher FSM
        .key_mode   (start),
        .round_key  (wire_round_key),     // Trả khóa vòng 128-bit sang Cipher FSM
        .flag      (wire_key_ready)      // Báo tín hiệu hoàn tất sinh khóa
    );

    // ------------------------------------------------------------------------
    // 4. Khởi tạo & Kết nối Khối Mã hóa FSM (Cipher FSM)
    //    (Bên trong module này đã tự kết nối SubBytes, ShiftRows, MixColumns)
    // ------------------------------------------------------------------------
    Aes_data_FSM u_cipher_fsm (
        .clk        (clk),
        .reset      (reset),
        .start      (cipher_start),       // Kích hoạt khi Key Expansion hoàn tất
        .plaintext  (plaintext),          // Nhận plaintext từ Top
        .round_key  (wire_round_key),     // Nhận khóa vòng từ Key Expansion
        
        .round_num  (wire_round_num),     // Xuất số vòng yêu cầu sang Key Expansion
        .ciphertext (ciphertext),         // Xuất kết quả ciphertext ra Top
        .done       (done)                // Xuất cờ hoàn thành ra Top
    );

endmodule