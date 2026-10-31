module Aes_shift_rows (
    input  wire [127:0] data_in,
    output wire [127:0] data_out
);

    // Layout ma trận 4x4 (Mỗi Col chứa 4 Bytes, index từ 0 -> 15):
    // [0] [4] [8]  [12]   <- Row 0 (Không dịch)
    // [1] [5] [9]  [13]   <- Row 1 (Dịch trái 1)
    // [2] [6] [10] [14]   <- Row 2 (Dịch trái 2)
    // [3] [7] [11] [15]   <- Row 3 (Dịch trái 3)

    // Row 0: Giữ nguyên
    assign data_out[127:120] = data_in[127:120]; // Byte 0
    assign data_out[95:88]   = data_in[95:88];   // Byte 4
    assign data_out[63:56]   = data_in[63:56];   // Byte 8
    assign data_out[31:24]   = data_in[31:24];   // Byte 12

    // Row 1: Shift Left 1 Position (1 -> 5 -> 9 -> 13 -> 1)
    assign data_out[119:112] = data_in[87:80];   // Byte 5 -> vị trí Byte 1
    assign data_out[87:80]   = data_in[55:48];   // Byte 9 -> vị trí Byte 5
    assign data_out[55:48]   = data_in[23:16];   // Byte 13 -> vị trí Byte 9
    assign data_out[23:16]   = data_in[119:112]; // Byte 1 -> vị trí Byte 13

    // Row 2: Shift Left 2 Positions (2 -> 10, 6 -> 14...)
    assign data_out[111:104] = data_in[47:40];   // Byte 10 -> vị trí Byte 2
    assign data_out[79:72]   = data_in[15:8];    // Byte 14 -> vị trí Byte 6
    assign data_out[47:40]   = data_in[111:104]; // Byte 2 -> vị trí Byte 10
    assign data_out[15:8]    = data_in[79:72];   // Byte 6 -> vị trí Byte 14

    // Row 3: Shift Left 3 Positions (3 -> 15, 7 -> 3...)
    assign data_out[103:96]  = data_in[7:0];     // Byte 15 -> vị trí Byte 3
    assign data_out[71:64]   = data_in[103:96];  // Byte 3 -> vị trí Byte 7
    assign data_out[39:32]   = data_in[71:64];   // Byte 7 -> vị trí Byte 11
    assign data_out[7:0]     = data_in[39:32];   // Byte 11 -> vị trí Byte 15

endmodule