`timescale 1ns / 1ps
// ============================================================================
// Module : aes256_data_dec_fsm  (AES-256 decryption datapath, 1 round / clock)
// Reset  : reset ACTIVE-LOW (async)
// Security upgrades: clear (zeroize), fault (kiem tra so vong kep, trang thai la)
// ============================================================================
module aes256_data_dec_fsm (
    input  wire         clk,
    input  wire         reset,
    input  wire         start,
    input  wire         clear,       // zeroize (tie 1'b0 neu khong dung)
    input  wire [127:0] ciphertext,
    input  wire [127:0] round_key,
    output reg  [3:0]   dec_round_num,
    output reg  [127:0] plaintext,
    output reg          done,
    output reg          fault
);
    reg  [127:0] state_reg;
    reg  [3:0]   rnd_chk;
    wire [127:0] isr_out, isb_out, ark_out, imc_out;

    aes_inv_shift_rows  u_inv_sr (.data_in(state_reg), .data_out(isr_out));
    aes_inv_sub_bytes   u_inv_sb (.data_in(isr_out),   .data_out(isb_out));
    assign ark_out = isb_out ^ round_key;
    aes_inv_mix_columns u_inv_mc (.data_in(ark_out),   .data_out(imc_out));

    localparam IDLE   = 3'd0,
               INIT   = 3'd1,
               ROUNDS = 3'd2,
               FINAL  = 3'd3,
               DONE   = 3'd4;

    (* fsm_safe_state = "reset_state" *)
    reg [2:0] state;

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            state         <= IDLE;
            done          <= 1'b0;
            fault         <= 1'b0;
            dec_round_num <= 4'd0;
            rnd_chk       <= 4'd0;
            state_reg     <= 128'd0;
            plaintext     <= 128'd0;
        end else if (clear) begin
            state         <= IDLE;
            done          <= 1'b0;
            fault         <= 1'b0;
            dec_round_num <= 4'd0;
            rnd_chk       <= 4'd0;
            state_reg     <= 128'd0;
            plaintext     <= 128'd0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        fault         <= 1'b0;
                        dec_round_num <= 4'd0;
                        rnd_chk       <= 4'd14;
                        state         <= INIT;
                    end
                end
                INIT: begin                     // AddRoundKey(K14)
                    state_reg     <= ciphertext ^ round_key;
                    dec_round_num <= 4'd1;
                    rnd_chk       <= rnd_chk - 1'b1;
                    state         <= ROUNDS;
                end
                ROUNDS: begin                   // dec round 1..13
                    state_reg <= imc_out;
                    rnd_chk   <= rnd_chk - 1'b1;
                    if (dec_round_num == 4'd13) begin
                        dec_round_num <= 4'd14;
                        state         <= FINAL;
                    end else begin
                        dec_round_num <= dec_round_num + 1'b1;
                    end
                end
                FINAL: begin                    // bo InvMixColumns, AddRoundKey(K0)
                    if (dec_round_num == 4'd14 && rnd_chk == 4'd0) begin
                        plaintext <= ark_out;
                    end else begin
                        plaintext <= 128'd0;
                        fault     <= 1'b1;
                    end
                    state_reg <= 128'd0;
                    rnd_chk   <= 4'd0;
                    done      <= 1'b1;
                    state     <= DONE;
                end
                DONE: begin
                    if (!start) state <= IDLE;
                end
                default: begin
                    fault     <= 1'b1;
                    state_reg <= 128'd0;
                    plaintext <= 128'd0;
                    state     <= IDLE;
                end
            endcase
        end
    end
endmodule
