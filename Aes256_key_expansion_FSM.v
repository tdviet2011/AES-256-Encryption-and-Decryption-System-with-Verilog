module Aes256_key_expansion_FSM(
input  wire         clk,
input  wire         reset,
input  wire         key_mode,
input  wire [255:0] key_in,
input  wire [3:0]   round_num,

output reg  [127:0] round_key,
output reg          flag
    );
    
    parameter IDLE = 2'd0;
    parameter CALC = 2'd1;
    parameter DONE = 2'd2;
    
    reg [1:0]  state;
    reg [3:0]  step_cal;
    reg [5:0]  idx;
    
    reg [31:0] w [0:59];
    reg [31:0] temp, w0, w1, w2, w3;
    integer i;
    
    always @(posedge clk or negedge reset) begin
    
        if (!reset) begin
        state    <= IDLE;
        flag     <= 1'b0;
        step_cal <= 4'd0;
        idx      <= 6'd0;
        for (i = 0; i < 60; i = i + 1) w[i] <= 32'd0;
    end else begin
            case (state) 
                IDLE : begin
                            flag <= 1'b0;
                       if(key_mode) begin
                                            w[0] <= key_in[255:224]; w[1] <= key_in[223:192];
                                            w[2] <= key_in[191:160]; w[3] <= key_in[159:128];
                                            w[4] <= key_in[127:96];  w[5] <= key_in[95:64];
                                            w[6] <= key_in[63:32];   w[7] <= key_in[31:0];          
                                            step_cal <= 4'd0;
                                            idx      <= 6'd8;
                                            state    <= CALC;                           
                                     end                                     
                       end
                CALC : begin
                            if ((idx % 8) == 0)
                                            temp = SubWordFunc(RotWord(w[idx-1])) ^ GetRcon(idx >> 3);
                                            else if ((idx % 8) == 4)
                                            temp = SubWordFunc(w[idx-1]);
                                             else
                                            temp = w[idx-1];
                                            
                                w0 = w[idx-8] ^ temp;
                                w1 = w[idx-7] ^ w0;
                                w2 = w[idx-6] ^ w1;
                                w3 = w[idx-5] ^ w2;
                                
                                w[idx]   <= w0;
                                w[idx+1] <= w1;
                                w[idx+2] <= w2;
                                w[idx+3] <= w3;
                                
                                if (step_cal == 4'd12) begin
                                                       state <= DONE;  // Hoàn tất 13 bước
                                                       end else begin
                                                                    step_cal <= step_cal + 1'b1;
                                                                    idx      <= idx + 3'd4;
                                end
                       end
                       DONE: begin
                                flag <= 1'b1; // Báo hiệu đã tạo xong khóa
                                if (!key_mode) begin
                                               state <= IDLE; // Quay về chờ nếu key_mode bị kéo xuống 0
                                               end
                             end
            
            default: state <= IDLE;
            endcase
        end
    
    end
    
    
    
   
    function [31:0] SubWordFunc;
    input [31:0] word_in;
    begin
        SubWordFunc = {SBox(word_in[31:24]), SBox(word_in[23:16]), SBox(word_in[15:8]), SBox(word_in[7:0])};
    end
endfunction

    function [31:0] RotWord;
        input [31:0] word;
        begin
            RotWord = {word[23:0], word[31:24]};
        end
    endfunction
    
    function [31:0] GetRcon;
    input [3:0] round;
    begin
        case(round)
            4'd1: GetRcon = 32'h01000000; 4'd2: GetRcon = 32'h02000000;
            4'd3: GetRcon = 32'h04000000; 4'd4: GetRcon = 32'h08000000;
            4'd5: GetRcon = 32'h10000000; 4'd6: GetRcon = 32'h20000000;
            4'd7: GetRcon = 32'h40000000;
            default: GetRcon = 32'h00000000;
        endcase
    end
endfunction
    
    
   
function [7:0] SBox;
    input  [7:0] in;
    begin
    case(in)
        8'h00: SBox = 8'h63; 8'h01: SBox = 8'h7C; 8'h02: SBox = 8'h77; 8'h03: SBox = 8'h7B; 8'h04: SBox = 8'hF2; 8'h05: SBox = 8'h6B; 8'h06: SBox = 8'h6F; 8'h07: SBox = 8'hC5;
        8'h08: SBox = 8'h30; 8'h09: SBox = 8'h01; 8'h0A: SBox = 8'h67; 8'h0B: SBox = 8'h2B; 8'h0C: SBox = 8'hFE; 8'h0D: SBox = 8'hD7; 8'h0E: SBox = 8'hAB; 8'h0F: SBox = 8'h76;
        8'h10: SBox = 8'hCA; 8'h11: SBox = 8'h82; 8'h12: SBox = 8'hC9; 8'h13: SBox = 8'h7D; 8'h14: SBox = 8'hFA; 8'h15: SBox = 8'h59; 8'h16: SBox = 8'h47; 8'h17: SBox = 8'hF0;
        8'h18: SBox = 8'hAD; 8'h19: SBox = 8'hD4; 8'h1A: SBox = 8'hA2; 8'h1B: SBox = 8'hAF; 8'h1C: SBox = 8'h9C; 8'h1D: SBox = 8'hA4; 8'h1E: SBox = 8'h72; 8'h1F: SBox = 8'hC0;
        8'h20: SBox = 8'hB7; 8'h21: SBox = 8'hFD; 8'h22: SBox = 8'h93; 8'h23: SBox = 8'h26; 8'h24: SBox = 8'h36; 8'h25: SBox = 8'h3F; 8'h26: SBox = 8'hF7; 8'h27: SBox = 8'hCC; 
        8'h28: SBox = 8'h34; 8'h29: SBox = 8'hA5; 8'h2A: SBox = 8'hE5; 8'h2B: SBox = 8'hF1; 8'h2C: SBox = 8'h71; 8'h2D: SBox = 8'hD8; 8'h2E: SBox = 8'h31; 8'h2F: SBox = 8'h15;
        8'h30: SBox = 8'h04; 8'h31: SBox = 8'hC7; 8'h32: SBox = 8'h23; 8'h33: SBox = 8'hC3; 8'h34: SBox = 8'h18; 8'h35: SBox = 8'h96; 8'h38: SBox = 8'h07; 8'h39: SBox = 8'h12;
        8'h3A: SBox = 8'h80; 8'h3B: SBox = 8'hE2; 8'h3C: SBox = 8'hEB; 8'h3D: SBox = 8'h27; 8'h3E: SBox = 8'hB2; 8'h3F: SBox = 8'h75; 8'h40: SBox = 8'h09; 8'h41: SBox = 8'h83;
        8'h42: SBox = 8'h2C; 8'h43: SBox = 8'h1A; 8'h44: SBox = 8'h1B; 8'h45: SBox = 8'h6E; 8'h46: SBox = 8'h5A; 8'h47: SBox = 8'hA0; 8'h48: SBox = 8'h52; 8'h49: SBox = 8'h3B;
        8'h4A: SBox = 8'hD6; 8'h4B: SBox = 8'hB3; 8'h4C: SBox = 8'h29; 8'h4D: SBox = 8'hE3; 8'h4E: SBox = 8'h2F; 8'h4F: SBox = 8'h84; 8'h50: SBox = 8'h53; 8'h51: SBox = 8'hD1;
        8'h52: SBox = 8'h00; 8'h53: SBox = 8'hED; 8'h54: SBox = 8'h20; 8'h55: SBox = 8'hFC; 8'h56: SBox = 8'hB1; 8'h57: SBox = 8'h5B; 8'h58: SBox = 8'h6A; 8'h59: SBox = 8'hCB;
        8'h5A: SBox = 8'hBE; 8'h5B: SBox = 8'h39; 8'h5C: SBox = 8'h4A; 8'h5D: SBox = 8'h4C; 8'h5E: SBox = 8'h58; 8'h5F: SBox = 8'hCF; 8'h60: SBox = 8'hD0; 8'h61: SBox = 8'hEF;
        8'h62: SBox = 8'hAA; 8'h63: SBox = 8'hFB; 8'h64: SBox = 8'h43; 8'h65: SBox = 8'h4D; 8'h66: SBox = 8'h33; 8'h67: SBox = 8'h85; 8'h68: SBox = 8'h45; 8'h69: SBox = 8'hF9;
        8'h6A: SBox = 8'h02; 8'h6B: SBox = 8'h7F; 8'h6C: SBox = 8'h50; 8'h6D: SBox = 8'h3C; 8'h6E: SBox = 8'h9F; 8'h6F: SBox = 8'hA8; 8'h70: SBox = 8'h51; 8'h71: SBox = 8'hA3;
        8'h72: SBox = 8'h40; 8'h73: SBox = 8'h8F; 8'h74: SBox = 8'h92; 8'h75: SBox = 8'h9D; 8'h76: SBox = 8'h38; 8'h77: SBox = 8'hF5; 8'h78: SBox = 8'hBC; 8'h79: SBox = 8'hB6;
        8'h7A: SBox = 8'hDA; 8'h7B: SBox = 8'h21; 8'h7C: SBox = 8'h10; 8'h7D: SBox = 8'hFF; 8'h7E: SBox = 8'hF3; 8'h7F: SBox = 8'hD2; 8'h80: SBox = 8'hCD; 8'h81: SBox = 8'h0C;
        8'h82: SBox = 8'h13; 8'h83: SBox = 8'hEC; 8'h84: SBox = 8'h5F; 8'h85: SBox = 8'h97; 8'h86: SBox = 8'h44; 8'h87: SBox = 8'h17; 8'h88: SBox = 8'hC4; 8'h89: SBox = 8'hA7;
        8'h8A: SBox = 8'h7E; 8'h8B: SBox = 8'h3D; 8'h8C: SBox = 8'h64; 8'h8D: SBox = 8'h5D; 8'h8E: SBox = 8'h19; 8'h8F: SBox = 8'h73; 8'h90: SBox = 8'h60; 8'h91: SBox = 8'h81;
        8'h92: SBox = 8'h4F; 8'h93: SBox = 8'hDC; 8'h94: SBox = 8'h22; 8'h95: SBox = 8'h2A; 8'h96: SBox = 8'h90; 8'h97: SBox = 8'h88; 8'h98: SBox = 8'h46; 8'h99: SBox = 8'hEE;
        8'h9A: SBox = 8'hB8; 8'h9B: SBox = 8'h14; 8'h9C: SBox = 8'hDE; 8'h9D: SBox = 8'h5E; 8'h9E: SBox = 8'h0B; 8'h9F: SBox = 8'hDB; 8'hA0: SBox = 8'hE0; 8'hA1: SBox = 8'h32;
        8'hA2: SBox = 8'h3A; 8'hA3: SBox = 8'h0A; 8'hA4: SBox = 8'h49; 8'hA5: SBox = 8'h06; 8'hA6: SBox = 8'h24; 8'hA7: SBox = 8'h5C; 8'hA8: SBox = 8'hC2; 8'hA9: SBox = 8'hD3;
        8'hAA: SBox = 8'hAC; 8'hAB: SBox = 8'h62; 8'hAC: SBox = 8'h91; 8'hAD: SBox = 8'h95; 8'hAE: SBox = 8'hE4; 8'hAF: SBox = 8'h79; 8'hB0: SBox = 8'hE7; 8'hB1: SBox = 8'hC8;
        8'hB2: SBox = 8'h37; 8'hB3: SBox = 8'h6D; 8'hB4: SBox = 8'h8D; 8'hB5: SBox = 8'hD5; 8'hB6: SBox = 8'h4E; 8'hB7: SBox = 8'hA9; 8'hB8: SBox = 8'h6C; 8'hB9: SBox = 8'h56;
        8'hBA: SBox = 8'hF4; 8'hBB: SBox = 8'hEA; 8'hBC: SBox = 8'h65; 8'hBD: SBox = 8'h7A; 8'hBE: SBox = 8'hAE; 8'hBF: SBox = 8'h08; 8'hC0: SBox = 8'hBA; 8'hC1: SBox = 8'h78;
        8'hC2: SBox = 8'h25; 8'hC3: SBox = 8'h2E; 8'hC4: SBox = 8'h1C; 8'hC5: SBox = 8'hA6; 8'hC6: SBox = 8'hB4; 8'hC7: SBox = 8'hC6; 8'hC8: SBox = 8'hE8; 8'hC9: SBox = 8'hDD;
        8'hCA: SBox = 8'h74; 8'hCB: SBox = 8'h1F; 8'hCC: SBox = 8'h4B; 8'hCD: SBox = 8'hBD; 8'hCE: SBox = 8'h8B; 8'hCF: SBox = 8'h8A; 8'hD0: SBox = 8'h70; 8'hD1: SBox = 8'h3E;
        8'hD2: SBox = 8'hB5; 8'hD3: SBox = 8'h66; 8'hD4: SBox = 8'h48; 8'hD5: SBox = 8'h03; 8'hD6: SBox = 8'hF6; 8'hD7: SBox = 8'h0E; 8'hD8: SBox = 8'h61; 8'hD9: SBox = 8'h35;
        8'hDA: SBox = 8'h57; 8'hDB: SBox = 8'hB9; 8'hDC: SBox = 8'h86; 8'hDD: SBox = 8'hC1; 8'hDE: SBox = 8'h1D; 8'hDF: SBox = 8'h9E; 8'hE0: SBox = 8'hE1; 8'hE1: SBox = 8'hF8;
        8'hE2: SBox = 8'h98; 8'hE3: SBox = 8'h11; 8'hE4: SBox = 8'h69; 8'hE5: SBox = 8'hD9; 8'hE6: SBox = 8'h8E; 8'hE7: SBox = 8'h94; 8'hE8: SBox = 8'h9B; 8'hE9: SBox = 8'h1E;
        8'hEA: SBox = 8'h87; 8'hEB: SBox = 8'hE9; 8'hEC: SBox = 8'hCE; 8'hED: SBox = 8'h55; 8'hEE: SBox = 8'h28; 8'hEF: SBox = 8'hDF; 8'hF0: SBox = 8'h8C; 8'hF1: SBox = 8'hA1;
        8'hF2: SBox = 8'h89; 8'hF3: SBox = 8'h0D; 8'hF4: SBox = 8'hBF; 8'hF5: SBox = 8'hE6; 8'hF6: SBox = 8'h42; 8'hF7: SBox = 8'h68; 8'hF8: SBox = 8'h41; 8'hF9: SBox = 8'h99;
        8'hFA: SBox = 8'h2D; 8'hFB: SBox = 8'h0F; 8'hFC: SBox = 8'hB0; 8'hFD: SBox = 8'h54; 8'hFE: SBox = 8'hBB; 8'hFF: SBox = 8'h16; 8'h36: SBox = 8'h05;
        8'h37: SBox = 8'h9A;
        default: SBox = 8'h00;
    endcase
end
endfunction
            always @(*) begin
                case(round_num)
                    4'd0 : round_key = {w[0],  w[1],  w[2],  w[3]};
                    4'd1 : round_key = {w[4],  w[5],  w[6],  w[7]};
                    4'd2 : round_key = {w[8],  w[9],  w[10], w[11]};
                    4'd3 : round_key = {w[12], w[13], w[14], w[15]};
                    4'd4 : round_key = {w[16], w[17], w[18], w[19]};
                    4'd5 : round_key = {w[20], w[21], w[22], w[23]};
                    4'd6 : round_key = {w[24], w[25], w[26], w[27]};
                    4'd7 : round_key = {w[28], w[29], w[30], w[31]};
                    4'd8 : round_key = {w[32], w[33], w[34], w[35]};
                    4'd9 : round_key = {w[36], w[37], w[38], w[39]};
                    4'd10: round_key = {w[40], w[41], w[42], w[43]};
                    4'd11: round_key = {w[44], w[45], w[46], w[47]};
                    4'd12: round_key = {w[48], w[49], w[50], w[51]};
                    4'd13: round_key = {w[52], w[53], w[54], w[55]};
                    4'd14: round_key = {w[56], w[57], w[58], w[59]};
                    default: round_key = 128'd0;
                endcase 
            end
endmodule
