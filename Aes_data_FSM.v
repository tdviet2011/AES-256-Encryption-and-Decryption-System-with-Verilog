module Aes_data_FSM(
    input  wire         clk,
    input  wire         reset,
    input  wire         start,
    
    input  wire [127:0] plaintext,
    input  wire [127:0] round_key,
    
    output reg  [3:0]   round_num,
    output reg  [127:0] ciphertext,
    output reg          done    
    );
    parameter IDLE   = 3'd0; 
    parameter INIT   = 3'd1;
    parameter ROUNDS = 3'd2; 
    parameter FINAL  = 3'd3; 
    parameter DONE   = 3'd4;
    reg  [127:0] state_reg;
    wire [127:0] sb_out;
    wire [127:0] sr_out;
    wire [127:0] mc_out;
    
    Aes_sub_bytes Sub_bytes (
        .data_in (state_reg),
        .data_out(sb_out)
    );
    
    Aes_shift_rows Shift_rows (
        .data_in (sb_out),      
        .data_out(sr_out)
    );
    
    Aes_mix_columns Mix_columns (
        .data_in (sr_out),      
        .data_out(mc_out)
    );
    reg [2:0] state;
    
    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            state      <= IDLE;
            done       <= 1'b0;
            round_num  <= 4'd0;
            state_reg  <= 128'd0;
            ciphertext <= 128'd0;
        end else begin
 
                    case(state)
                        IDLE   : begin
                                    done <= 1'b0;
                                        if (start) begin
                                            round_num <= 4'd0;
                                            state     <= INIT;
                                        end
                                 end
                        INIT   : begin
                                        state_reg <= plaintext ^ round_key;
                                        round_num <= 4'd1;
                                        state     <= ROUNDS;
                                 end
                        ROUNDS : begin
                                        state_reg <= mc_out ^ round_key;
                                                if (round_num == 4'd13) begin
                                                                    round_num <= 4'd14;
                                                                    state     <= FINAL;
                                                                        end else begin
                                                                                round_num <= round_num + 1'b1;
                                                                                end
                               end
                        FINAL  : begin
                                        ciphertext <= sr_out ^ round_key;
                                        done       <= 1'b1;
                                        state      <= DONE;
                               end   
                        DONE   : begin
                                 if (!start) state <= IDLE;
                               end    
                            default: state <= IDLE;           
                    endcase
                 end       
    end
endmodule
