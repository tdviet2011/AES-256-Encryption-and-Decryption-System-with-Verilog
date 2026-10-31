`timescale 1ns / 1ps
// ============================================================================
// Module : Aes_data_FSM  (AES-256 encryption datapath, 1 round / clock)
// Reset  : reset ACTIVE-LOW (async)
// Security upgrades:
//   - clear : xoa (zeroize) state_reg / ciphertext sau khi dung xong
//   - fault : bao loi neu FSM vao trang thai la hoac den FINAL khi chua du 14 vong
//             (chong tan cong fault-injection bo bot vong -> lo khoa)
//   - Chi xuat ciphertext khi so vong hop le, neu khong xuat 0
// ============================================================================
module Aes_data_FSM(
    input  wire         clk,
    input  wire         reset,
    input  wire         start,
    input  wire         clear,       // zeroize (tie 1'b0 neu khong dung)

    input  wire [127:0] plaintext,
    input  wire [127:0] round_key,

    output reg  [3:0]   round_num,
    output reg  [127:0] ciphertext,
    output reg          done,
    output reg          fault
    );
    localparam IDLE   = 3'd0;
    localparam INIT   = 3'd1;
    localparam ROUNDS = 3'd2;
    localparam FINAL  = 3'd3;
    localparam DONE   = 3'd4;

    reg  [127:0] state_reg;
    reg  [3:0]   rnd_chk;           // bo dem du phong dem nguoc 14 -> 0
    wire [127:0] sb_out, sr_out, mc_out;

    Aes_sub_bytes   Sub_bytes   (.data_in(state_reg), .data_out(sb_out));
    Aes_shift_rows  Shift_rows  (.data_in(sb_out),    .data_out(sr_out));
    Aes_mix_columns Mix_columns (.data_in(sr_out),    .data_out(mc_out));

    (* fsm_safe_state = "reset_state" *)
    reg [2:0] state;

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            state      <= IDLE;
            done       <= 1'b0;
            fault      <= 1'b0;
            round_num  <= 4'd0;
            rnd_chk    <= 4'd0;
            state_reg  <= 128'd0;
            ciphertext <= 128'd0;
        end else if (clear) begin
            state      <= IDLE;
            done       <= 1'b0;
            fault      <= 1'b0;
            round_num  <= 4'd0;
            rnd_chk    <= 4'd0;
            state_reg  <= 128'd0;
            ciphertext <= 128'd0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        fault     <= 1'b0;
                        round_num <= 4'd0;
                        rnd_chk   <= 4'd14;
                        state     <= INIT;
                    end
                end
                INIT: begin                          // Round 0: AddRoundKey(K0)
                    state_reg <= plaintext ^ round_key;
                    round_num <= 4'd1;
                    rnd_chk   <= rnd_chk - 1'b1;
                    state     <= ROUNDS;
                end
                ROUNDS: begin                        // Round 1..13
                    state_reg <= mc_out ^ round_key;
                    rnd_chk   <= rnd_chk - 1'b1;
                    if (round_num == 4'd13) begin
                        round_num <= 4'd14;
                        state     <= FINAL;
                    end else begin
                        round_num <= round_num + 1'b1;
                    end
                end
                FINAL: begin                         // Round 14 (khong MixColumns)
                    // Kiem tra kep: ca 2 bo dem phai dong y la da chay du vong
                    if (round_num == 4'd14 && rnd_chk == 4'd0) begin
                        ciphertext <= sr_out ^ round_key;
                    end else begin
                        ciphertext <= 128'd0;
                        fault      <= 1'b1;
                    end
                    state_reg <= 128'd0;             // xoa trang thai trung gian
                    rnd_chk   <= 4'd0;
                    done      <= 1'b1;
                    state     <= DONE;
                end
                DONE: begin
                    if (!start) state <= IDLE;
                end
                default: begin                       // trang thai la -> nghi bi tan cong
                    fault      <= 1'b1;
                    state_reg  <= 128'd0;
                    ciphertext <= 128'd0;
                    state      <= IDLE;
                end
            endcase
        end
    end
endmodule
