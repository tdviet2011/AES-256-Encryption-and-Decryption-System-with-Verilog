`timescale 1ns / 1ps

module aes_inv_mix_columns (
    input  wire [127:0] data_in,
    output wire [127:0] data_out
);
    // Nhân 2
    function [7:0] gmul2;
        input [7:0] x;
        begin
            gmul2 = (x[7]) ? ((x << 1) ^ 8'h1b) : (x << 1);
        end
    endfunction

    // Nhân 4, 8 bằng cách nhân 2 liên tiếp
    function [7:0] gmul4; input [7:0] x; begin gmul4 = gmul2(gmul2(x)); end endfunction
    function [7:0] gmul8; input [7:0] x; begin gmul8 = gmul2(gmul4(x)); end endfunction

    // Phép nhân Galois cho 解码 (09, 0B, 0D, 0E)
    function [7:0] gmul9;  input [7:0] x; begin gmul9  = gmul8(x) ^ x; end endfunction
    function [7:0] gmul11; input [7:0] x; begin gmul11 = gmul8(x) ^ gmul2(x) ^ x; end endfunction
    function [7:0] gmul13; input [7:0] x; begin gmul13 = gmul8(x) ^ gmul4(x) ^ x; end endfunction
    function [7:0] gmul14; input [7:0] x; begin gmul14 = gmul8(x) ^ gmul4(x) ^ gmul2(x); end endfunction
    // ------------------------------------------------------------------------
    // Hàm 4: InvMixSingleColumn - Trộn ngược 1 cột 32-bit (4 bytes [a0, a1, a2, a3])
    // Ma trận nghịch đảo AES:
    // [s0']   [14 11 13  9]   [a0]
    // [s1'] = [ 9 14 11 13] * [a1]
    // [s2']   [13  9 14 11]   [a2]
    // [s3']   [11 13  9 14]   [a3]
    // ------------------------------------------------------------------------
    function [31:0] InvMixSingleColumn;
        input [31:0] col;
        reg [7:0] a0, a1, a2, a3;
        begin
            a0 = col[31:24]; a1 = col[23:16]; a2 = col[15:8]; a3 = col[7:0];
            InvMixSingleColumn[31:24] = gmul14(a0) ^ gmul11(a1) ^ gmul13(a2) ^ gmul9(a3);
            InvMixSingleColumn[23:16] = gmul9(a0)  ^ gmul14(a1) ^ gmul11(a2) ^ gmul13(a3);
            InvMixSingleColumn[15:8]  = gmul13(a0) ^ gmul9(a1)  ^ gmul14(a2) ^ gmul11(a3);
            InvMixSingleColumn[7:0]   = gmul11(a0) ^ gmul13(a1) ^ gmul9(a2)  ^ gmul14(a3);
        end
    endfunction

    assign data_out[127:96] = InvMixSingleColumn(data_in[127:96]);
    assign data_out[95:64]  = InvMixSingleColumn(data_in[95:64]);
    assign data_out[63:32]  = InvMixSingleColumn(data_in[63:32]);
    assign data_out[31:0]   = InvMixSingleColumn(data_in[31:0]);
endmodule