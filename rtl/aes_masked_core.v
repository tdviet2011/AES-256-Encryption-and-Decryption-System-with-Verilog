`timescale 1ns / 1ps
// ============================================================================
// Module : aes_masked_core
//   Duong du lieu AES-256 (ma hoa HOAC giai ma) co CHONG SIDE-CHANNEL:
//     Lop 1: Boolean masking bac 1, mat na RIENG cho tung byte
//     Lop 2: Shuffling - 16 phep tra S-box lam theo thu tu NGAU NHIEN
//     Lop 3: Giu nguyen cac lop chong fault-injection (dem vong kep, trang thai la)
//
// ---------------------------------------------------------------------------
// BAT BIEN MASK (quan trong nhat - moi sua doi phai giu dung bat bien nay):
//
//        trang thai THAT  =  dstate ^ mstate
//
//   Gia tri that KHONG BAO GIO duoc ghi vao bat ky thanh ghi nao. Muc tieu cua
//   DPA la tuong quan giua cong suat tieu thu va mot gia tri trung gian phu thuoc
//   khoa (vi du plaintext ^ K0, hoac S[plaintext ^ K0]). Vi moi gia tri trong
//   day deu bi XOR voi mat na ngau nhien MOI o moi lan ma hoa, tuong quan do
//   bi triet tieu -> can rat nhieu trace hon (hoac khong con khai thac duoc bac 1).
//
// CACH MASK DI QUA TUNG PHEP BIEN DOI AES:
//   AddRoundKey  : XOR khoa chi vao dstate     -> mstate khong doi
//   SubBytes     : phi tuyen -> phai dung BANG CO MAT NA (aes_masked_sbox)
//   ShiftRows    : chi la noi day -> hoan vi CA dstate va mstate
//   MixColumns   : TUYEN TINH -> MC(d) = MC(that) ^ MC(mask)
//                  => phai chay THEM 1 khoi MixColumns tren duong MASK.
//                  Day la ly do thiet ke nay co 2 khoi MixColumns va 2 khoi
//                  InvMixColumns (tang dien tich, doi lay bao mat).
//
// ---------------------------------------------------------------------------
// HAI CHO TUYET DOI KHONG DUOC DE SYNTHESIS "TOI UU" (neu lam sai -> mat na vo dung):
//
//   (1) Khi lay dia chi tra bang:  addr = dstate[j] ^ mstate[j] ^ mi
//       Neu tool tinh (dstate[j] ^ mstate[j]) TRUOC thi ket qua trung gian do
//       chinh la BYTE THAT -> ro ri hoan toan.
//       => Giai phap trong code: khong bao gio viet bieu thuc 3 toan hang nay.
//          Ta tinh san corr = mstate ^ {16{mi}} vao THANH GHI 'corr' tu chu ky
//          truoc (corr chi chua mask, khong chua bi mat), roi addr = dstate[j] ^ corr[j]
//          chi con 1 phep XOR duy nhat.
//
//   (2) Khi go mat na dau ra bang: subd[j] = tdout ^ mo ^ nm
//       Neu tool tinh (tdout ^ mo) truoc thi do chinh la S[x] THAT -> ro ri.
//       => Giai phap: tinh san omc_r = mo ^ nm vao THANH GHI tu chu ky truoc,
//          roi subd[j] = tdout ^ omc_r, cung chi 1 phep XOR.
//
//   Hai thanh ghi corr/omc_r duoc danh dau dont_touch de Vivado khong gop lai.
//   SAU KHI SYNTH: nen kiem tra lai schematic, va trong XDC nen co
//       set_property DONT_TOUCH true [get_cells -hier -filter {NAME =~ *corr_reg*}]
//       set_property DONT_TOUCH true [get_cells -hier -filter {NAME =~ *omc_r_reg*}]
//
// ---------------------------------------------------------------------------
// GIOI HAN - PHAI NEU RO TRONG BAO CAO, KHONG DUOC NOI QUA:
//   a) Day la masking bac 1. Tan cong bac 2 (ket hop 2 diem ro ri) VAN co the
//      thanh cong. Chong bac cao hon can d+1 shares.
//   b) Masking Boolean tren FPGA khong duoc CHUNG MINH chong glitch. Phan phi
//      tuyen o day la RAM nen it glitch, nhung cac cay XOR cua MixColumns van
//      glitch. Muon bao dam toan hoc phai dung Threshold Implementation (TI)
//      hoac Domain-Oriented Masking (DOM) voi thanh ghi chan giua cac tang.
//   c) Chat luong bao ve PHU THUOC HOAN TOAN vao aes_prng (xem canh bao TRNG o do).
//   d) Shuffling o day dung hoan vi (cnt + a) ^ x -> 256 thu tu khac nhau, KHONG
//      phai 16! = 2*10^13 thu tu. Muon day du phai sinh hoan vi Fisher-Yates.
//   e) Khoi key expansion KHONG duoc mask (xem ghi chu o aes256_masked_top.v).
//   f) Chua chong ro ri qua Hamming-distance giua 2 vong lien tiep o muc toi da;
//      da giam bang cach doi mat na moi vong, nhung precharge thanh ghi bang gia
//      tri ngau nhien se tot hon nua.
// ---------------------------------------------------------------------------
// Do dai mot phep: 1(tload) + 16(sinh mask) + 257(tinh bang) + 1(init)
//                  + 14*(16+1) + 1  = ~514 chu ky  (ban khong mask: 32 chu ky)
//   => Day la cai gia cua bao mat: cham hon ~16 lan. O 100 MHz = ~5.1 us/block.
// ============================================================================
module aes_masked_core (
    input  wire         clk,
    input  wire         reset,       // Active LOW
    input  wire         start,
    input  wire         clear,       // zeroize
    input  wire         dec,         // 0 = ma hoa, 1 = giai ma
    input  wire [127:0] din,
    input  wire [127:0] round_key,
    input  wire [31:0]  rnd32,       // tu aes_prng

    output reg  [3:0]   round_num,   // -> chon round key (top lo viec dao chi so khi giai ma)
    output reg  [127:0] dout,
    output reg          done,
    output reg          fault
);
    localparam S_IDLE  = 4'd0,
               S_TLOAD = 4'd1,   // chot mi/mo/thu tu tron, kich tinh lai bang
               S_RMASK = 4'd2,   // 16 chu ky: sinh vector mat na dau vao
               S_TWAIT = 4'd3,   // cho bang tinh xong
               S_INIT  = 4'd4,   // AddRoundKey vong 0 (da co mat na)
               S_SUB   = 4'd5,   // 16 chu ky: SubBytes tuan tu, thu tu ngau nhien
               S_LIN   = 4'd6,   // cac phep tuyen tinh + AddRoundKey
               S_FIN   = 4'd7,   // kiem tra & go mat na dau ra
               S_DONE  = 4'd8;

    (* fsm_safe_state = "reset_state" *)
    reg [3:0]   st;

    reg [127:0] dstate, mstate;          // du lieu da mask / mat na tuong ung
    (* dont_touch = "true" *)
    reg [127:0] corr;                    // = mstate ^ {16{mi}}  (CHI chua mask - xem ghi chu (1))
    reg [127:0] subd, subm;              // ket qua SubBytes (da mask) va mat na moi
    reg [127:0] minit;                   // vector mat na ban dau
    reg [7:0]   mi, mo;                  // mat na vao/ra cua bang S-box
    reg [7:0]   nm_r;                    // mat na moi cho byte dang xu ly
    (* dont_touch = "true" *)
    reg [7:0]   omc_r;                   // = mo ^ nm_r  (CHI chua mask - xem ghi chu (2))
    reg [3:0]   cnt4;
    reg [3:0]   shuf_a, shuf_x;          // tham so hoan vi thu tu tra S-box
    reg [3:0]   rnd_chk;                 // bo dem vong DU PHONG (chong fault)
    reg         tload;

    // ------------------------------------------------------------------------
    // Bang S-box co mat na
    // ------------------------------------------------------------------------
    wire        tready;
    wire [7:0]  tdout;

    // Thu tu tra 16 byte: hoan vi song anh tren 0..15 -> khong bo sot/trung byte nao
    wire [3:0]  j = (cnt4 + shuf_a) ^ shuf_x;

    // Giai ma: InvShiftRows chi la noi day nen gop luon vao buoc doc byte
    wire [127:0] isr_d, isr_c;
    aes_inv_shift_rows u_isr_d (.data_in(dstate), .data_out(isr_d));
    aes_inv_shift_rows u_isr_c (.data_in(corr),   .data_out(isr_c));

    wire [127:0] rd_d = dec ? isr_d : dstate;
    wire [127:0] rd_c = dec ? isr_c : corr;

    // Byte 0 nam o bit [127:120] (dung quy uoc cua project)
    wire [7:0] byte_d = rd_d[127 - 8*j -: 8];
    wire [7:0] byte_c = rd_c[127 - 8*j -: 8];

    // DUY NHAT 1 phep XOR: (gia tri da mask) ^ (mask thuan) -> khong lo gia tri that
    wire [7:0] taddr = byte_d ^ byte_c;

    aes_masked_sbox u_tab (
        .clk(clk), .reset(reset), .load(tload), .inv(dec),
        .mask_in(mi), .mask_out(mo), .ready(tready),
        .addr(taddr), .dout(tdout)
    );

    // ------------------------------------------------------------------------
    // Cac phep tuyen tinh - LAM DOI: 1 ban cho du lieu, 1 ban cho MAT NA
    // ------------------------------------------------------------------------
    wire [127:0] sr_d, sr_m, mc_d, mc_m, ark_d, imc_d, imc_m;

    Aes_shift_rows      u_sr_d  (.data_in(subd),  .data_out(sr_d));
    Aes_shift_rows      u_sr_m  (.data_in(subm),  .data_out(sr_m));   // mask path
    Aes_mix_columns     u_mc_d  (.data_in(sr_d),  .data_out(mc_d));
    Aes_mix_columns     u_mc_m  (.data_in(sr_m),  .data_out(mc_m));   // mask path

    assign ark_d = subd ^ round_key;
    aes_inv_mix_columns u_imc_d (.data_in(ark_d), .data_out(imc_d));
    aes_inv_mix_columns u_imc_m (.data_in(subm),  .data_out(imc_m));  // mask path

    wire last = (round_num == 4'd14);

    // Vong cuoi cua AES khong co MixColumns / InvMixColumns
    wire [127:0] nxt_d = dec ? (last ? ark_d : imc_d)
                            : (last ? (sr_d ^ round_key) : (mc_d ^ round_key));
    wire [127:0] nxt_m = dec ? (last ? subm  : imc_m)
                            : (last ? sr_m   : mc_m);

    // Dat mat na dau vao cua plaintext/ciphertext TRUOC khi XOR voi round key,
    // de gia tri (din ^ round_key) - muc tieu kinh dien cua DPA - khong he ton tai.
    (* dont_touch = "true" *)
    wire [127:0] din_masked = din ^ minit;

    always @(posedge clk or negedge reset) begin
        if (!reset || clear) begin
            st        <= S_IDLE;
            done      <= 1'b0;
            fault     <= 1'b0;
            round_num <= 4'd0;
            dstate    <= 128'd0;
            mstate    <= 128'd0;
            corr      <= 128'd0;
            subd      <= 128'd0;
            subm      <= 128'd0;
            minit     <= 128'd0;
            dout      <= 128'd0;
            mi        <= 8'd0;
            mo        <= 8'd0;
            nm_r      <= 8'd0;
            omc_r     <= 8'd0;
            cnt4      <= 4'd0;
            shuf_a    <= 4'd0;
            shuf_x    <= 4'd0;
            rnd_chk   <= 4'd0;
            tload     <= 1'b0;
        end else begin
            tload <= 1'b0;

            // Randomness duoc CHOT TRUOC 1 chu ky (xem ghi chu (2) o dau file)
            nm_r  <= rnd32[7:0];
            omc_r <= mo ^ rnd32[7:0];

            case (st)
                S_IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        // Mat na moi hoan toan cho MOI lan ma hoa.
                        // Dung lai mat na cu giua cac lan se cho phep tan cong
                        // lay trung binh de triet tieu mat na -> PHAI doi moi lan.
                        mi        <= rnd32[7:0];
                        mo        <= rnd32[15:8];
                        shuf_a    <= rnd32[19:16];
                        shuf_x    <= rnd32[23:20];
                        tload     <= 1'b1;
                        fault     <= 1'b0;
                        round_num <= 4'd0;
                        cnt4      <= 4'd0;
                        st        <= S_TLOAD;
                    end
                end

                S_TLOAD: begin            // bang bat dau tinh tu chu ky sau (mi/mo da on dinh)
                    cnt4 <= 4'd0;
                    st   <= S_RMASK;
                end

                S_RMASK: begin            // sinh 16 byte mat na doc lap cho 16 byte state
                    minit[127 - 8*cnt4 -: 8] <= rnd32[7:0];
                    cnt4 <= cnt4 + 1'b1;
                    if (cnt4 == 4'd15) st <= S_TWAIT;
                end

                S_TWAIT: begin
                    if (tready) st <= S_INIT;
                end

                S_INIT: begin
                    // Vong 0: AddRoundKey. din_masked da co mat na truoc khi gap khoa.
                    dstate    <= din_masked ^ round_key;
                    mstate    <= minit;
                    corr      <= minit ^ {16{mi}};
                    round_num <= 4'd1;
                    rnd_chk   <= 4'd14;
                    cnt4      <= 4'd0;
                    st        <= S_SUB;
                end

                S_SUB: begin
                    // Tra bang 1 byte / chu ky, THU TU NGAU NHIEN (shuffling).
                    // Shuffling lam ke tan cong khong biet thoi diem nao ung voi byte nao
                    // -> ty so tin hieu/nhieu cua DPA giam khoang 16 lan.
                    subd[127 - 8*j -: 8] <= tdout ^ omc_r;   // doi tu mat na mo sang nm_r
                    subm[127 - 8*j -: 8] <= nm_r;
                    cnt4 <= cnt4 + 1'b1;
                    if (cnt4 == 4'd15) st <= S_LIN;
                end

                S_LIN: begin
                    dstate  <= nxt_d;
                    mstate  <= nxt_m;
                    corr    <= nxt_m ^ {16{mi}};    // chuan bi san cho vong sau
                    rnd_chk <= rnd_chk - 1'b1;
                    cnt4    <= 4'd0;
                    if (last) st <= S_FIN;
                    else begin
                        round_num <= round_num + 1'b1;
                        st        <= S_SUB;
                    end
                end

                S_FIN: begin
                    // Chong fault: hai bo dem doc lap phai dong y la da chay du 14 vong.
                    // Neu bi glitch bo bot vong -> KHONG xuat ket qua (ciphertext giam vong
                    // cho phep khoi phuc khoa bang Differential Fault Analysis).
                    if (round_num == 4'd14 && rnd_chk == 4'd0) begin
                        dout <= dstate ^ mstate;    // go mat na: dau ra la cong khai -> an toan
                    end else begin
                        dout  <= 128'd0;
                        fault <= 1'b1;
                    end
                    // Zeroize ngay: khong de du lieu nhay cam nam lai trong FF
                    dstate <= 128'd0;
                    mstate <= 128'd0;
                    corr   <= 128'd0;
                    subd   <= 128'd0;
                    subm   <= 128'd0;
                    minit  <= 128'd0;
                    done   <= 1'b1;
                    st     <= S_DONE;
                end

                S_DONE: begin
                    // 'done' la XUNG 1 CHU KY (khong giu muc). Ly do: top chay core
                    // nay HAI lan lien tiep (phep chinh + phep kiem tra nguoc); neu
                    // done giu muc thi top se tuong lan 2 xong ngay lap tuc, va core
                    // dang o S_DONE cho !start se bo qua xung start lan 2 -> treo.
                    done <= 1'b0;
                    st   <= S_IDLE;
                end

                default: begin
                    // Trang thai la: coi nhu bi tan cong -> xoa sach, bao fault
                    fault  <= 1'b1;
                    dout   <= 128'd0;
                    dstate <= 128'd0;
                    mstate <= 128'd0;
                    st     <= S_IDLE;
                end
            endcase
        end
    end
endmodule
