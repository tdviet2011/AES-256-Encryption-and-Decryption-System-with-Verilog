`timescale 1ns / 1ps
// ============================================================================
// Module : aes256_enc_dec_top   (hardened version)
//   mode = 1'b0 : Encryption (data_in = Plaintext  --> data_out = Ciphertext)
//   mode = 1'b1 : Decryption (data_in = Ciphertext --> data_out = Plaintext)
//   reset       : ACTIVE-LOW, asynchronous
//
// Giao tiep:
//   - Dua key/data_in/mode roi kich start (chi canh len duoc tinh).
//   - start chi duoc nhan khi busy = 0; key/data_in/mode duoc CHOT dung canh clock do.
//   - done = 1 (giu muc) khi co ket qua, ha xuong khi start lan sau duoc nhan.
//   - fault = 1 khi phat hien loi/tan cong -> data_out bi ep = 0.
//
// Nang cap bao mat so voi ban cu:
//   1. Chot (latch) key, data_in, mode khi start -> doi input giua chung khong lam hong ket qua
//   2. Busy-lock: bo qua start khi dang tinh -> khong ghi de key schedule giua chung
//   3. Dung chung 1 khoi Key Expansion (ban cu: 2 khoi = 2 ban sao khoa trong FF)
//   4. Verify-after-compute (VERIFY_EN=1): ma hoa xong thi giai nguoc lai de so sanh
//      (va nguoc lai) -> chong Differential Fault Analysis / glitch bo vong
//   5. Kiem tra so vong kep + trang thai FSM la trong tung core -> fault
//   6. Watchdog: qua WDT_MAX chu ky ma chua xong -> fault
//   7. Zeroize: xoa key schedule, state trung gian, ban sao input sau moi lan dung
//   8. data_out chi lay tu thanh ghi ket qua da kiem tra; khi fault -> 0
// ============================================================================
module aes256_enc_dec_top #(
    parameter VERIFY_EN = 1,        // 1: bat kiem tra nguoc (latency ~ x2)
    parameter WDT_MAX   = 8'd120    // gioi han chu ky cho 1 lan tinh
)(
    input  wire         clk,
    input  wire         reset,      // Active LOW
    input  wire         start,
    input  wire         mode,       // 0: Encrypt, 1: Decrypt
    input  wire [255:0] key,
    input  wire [127:0] data_in,

    output reg  [127:0] data_out,
    output reg          done,
    output wire         busy,
    output reg          fault
);
    // ------------------------------------------------------------------------
    // Controller states
    // ------------------------------------------------------------------------
    localparam S_IDLE = 3'd0,
               S_KEXP = 3'd1,   // cho key expansion
               S_RUN1 = 3'd2,   // phep tinh chinh
               S_RUN2 = 3'd3,   // phep tinh kiem tra nguoc
               S_WIPE = 3'd4;   // xoa du lieu nhay cam

    (* fsm_safe_state = "reset_state" *)
    reg  [2:0]   st;
    reg          mode_r;
    reg  [127:0] data_r;        // ban sao input da chot
    reg  [127:0] res1;          // ket qua phep tinh chinh
    reg          ke_req;        // giu key expansion o trang thai DONE
    reg          start_q;       // phat hien canh len cua start
    reg          enc_go, dec_go;
    reg          pend_ok;
    reg  [7:0]   wdt;

    assign busy = (st != S_IDLE);

    // Chi nhan CANH LEN cua start: giu start = 1 lien tuc cung chi chay 1 lan
    wire start_pe = start & ~start_q;
    wire accept   = (st == S_IDLE) && start_pe;

    // Zeroize to hop: dang o S_WIPE hoac FSM roi vao trang thai la
    wire wipe = (st == S_WIPE) || (st > S_WIPE);
    // key_mode len cung canh voi start -> key duoc chot DUNG chu ky start
    wire ke_mode = ke_req | accept;

    // ------------------------------------------------------------------------
    // Shared key expansion
    // ------------------------------------------------------------------------
    wire [3:0]   enc_rnum, dec_rnum;
    wire [127:0] rkey;
    wire         ke_flag;
    // Core nao dang chay thi core do dieu khien round_num
    wire         enc_active = (st == S_RUN1) ? ~mode_r : mode_r;
    wire [3:0]   ke_rnum    = enc_active ? enc_rnum : (4'd14 - dec_rnum);

    Aes256_key_expansion_FSM u_kexp (
        .clk       (clk),
        .reset     (reset),
        .key_mode  (ke_mode),
        .clear     (wipe),
        .key_in    (key),
        .round_num (ke_rnum),
        .round_key (rkey),
        .flag      (ke_flag)
    );

    // ------------------------------------------------------------------------
    // Cores
    // ------------------------------------------------------------------------
    wire [127:0] enc_out, dec_out;
    wire         enc_done, dec_done, enc_fault, dec_fault;

    // Enc core: input = data_r khi mode=0 (chinh), = res1 khi mode=1 (verify)
    Aes_data_FSM u_enc (
        .clk        (clk),
        .reset      (reset),
        .start      (enc_go),
        .clear      (wipe),
        .plaintext  (mode_r ? res1 : data_r),
        .round_key  (rkey),
        .round_num  (enc_rnum),
        .ciphertext (enc_out),
        .done       (enc_done),
        .fault      (enc_fault)
    );

    aes256_data_dec_fsm u_dec (
        .clk           (clk),
        .reset         (reset),
        .start         (dec_go),
        .clear         (wipe),
        .ciphertext    (mode_r ? data_r : res1),
        .round_key     (rkey),
        .dec_round_num (dec_rnum),
        .plaintext     (dec_out),
        .done          (dec_done),
        .fault         (dec_fault)
    );

    wire core_fault = enc_fault | dec_fault;

    // ------------------------------------------------------------------------
    // Controller
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            st       <= S_IDLE;
            mode_r   <= 1'b0;
            data_r   <= 128'd0;
            res1     <= 128'd0;
            ke_req   <= 1'b0;
            start_q  <= 1'b0;
            enc_go   <= 1'b0;
            dec_go   <= 1'b0;
            pend_ok  <= 1'b0;
            wdt      <= 8'd0;
            data_out <= 128'd0;
            done     <= 1'b0;
            fault    <= 1'b0;
        end else begin
            enc_go <= 1'b0;             // mac dinh: xung 1 chu ky
            dec_go <= 1'b0;
            start_q <= start;
            wdt     <= busy ? wdt + 1'b1 : 8'd0;

            case (st)
                S_IDLE: begin
                    if (accept) begin   // chot toan bo input (key chot trong u_kexp)
                        mode_r   <= mode;
                        data_r   <= data_in;
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
                        if (mode_r) dec_go <= 1'b1;
                        else        enc_go <= 1'b1;
                        st <= S_RUN1;
                    end
                end

                S_RUN1: begin
                    if (mode_r ? dec_done : enc_done) begin
                        res1 <= mode_r ? dec_out : enc_out;
                        if (VERIFY_EN != 0) begin
                            if (mode_r) enc_go <= 1'b1;   // decrypt -> re-encrypt
                            else        dec_go <= 1'b1;   // encrypt -> re-decrypt
                            st <= S_RUN2;
                        end else begin
                            pend_ok <= 1'b1;
                            st      <= S_WIPE;
                        end
                    end
                end

                S_RUN2: begin
                    if (mode_r ? enc_done : dec_done) begin
                        // ket qua kiem tra nguoc phai trung voi input goc
                        pend_ok <= ((mode_r ? enc_out : dec_out) == data_r);
                        st      <= S_WIPE;
                    end
                end

                S_WIPE: begin
                    if (pend_ok && !core_fault && !fault) begin
                        data_out <= res1;
                    end else begin
                        data_out <= 128'd0;
                        fault    <= 1'b1;
                    end
                    done    <= 1'b1;
                    ke_req  <= 1'b0;        // wipe = 1 trong state nay -> xoa key schedule + cores
                    data_r  <= 128'd0;
                    res1    <= 128'd0;
                    pend_ok <= 1'b0;
                    st      <= S_IDLE;
                end

                default: begin              // trang thai la -> coi nhu bi tan cong
                    fault    <= 1'b1;
                    pend_ok  <= 1'b0;
                    st       <= S_WIPE;
                end
            endcase

            // Loi tu core hoac watchdog -> huy ngay, xoa sach
            if (busy && st != S_WIPE && (core_fault || wdt >= WDT_MAX)) begin
                fault   <= 1'b1;
                pend_ok <= 1'b0;
                st      <= S_WIPE;
            end
        end
    end
endmodule
