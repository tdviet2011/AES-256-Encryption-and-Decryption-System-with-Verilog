module Aes_sub_bytes (
    input  wire [127:0] data_in,
    output wire [127:0] data_out
);
    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin: sbox_loop
        Aes_Sbox u_sbox(
            .data_in (data_in[127-i*8 -: 8]),
            .data_out(data_out[127-i*8 -: 8])
        );
        end
    endgenerate

endmodule
