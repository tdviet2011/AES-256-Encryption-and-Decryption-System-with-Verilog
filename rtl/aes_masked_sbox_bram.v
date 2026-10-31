`timescale 1ns / 1ps
// ============================================================================
// Module : aes_masked_sbox_bram
//   Giong het aes_masked_sbox ve CHUC NANG (bang S-box co mat na, tinh lai
//   moi lan ma hoa), chi khac CACH DOC:
//       aes_masked_sbox       : doc BAT DONG BO  -> Vivado suy ra distributed
//                               RAM (LUTRAM), ton LUT, khong ton BRAM
//       aes_masked_sbox_bram  : doc DONG BO      -> Vivado suy ra Block RAM,
//                               ton 1 BRAM (18Kb), gan nhu khong ton LUT
//
// KHI NAO DUNG BAN NAO:
//   - Thiet ke da het LUT nhung con thua BRAM  -> dung ban BRAM nay
//   - Thiet ke da het BRAM (vi du dung cho buffer du lieu) -> dung ban LUTRAM
//   - Bang 256x8 = 2048 bit, dung het 1 BRAM 18Kb la LANG PHI (~11%), nhung
//     doi lai tiet kiem khoang 100-150 LUT.
//
// CAI GIA: doc dong bo -> ket qua ve CHAM 1 CHU KY.
//   Phai bat tham so SYNC_RAM=1 o aes_masked_core_mk de no them 1 tang pipeline
//   trong pha SubBytes (16 chu ky -> 17 chu ky moi vong, tong +14 chu ky/block).
//   KHONG duoc dung module nay voi SYNC_RAM=0: ket qua se SAI.
// ============================================================================
module aes_masked_sbox_bram (
    input  wire       clk,
    input  wire       reset,       // Active LOW
    input  wire       load,
    input  wire       inv,
    input  wire [7:0] mask_in,
    input  wire [7:0] mask_out,
    output reg        ready,
    input  wire [7:0] addr,
    output wire [7:0] dout
);
    reg [7:0] mem [0:255];
    reg [7:0] dout_r;
    reg [8:0] cnt;

    wire [7:0] s_fwd, s_inv;
    Aes_Sbox     u_sbox     (.data_in(cnt[7:0]), .data_out(s_fwd));
    aes_inv_sbox u_inv_sbox (.data_in(cnt[7:0]), .data_out(s_inv));
    wire [7:0] sval = inv ? s_inv : s_fwd;

    // Bo dem / co bao: co reset bat dong bo
    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            cnt   <= 9'd0;
            ready <= 1'b0;
        end else if (load) begin
            cnt   <= 9'd0;
            ready <= 1'b0;
        end else if (!cnt[8]) begin
            cnt <= cnt + 1'b1;
            if (cnt == 9'd255) ready <= 1'b1;
        end
    end

    // Phan BO NHO: KHONG co reset -> dieu kien bat buoc de Vivado suy ra BRAM.
    // (Neu them reset vao day thi tool se bo ve LUTRAM hoac thanh ghi roi.)
    always @(posedge clk) begin
        if (!cnt[8] && reset && !load) mem[cnt[7:0] ^ mask_in] <= sval ^ mask_out;
        dout_r <= mem[addr];
    end

    assign dout = dout_r;
endmodule
