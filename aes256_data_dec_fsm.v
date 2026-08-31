`timescale 1ns / 1ps

module aes256_data_dec_fsm (
    input  wire         clk,
    input  wire         reset,
    input  wire         start,
    input  wire [127:0] ciphertext,
    input  wire [127:0] round_key,
    output reg  [3:0]   dec_round_num,
    output reg  [127:0] plaintext,
    output reg          done
);
    reg [127:0] state_reg;

    wire [127:0] isr_out, isb_out, ark_out, imc_out;

    // Nối liên tiếp các khối biến đổi ngược
    aes_inv_shift_rows u_inv_sr (.data_in(state_reg), .data_out(isr_out));
    aes_inv_sub_bytes  u_inv_sb (.data_in(isr_out),   .data_out(isb_out));
    
    assign ark_out = isb_out ^ round_key;
    
    aes_inv_mix_columns u_inv_mc (.data_in(ark_out),   .data_out(imc_out));

    localparam IDLE   = 3'd0,
               INIT   = 3'd1,
               ROUNDS = 3'd2,
               FINAL  = 3'd3,
               DONE   = 3'd4;
               
    reg [2:0] state;

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            state         <= IDLE;
            done          <= 1'b0;
            dec_round_num <= 4'd0;
            state_reg     <= 128'd0;
            plaintext     <= 128'd0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        dec_round_num <= 4'd0;
                        state         <= INIT;
                    end
                end

                INIT: begin // Vòng 0: AddRoundKey với Key14
                    state_reg     <= ciphertext ^ round_key;
                    dec_round_num <= 4'd1;
                    state         <= ROUNDS;
                end

                ROUNDS: begin // Vòng 1 -> 13
                    state_reg <= imc_out;
                    if (dec_round_num == 4'd13) begin
                        dec_round_num <= 4'd14;
                        state         <= FINAL;
                    end else begin
                        dec_round_num <= dec_round_num + 1'b1;
                    end
                end

                FINAL: begin // Vòng 14: Bỏ qua InvMixColumns
                    plaintext <= ark_out; // isb_out ^ Key0
                    done      <= 1'b1;
                    state     <= DONE;
                end

                DONE: begin
                    if (!start) state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule