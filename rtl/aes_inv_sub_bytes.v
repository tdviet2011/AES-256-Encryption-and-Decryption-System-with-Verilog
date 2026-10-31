`timescale 1ns / 1ps

module aes_inv_sub_bytes (
    input  wire [127:0] data_in,
    output wire [127:0] data_out
);
    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : inv_sbox_loop
            aes_inv_sbox u_inv_sbox (
                .data_in (data_in[i*8 +: 8]),
                .data_out(data_out[i*8 +: 8])
            );
        end
    endgenerate
endmodule