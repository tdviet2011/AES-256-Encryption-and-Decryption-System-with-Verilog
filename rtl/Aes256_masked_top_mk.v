`timescale 1ns / 1ps
// ============================================================================
// Module : aes256_masked_top_mk
//   Giong aes256_masked_top nhung dung KEY SCHEDULE CO MASK + CO CACHE:
//     - round key khong con nam THO trong thanh ghi (xem Aes256_key_expansion_masked)
//     - key schedule chi tinh lai khi khoa doi (tiet kiem thoi gian + giam lo dien)
//     - them chan 'zeroize' (BAT BUOC keo len khi ket thuc phien) va 'key_cached'
//     - tham so SYNC_RAM chon LUTRAM / Block RAM cho bang S-box
//
// Module goc:
//   AES-256 ma hoa/giai ma CO CHONG SIDE-CHANNEL (DPA) + CHONG FAULT-INJECTION.
//
//   Cung bo chan nhu aes256_enc_dec_top, chi THEM 2 chan seed cho TRNG.
//   Muon doi sang ban nay chi can dat module nay lam top trong Vivado.
//
//   mode = 1'b0 : Encryption (data_in = Plaintext  --> data_out = Ciphertext)
//   mode = 1'b1 : Decryption (data_in = Ciphertext --> data_out = Plaintext)
//   reset       : ACTIVE-LOW, bat dong bo
//
// GIAO TIEP (giong ban khong mask):
//   - Dat key/data_in/mode roi kich start (CHI canh len duoc tinh).
//   - start chi duoc nhan khi busy = 0; input duoc CHOT dung canh clock do.
//   - done giu muc khi co ket qua; fault = 1 thi data_out bi ep = 0.
//
// ---------------------------------------------------------------------------
// CAC LOP BAO VE (va lop nao chong tan cong gi):
//
//   [Chong DPA/CPA - phan tich cong suat]
//     1. Boolean masking bac 1, mat na rieng tung byte, DOI MOI LAN ma hoa
//     2. Shuffling thu tu 16 phep tra S-box
//     3. S-box dang bang tinh lai -> phan phi tuyen khong co glitch to hop
//        (chi tiet + gioi han: xem aes_masked_core.v)
//
//   [Chong fault injection / DFA]
//     4. Dem vong kep trong core (hai bo dem doc lap)
//     5. Verify-after-compute: ma hoa xong thi giai nguoc lai va so voi dau vao
//     6. Phat hien trang thai FSM la
//     7. Watchdog
//
//   [Chong doc lai bi mat]
//     8. Zeroize key schedule + mat na + state trung gian sau moi lan dung
//
//   [Chong loi giao tiep]
//     9. Chot input, busy-lock, loc canh len start
//
// ---------------------------------------------------------------------------
// GHI CHU: VI SAO KEY EXPANSION KHONG DUOC MASK
//   Khoi key expansion tinh ra 15 round key tu khoa, va KET QUA CUA NO KHONG
//   PHU THUOC PLAINTEXT. DPA/CPA kinh dien hoat dong bang cach tuong quan cong
//   suat voi mot gia tri trung gian THAY DOI theo plaintext; vi key schedule
//   la hang so voi mot khoa cho truoc, no khong cung cap "bien thien" nao de
//   tuong quan -> KHONG bi DPA bac 1 kieu thong thuong.
//   Tuy nhien no VAN bi:
//     - SPA / template attack / single-trace (phan tich 1 vet do)
//     - DPA neu he thong doi khoa thuong xuyen
//   => KHUYEN NGHI THUC TE: tinh key schedule MOT LAN moi khoa (khong phai moi
//      block nhu hien tai) de giam so lan lo dien, va neu de tai yeu cau chong
//      ca SPA thi phai mask luon duong SubWord cua key expansion.
//   Hien tai thiet ke tinh lai key schedule moi lan start -> dung nhung lo dien
//   nhieu hon can thiet. Day la viec nen lam tiep.
// ============================================================================
module aes256_masked_top_mk #(
    parameter VERIFY_EN = 1,          // 1: bat kiem tra nguoc (latency x2)
    parameter SYNC_RAM  = 0,          // 0 = LUTRAM, 1 = Block RAM (+14 chu ky/block)
    parameter WDT_MAX   = 16'd4000    // phai phu het: doi khoa (~338) + 2 x core (~514)
)(
    input  wire         clk,
    input  wire         reset,        // Active LOW
    input  wire         start,
    input  wire         mode,         // 0: Encrypt, 1: Decrypt
    input  wire [255:0] key,
    input  wire [127:0] data_in,
    input  wire         zeroize,      // 1 xung khi KET THUC PHIEN -> xoa sach khoa khoi FF

    // Nguon entropy - XEM CANH BAO TRONG aes_prng.v.
    // Neu de seed_en = 0 thi mask sinh ra tu seed co dinh -> masking GAN NHU VO NGHIA.
    // Phai noi toi TRNG (ring oscillator) hoac nhan seed tu PS/AXI khi khoi dong.
    input  wire         seed_en,
    input  wire [63:0]  seed_in,

    output reg  [127:0] data_out,
    output reg          done,
    output wire         busy,
    output reg          fault,
    output wire         key_cached    // 1 = lan nay dung lai key schedule cu
);
    localparam S_IDLE = 3'd0,
               S_KEXP = 3'd1,
               S_RUN1 = 3'd2,         // phep tinh chinh
               S_RUN2 = 3'd3,         // phep tinh nguoc de kiem tra
               S_WIPE = 3'd4;

    (* fsm_safe_state = "reset_state" *)
    reg  [2:0]   st;
    reg          mode_r;
    reg  [127:0] data_r;
    reg  [127:0] res1;
    reg          ke_req;
    reg          core_go;
    reg          core_dec;
    reg          pend_ok;
    reg          start_q;
    reg  [15:0]  wdt;

    assign busy = (st != S_IDLE);

    wire start_pe = start & ~start_q;
    wire accept   = (st == S_IDLE) && start_pe;

    // wipe la to hop: dang o S_WIPE hoac FSM roi vao trang thai la
    wire wipe    = (st == S_WIPE) || (st > S_WIPE);
    wire ke_mode = ke_req | accept;   // key duoc chot DUNG chu ky nhan start

    // ------------------------------------------------------------------------
    // PRNG - nguon mat na. CHI MOT khoi, dung chung.
    // ------------------------------------------------------------------------
    wire [31:0] rnd32;
    aes_prng u_prng (
        .clk(clk), .reset(reset),
        .seed_en(seed_en), .seed_in(seed_in),
        .rnd32(rnd32)
    );

    // ------------------------------------------------------------------------
    // Key expansion - DUNG CHUNG 1 khoi (ban cu co 2 khoi = 2 ban sao khoa trong FF)
    // ------------------------------------------------------------------------
    wire [3:0]   core_rnum;
    wire [127:0] rkey;
    wire         ke_flag;

    // Giai ma dung round key theo thu tu nguoc: vong r -> K(14-r)
    wire [3:0]   ke_rnum = core_dec ? (4'd14 - core_rnum) : core_rnum;

    // Key schedule: CO MASK (w[] luu duoi dang chia doi) va CO CACHE (chi tinh
    // lai khi khoa doi). 'clear' chi dua FSM ve cho; muon xoa sach phai dua
    // 'zeroize' len khi ket thuc phien.
    wire [127:0] rkey_mask;
    Aes256_key_expansion_masked u_kexp (
        .clk            (clk),
        .reset          (reset),
        .key_mode       (ke_mode),
        .clear          (wipe),
        .zeroize        (zeroize),
        .key_in         (key),
        .rnd32          (rnd32),
        .round_num      (ke_rnum),
        .round_key      (rkey),
        .round_key_mask (rkey_mask),
        .flag           (ke_flag),
        .cache_hit      (key_cached)
    );

    // ------------------------------------------------------------------------
    // MOT core masked duy nhat, chay 2 lan (chinh + kiem tra nguoc).
    // Dung 1 core thay vi 2 giup tiet kiem rat nhieu dien tich, vi core masked
    // da co san 2 khoi MixColumns + 2 khoi InvMixColumns cho duong mat na.
    // ------------------------------------------------------------------------
    wire [127:0] core_in = (st == S_RUN2) ? res1 : data_r;
    wire [127:0] core_out;
    wire         core_done, core_fault;

    aes_masked_core_mk #(.SYNC_RAM(SYNC_RAM)) u_core (
        .clk       (clk),
        .reset     (reset),
        .start     (core_go),
        .clear     (wipe),
        .dec       (core_dec),
        .din       (core_in),
        .round_key      (rkey),
        .round_key_mask (rkey_mask),
        .rnd32     (rnd32),
        .round_num (core_rnum),
        .dout      (core_out),
        .done      (core_done),
        .fault     (core_fault)
    );

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            st       <= S_IDLE;
            mode_r   <= 1'b0;
            data_r   <= 128'd0;
            res1     <= 128'd0;
            ke_req   <= 1'b0;
            core_go  <= 1'b0;
            core_dec <= 1'b0;
            pend_ok  <= 1'b0;
            start_q  <= 1'b0;
            wdt      <= 16'd0;
            data_out <= 128'd0;
            done     <= 1'b0;
            fault    <= 1'b0;
        end else begin
            core_go <= 1'b0;
            start_q <= start;
            wdt     <= busy ? wdt + 1'b1 : 16'd0;

            case (st)
                S_IDLE: begin
                    if (accept) begin        // CHOT toan bo input tai day
                        mode_r   <= mode;
                        data_r   <= data_in;
                        core_dec <= mode;
                        ke_req   <= 1'b1;
                        done     <= 1'b0;
                        fault    <= 1'b0;
                        data_out <= 128'd0;
                        pend_ok  <= 1'b0;
                        st       <= S_KEXP;
                    end
                end

                S_KEXP: begin
                    if (ke_flag) begin
                        core_go <= 1'b1;
                        st      <= S_RUN1;
                    end
                end

                S_RUN1: begin
                    if (core_done) begin
                        res1 <= core_out;
                        if (VERIFY_EN != 0) begin
                            // Chay nguoc lai: ma hoa -> giai ma, hoac giai ma -> ma hoa.
                            // Neu fault injection lam sai bat ky vong nao thi ket qua
                            // nguoc se khong khop dau vao -> bi chan, khong xuat ra.
                            core_dec <= ~mode_r;
                            core_go  <= 1'b1;
                            st       <= S_RUN2;
                        end else begin
                            pend_ok <= 1'b1;
                            st      <= S_WIPE;
                        end
                    end
                end

                S_RUN2: begin
                    if (core_done) begin
                        pend_ok <= (core_out == data_r);
                        st      <= S_WIPE;
                    end
                end

                S_WIPE: begin
                    if (pend_ok && !core_fault && !fault) begin
                        data_out <= res1;
                    end else begin
                        data_out <= 128'd0;   // co su co -> KHONG xuat gi ca
                        fault    <= 1'b1;
                    end
                    done     <= 1'b1;
                    ke_req   <= 1'b0;         // wipe = 1 o state nay -> xoa key schedule + core
                    data_r   <= 128'd0;
                    res1     <= 128'd0;
                    core_dec <= 1'b0;
                    pend_ok  <= 1'b0;
                    st       <= S_IDLE;
                end

                default: begin
                    fault   <= 1'b1;
                    pend_ok <= 1'b0;
                    st      <= S_WIPE;
                end
            endcase

            // Loi tu core hoac watchdog -> huy ngay va xoa sach
            if (busy && st != S_WIPE && (core_fault || wdt >= WDT_MAX)) begin
                fault   <= 1'b1;
                pend_ok <= 1'b0;
                st      <= S_WIPE;
            end
        end
    end
endmodule
