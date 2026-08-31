module Aes_mix_columns(
    input  wire [127:0] data_in,
    output wire [127:0] data_out
    );
    
    function [7:0] xtime;
        input [7:0] x;
        begin
            xtime = (x[7]) ? ((x << 1) ^ 8'h1b) : (x << 1);
        end
    endfunction
    
    function [7:0] gmul3;
        input [7:0] x;
        begin
            gmul3 = xtime(x) ^ x;
        end
    endfunction
    // ------------------------------------------------------------------------
    // Hàm 3: MixSingleColumn - Trộn 1 cột 32-bit (4 bytes [a0, a1, a2, a3])
    // Ma trận nhân hằng số AES:
    // [s0']   [02 03 01 01]   [a0]
    // [s1'] = [01 02 03 01] * [a1]
    // [s2']   [01 01 02 03]   [a2]
    // [s3']   [03 01 01 02]   [a3]
    // ------------------------------------------------------------------------
    function [31:0] MixSingleColumn;
        input [31:0] col;
        reg [7:0] a0, a1, a2, a3;
        begin
            a0 = col[31:24]; a1 = col[23:16]; a2 = col[15:8]; a3 = col[7:0];
            // Hàng 0: s0' = (02 * a0) ^ (03 * a1) ^ a2 ^ a3
            MixSingleColumn[31:24] = xtime(a0) ^  gmul3(a1)  ^  a2         ^  a3;
            // Hàng 1: s1' = a0 ^ (02 * a1) ^ (03 * a2) ^ a3
            MixSingleColumn[23:16] = a0        ^  xtime(a1)  ^  gmul3(a2)  ^  a3;
            // Hàng 2: s2' = a0 ^ a1 ^ (02 * a2) ^ (03 * a3)
            MixSingleColumn[15:8]  = a0        ^  a1         ^  xtime(a2)  ^  gmul3(a3);
            // Hàng 3: s3' = (03 * a0) ^ a1 ^ a2 ^ (02 * a3)
            MixSingleColumn[7:0]   = gmul3(a0) ^  a1         ^  a2         ^  xtime(a3);
        end
    endfunction
    
    assign data_out[127:96] = MixSingleColumn(data_in[127:96]); // Trộn Cột 0 (Byte 0->3)
    assign data_out[95:64]  = MixSingleColumn(data_in[95:64]);  // Trộn Cột 1 (Byte 4->7)
    assign data_out[63:32]  = MixSingleColumn(data_in[63:32]);  // Trộn Cột 2 (Byte 8->11)
    assign data_out[31:0]   = MixSingleColumn(data_in[31:0]);   // Trộn Cột 3 (Byte 12->15)   
endmodule
