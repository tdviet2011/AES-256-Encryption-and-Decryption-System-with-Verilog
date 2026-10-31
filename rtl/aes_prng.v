`timescale 1ns / 1ps
// ============================================================================
// Module : aes_prng
// Nhiem vu: cap randomness cho mat na (mask) va cho thu tu tron (shuffle).
//
// !!! CANH BAO BAO MAT QUAN TRONG NHAT CUA CA THIET KE NAY !!!
//   LFSR *KHONG* phai nguon ngau nhien an toan. No la tuyen tinh: biet 32 bit
//   lien tiep la suy ra duoc toan bo day truoc/sau. Neu ke tan cong doan duoc
//   day mask, mat na bi go sach va moi lop chong DPA ben duoi tro thanh vo nghia.
//
//   LFSR o day CHI dong vai tro "khuech tan" (whitening). De dung that su phai:
//     - Cap seed tu nguon entropy VAT LY moi lan khoi dong (ring-oscillator TRNG,
//       hoac SoC/PS dua seed vao qua AXI) qua cong seed_en/seed_in.
//     - Tot hon nua: thay han khoi nay bang TRNG + DRBG (AES-CTR_DRBG / SHA-based).
//   Neu de seed co dinh (mac dinh ben duoi) thi day mask lap lai y nguyen moi lan
//   bat nguon -> coi nhu KHONG co masking.
//
// KET QUA DO DUOC (1000 trace mo phong, chup trang thai ngay sau AddRoundKey vong 0):
//   tuong quan HW(thanh ghi) vs HW(gia tri that) : -0.0065  (nguong nhieu 3-sigma = 0.095)
//        -> ban KHONG mask cho tuong quan = 1.0000, tuc la ro ri hoan toan.
//           Masking da triet tieu duoc chi so DPA chinh.
//   tuong quan theo TUNG BIT, gia tri lon nhat   :  0.1252  (ky vong nhieu ~0.101)
//        -> hoi cao hon nhieu thuan (~4 sigma). Nguyen nhan rat co kha nang la
//           16 byte mat na trong cung 1 lan ma hoa duoc lay tu cac dau ra LFSR
//           LIEN TIEP nen co tuong quan voi nhau. Day la bang chung thuc nghiem
//           cho thay PHAI thay LFSR bang TRNG + DRBG, khong phai chi la ly thuyet.
//
// Cau truc: 4 LFSR 32-bit doc lap, moi chu ky dich 8 buoc -> 32 bit/chu ky.
//   Dung 4 LFSR rieng (thay vi 1 LFSR dich 32 buoc) de do sau chuoi XOR chi la
//   8 muc -> khong pha timing khi chay 100 MHz tro len.
// ============================================================================
module aes_prng (
    input  wire        clk,
    input  wire        reset,      // Active LOW
    input  wire        seed_en,    // 1 chu ky = nap seed tu ngoai (NEN DUNG)
    input  wire [63:0] seed_in,
    output wire [31:0] rnd32
);
    reg [31:0] l0, l1, l2, l3;

    // Mot buoc Fibonacci LFSR 32-bit, da thuc nguyen thuy x^32+x^22+x^2+x+1
    function [31:0] step1;
        input [31:0] s;
        begin
            step1 = {s[30:0], s[31] ^ s[21] ^ s[1] ^ s[0]};
        end
    endfunction

    // Dich 8 buoc trong 1 chu ky
    function [31:0] step8;
        input [31:0] s;
        integer k;
        reg [31:0] t;
        begin
            t = s;
            for (k = 0; k < 8; k = k + 1) t = step1(t);
            step8 = t;
        end
    endfunction

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            // Seed mac dinh: CHI de mo phong / tranh khoa cung o trang thai 0.
            // San pham that PHAI nap seed that qua seed_en.
            l0 <= 32'h1F2E3D4C; l1 <= 32'hA5A55A5A;
            l2 <= 32'h0BADC0DE; l3 <= 32'h7E57C0DE;
        end else if (seed_en) begin
            // OR voi hang so khac 0: LFSR o trang thai toan 0 se bi khoa cung
            l0 <= seed_in[31:0]  | 32'h1;
            l1 <= seed_in[63:32] | 32'h2;
            l2 <= (seed_in[31:0]  ^ seed_in[63:32]) | 32'h4;
            l3 <= (~seed_in[31:0] + seed_in[63:32]) | 32'h8;
        end else begin
            l0 <= step8(l0); l1 <= step8(l1);
            l2 <= step8(l2); l3 <= step8(l3);
        end
    end

    assign rnd32 = {l3[7:0], l2[7:0], l1[7:0], l0[7:0]};
endmodule
