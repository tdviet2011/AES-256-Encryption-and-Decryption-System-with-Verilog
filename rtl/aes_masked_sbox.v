`timescale 1ns / 1ps
// ============================================================================
// Module : aes_masked_sbox   (S-box co mat na, dung bang tinh lai - "table recomputation")
//
// Y TUONG: bang tra duoc tinh lai moi lan ma hoa, voi mat na ngau nhien moi:
//              T[a] = S[a ^ mask_in] ^ mask_out
//          Khi tra bang voi dia chi (x ^ mask_in) ta nhan duoc S[x] ^ mask_out.
//          => gia tri THAT S[x] khong bao gio xuat hien o bat ky day nao.
//
// VI SAO DUNG BANG (RAM) MA KHONG DUNG LOGIC TO HOP MASKED:
//   Masking Boolean tren logic to hop CMOS/FPGA bi ro ri bac 1 vi GLITCH
//   (Mangard et al. 2005): cong XOR/AND chuyen trang thai nhieu lan trong 1 chu ky,
//   so lan chuyen phu thuoc gia tri that -> ro ri du da co mat na.
//   Phep tra bang la truy cap bo nho, phan PHI TUYEN khong nam trong cay logic
//   to hop nen gan nhu khong co glitch -> an toan hon nhieu trong thuc te.
//   (Giai phap "chuan vang" hien nay la Threshold Implementation / DOM, chong
//    glitch bang chung minh toan hoc; xem ghi chu gioi han o aes_masked_core.v)
//
// GHI CHU TINH LAI BANG:
//   - Vong lap chay cnt = 0..255, ghi mem[cnt ^ mask_in] <= S[cnt] ^ mask_out.
//   - S[cnt] duoc tinh tu S-box THUAN (to hop) nhung dia chi cnt la bo dem CONG KHAI,
//     khong lien quan khoa -> khong co gi de ro ri o buoc nay.
//   - Mat 256 chu ky / lan ma hoa. Day la gia phai tra cua masking.
//
// SYNTHESIS: doc bat dong bo (assign dout = mem[addr]) -> Vivado suy ra
//   distributed RAM (LUTRAM) 256x8. Neu muon dung Block RAM thi phai doi sang
//   doc dong bo va them 1 tang pipeline o aes_masked_core.
// ============================================================================
module aes_masked_sbox (
    input  wire       clk,
    input  wire       reset,       // Active LOW
    input  wire       load,        // 1 chu ky: bat dau tinh lai bang
    input  wire       inv,         // 0 = S-box thuan, 1 = S-box nghich (giai ma)
    input  wire [7:0] mask_in,     // mi
    input  wire [7:0] mask_out,    // mo
    output reg        ready,       // 1 = bang da san sang
    input  wire [7:0] addr,
    output wire [7:0] dout
);
    reg [7:0] mem [0:255];
    reg [8:0] cnt;                 // 9 bit: bit[8] = da xong

    wire [7:0] s_fwd, s_inv;
    Aes_Sbox     u_sbox     (.data_in(cnt[7:0]), .data_out(s_fwd));
    aes_inv_sbox u_inv_sbox (.data_in(cnt[7:0]), .data_out(s_inv));
    wire [7:0] sval = inv ? s_inv : s_fwd;

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            cnt   <= 9'd0;
            ready <= 1'b0;
        end else if (load) begin
            cnt   <= 9'd0;
            ready <= 1'b0;         // trong chu ky nay chua ghi -> mask_in/out kip on dinh
        end else if (!cnt[8]) begin
            mem[cnt[7:0] ^ mask_in] <= sval ^ mask_out;
            cnt <= cnt + 1'b1;
            if (cnt == 9'd255) ready <= 1'b1;
        end
    end

    assign dout = mem[addr];
endmodule
