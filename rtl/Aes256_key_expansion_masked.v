`timescale 1ns / 1ps
// ============================================================================
// Module : Aes256_key_expansion_masked
//   Key expansion AES-256 co MASK + co CACHE (tinh mot lan moi khoa).
//
// ---------------------------------------------------------------------------
// VI SAO PHAI MASK CA MANG w[] CHU KHONG CHI MASK SubWord
//   Y dinh ban dau la "mask duong SubWord cho do lo khoa". Nhung neu w[0..59]
//   van luu round key DANG THO thi:
//     - dau vao cua S-box (w[idx-1]) da nam tho trong thanh ghi roi,
//     - dau ra S-box cuoi cung cung duoc ghi tho vao w[idx],
//   nghia la chi co BUOC TINH o giua la duoc che, con hai dau thi khong.
//   Do la bao mat hinh thuc, khong phai bao mat that.
//   => Ban nay luu w[] duoi dang CHIA DOI:
//            w_that[i]  =  wd[i] ^ wm[i]
//      Gia tri round key that khong nam trong bat ky thanh ghi nao.
//      Dau ra cung tra ve DANG MASK (round_key + round_key_mask) de khoi phai
//      go mat na o bien module -> aes_masked_core_mk nhan va cong mat na do
//      vao duong mat na cua no.
//
// ---------------------------------------------------------------------------
// VAN CON GIOI HAN - PHAI NEU TRONG BAO CAO:
//   1. 'key_in' la khoa THO o chan vao. Module nay khong the lam gi voi dieu do;
//      muon sach thi khoa phai duoc dua vao duoi dang chia doi tu ben ngoai
//      (vi du PS/AXI gui key^r va r), hoac nap qua kenh rieng.
//   2. Mat na wm[] la CO DINH trong suot vong doi mot khoa (vi key schedule
//      duoc cache, khong tinh lai). Dieu nay HOP LY: gia tri luu cung co dinh
//      nen khong co bien thien de DPA khai thac. Nhung no co nghia la neu ke
//      tan cong lay duoc wm[] mot lan thi go duoc ca key schedule.
//   3. Day la masking bac 1. Tan cong bac 2 van kha thi.
//   4. Bo so sanh 256-bit cho cache: xem ghi chu o Aes256_key_expansion_cached.v
//
// ---------------------------------------------------------------------------
// CHI PHI:
//   - Thanh ghi: 60 word x 2 (wd + wm) = 3840 FF, gap doi ban khong mask.
//   - Thoi gian (CHI khi khoa doi): 8 (chia doi khoa) + 257 (dung bang S-box
//     co mat na) + 13 buoc x 6 chu ky = ~343 chu ky. Khoa khong doi: 2 chu ky.
// ============================================================================
module Aes256_key_expansion_masked (
    input  wire         clk,
    input  wire         reset,        // Active LOW
    input  wire         key_mode,
    input  wire         clear,        // chi dua FSM ve cho, KHONG xoa cache
    input  wire         zeroize,      // xoa SACH (cuoi phien)
    input  wire [255:0] key_in,
    input  wire [31:0]  rnd32,        // tu aes_prng
    input  wire [3:0]   round_num,

    output wire [127:0] round_key,       // DA MASK
    output wire [127:0] round_key_mask,  // mat na tuong ung
    output reg          flag,
    output reg          cache_hit
);
    localparam S_IDLE  = 3'd0,
               S_KMASK = 3'd1,   // chia doi khoa goc thanh wd/wm
               S_TLOAD = 3'd2,
               S_TWAIT = 3'd3,
               S_PREP  = 3'd4,   // chuan bi word nguon + kcorr cho mot buoc
               S_SUB   = 3'd5,   // 4 chu ky tra bang S-box co mat na
               S_LIN   = 3'd6,   // phan tuyen tinh: ghi 4 word moi
               S_DONE  = 3'd7;

    (* fsm_safe_state = "reset_state" *)
    reg [2:0]  st;
    reg [3:0]  step_cal;
    reg [5:0]  idx;
    reg [1:0]  bsel;
    reg [2:0]  kcnt;

    reg [31:0] wd [0:59];
    reg [31:0] wm [0:59];

    reg [31:0] src_d, src_m;            // word nguon (da mask) + mat na cua no
    (* dont_touch = "true" *)
    reg [31:0] kcorr;                   // = src_m ^ {4{mi}}  (CHI chua mask)
    reg [31:0] tmp_d, tmp_m;            // ket qua SubWord (da mask) + mat na

    reg [7:0]  mi, mo;
    reg [7:0]  nm_r;
    (* dont_touch = "true" *)
    reg [7:0]  omc_r;                   // = mo ^ nm_r  (CHI chua mask)
    reg        tload;

    reg [255:0] key_cache;
    reg         key_valid;
    integer i;

    wire key_same = key_valid && (key_in == key_cache);

    // ------------------------------------------------------------------------
    // Bang S-box co mat na (chi can chieu thuan cho key expansion)
    // ------------------------------------------------------------------------
    wire       tready;
    wire [7:0] tdout;
    // Mot phep XOR duy nhat -> khong bao gio hien byte khoa that
    wire [7:0] taddr = src_d[31 - 8*bsel -: 8] ^ kcorr[31 - 8*bsel -: 8];

    aes_masked_sbox u_tab (
        .clk(clk), .reset(reset), .load(tload), .inv(1'b0),
        .mask_in(mi), .mask_out(mo), .ready(tready),
        .addr(taddr), .dout(tdout)
    );

    function [31:0] GetRcon;
        input [3:0] round;
        begin
            case (round)
                4'd1: GetRcon = 32'h01000000; 4'd2: GetRcon = 32'h02000000;
                4'd3: GetRcon = 32'h04000000; 4'd4: GetRcon = 32'h08000000;
                4'd5: GetRcon = 32'h10000000; 4'd6: GetRcon = 32'h20000000;
                4'd7: GetRcon = 32'h40000000;
                default: GetRcon = 32'h00000000;
            endcase
        end
    endfunction

    function [31:0] RotWord;
        input [31:0] word;
        begin
            RotWord = {word[23:0], word[31:24]};
        end
    endfunction

    // Word nguon cho buoc hien tai (co RotWord khi idx chia het cho 8)
    wire        need_rot = ((idx % 8) == 0);
    wire [31:0] prev_d   = wd[idx-1];
    wire [31:0] prev_m   = wm[idx-1];

    // Khoa goc duoc chia doi ngay khi nap (khong luu tho)
    wire [31:0] kword = key_in[255 - 32*kcnt -: 32];

    // Phan tuyen tinh: XOR lan truyen, lam song song tren CA hai duong
    wire [31:0] rcon_v = need_rot ? GetRcon(idx >> 3) : 32'd0;
    wire [31:0] t_d    = tmp_d ^ rcon_v;      // Rcon la hang so cong khai -> chi vao duong du lieu
    wire [31:0] t_m    = tmp_m;
    wire [31:0] n0_d = wd[idx-8] ^ t_d;  wire [31:0] n0_m = wm[idx-8] ^ t_m;
    wire [31:0] n1_d = wd[idx-7] ^ n0_d; wire [31:0] n1_m = wm[idx-7] ^ n0_m;
    wire [31:0] n2_d = wd[idx-6] ^ n1_d; wire [31:0] n2_m = wm[idx-6] ^ n1_m;
    wire [31:0] n3_d = wd[idx-5] ^ n2_d; wire [31:0] n3_m = wm[idx-5] ^ n2_m;

    always @(posedge clk or negedge reset) begin
        if (!reset || zeroize) begin
            st <= S_IDLE; flag <= 1'b0; cache_hit <= 1'b0;
            step_cal <= 4'd0; idx <= 6'd0; bsel <= 2'd0; kcnt <= 3'd0;
            key_cache <= 256'd0; key_valid <= 1'b0;
            mi <= 8'd0; mo <= 8'd0; nm_r <= 8'd0; omc_r <= 8'd0; tload <= 1'b0;
            src_d <= 32'd0; src_m <= 32'd0; kcorr <= 32'd0;
            tmp_d <= 32'd0; tmp_m <= 32'd0;
            for (i = 0; i < 60; i = i + 1) begin wd[i] <= 32'd0; wm[i] <= 32'd0; end
        end else if (clear) begin
            st   <= S_IDLE;
            flag <= 1'b0;
        end else begin
            tload <= 1'b0;
            nm_r  <= rnd32[7:0];
            omc_r <= mo ^ rnd32[7:0];

            case (st)
                S_IDLE: begin
                    flag <= 1'b0;
                    if (key_mode) begin
                        if (key_same) begin
                            cache_hit <= 1'b1;
                            st        <= S_DONE;
                        end else begin
                            cache_hit <= 1'b0;
                            key_cache <= key_in;
                            key_valid <= 1'b0;
                            mi        <= rnd32[7:0];
                            mo        <= rnd32[15:8];
                            tload     <= 1'b1;
                            kcnt      <= 3'd0;
                            st        <= S_KMASK;
                        end
                    end
                end

                S_KMASK: begin
                    // Chia doi 8 word khoa goc: wd = key ^ r, wm = r
                    wd[kcnt] <= kword ^ rnd32;
                    wm[kcnt] <= rnd32;
                    kcnt     <= kcnt + 1'b1;
                    if (kcnt == 3'd7) begin
                        step_cal <= 4'd0;
                        idx      <= 6'd8;
                        st       <= S_TWAIT;
                    end
                end

                S_TWAIT: if (tready) st <= S_PREP;

                S_PREP: begin
                    src_d <= need_rot ? RotWord(prev_d) : prev_d;
                    src_m <= need_rot ? RotWord(prev_m) : prev_m;
                    // kcorr chi chua mat na -> tinh truoc 1 chu ky, khong bao gio
                    // de bieu thuc (src_d ^ src_m) xuat hien (se lo byte khoa that)
                    kcorr <= (need_rot ? RotWord(prev_m) : prev_m) ^ {4{mi}};
                    bsel  <= 2'd0;
                    st    <= S_SUB;
                end

                S_SUB: begin
                    tmp_d[31 - 8*bsel -: 8] <= tdout ^ omc_r;   // doi mat na mo -> nm_r
                    tmp_m[31 - 8*bsel -: 8] <= nm_r;
                    bsel <= bsel + 1'b1;
                    if (bsel == 2'd3) st <= S_LIN;
                end

                S_LIN: begin
                    wd[idx]   <= n0_d;  wm[idx]   <= n0_m;
                    wd[idx+1] <= n1_d;  wm[idx+1] <= n1_m;
                    wd[idx+2] <= n2_d;  wm[idx+2] <= n2_m;
                    wd[idx+3] <= n3_d;  wm[idx+3] <= n3_m;
                    if (step_cal == 4'd12) begin
                        st <= S_DONE;
                    end else begin
                        step_cal <= step_cal + 1'b1;
                        idx      <= idx + 3'd4;
                        st       <= S_PREP;
                    end
                end

                S_DONE: begin
                    flag      <= 1'b1;
                    key_valid <= 1'b1;
                    if (!key_mode) st <= S_IDLE;
                end

                default: st <= S_IDLE;
            endcase
        end
    end

    // ------------------------------------------------------------------------
    // Mux round key - tra ve DANG MASK (du lieu + mat na di cung nhau)
    // ------------------------------------------------------------------------
    wire [5:0] b = {round_num, 2'b00};          // = round_num * 4
    assign round_key      = {wd[b], wd[b+1], wd[b+2], wd[b+3]};
    assign round_key_mask = {wm[b], wm[b+1], wm[b+2], wm[b+3]};
endmodule
