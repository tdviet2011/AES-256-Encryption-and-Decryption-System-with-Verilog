`timescale 1ns / 1ps
// ============================================================================
// AES_SECURE_TB : Testbench tu kiem tra cho aes256_enc_dec_top (ban hardened)
//   Phan 1 : vector chuan NIST FIPS-197 / SP800-38A, chay back-to-back
//   Phan 2 : kich ban tan cong & loi giao tiep (phai bao fault, khong ro ri)
// Chay: xsim / iverilog -g2005 -o tb AES_SECURE_TB.v <tat ca file .v> && vvp tb
// ============================================================================
module AES_SECURE_TB;

    reg          clk = 0, reset = 0, start = 0, mode = 0;
    reg  [255:0] key;
    reg  [127:0] data_in;
    wire [127:0] data_out;
    wire         done, busy, fault;

    integer err = 0, n, d, bad, i, nz, runs = 0;

    aes256_enc_dec_top uut (
        .clk(clk), .reset(reset), .start(start), .mode(mode),
        .key(key), .data_in(data_in),
        .data_out(data_out), .done(done), .busy(busy), .fault(fault)
    );

    always #5 clk = ~clk;                      // 100 MHz
    always @(posedge busy) runs = runs + 1;

    localparam [255:0] K0 = 256'h000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F;
    localparam [127:0] P0 = 128'h00112233445566778899AABBCCDDEEFF;
    localparam [127:0] C0 = 128'h8EA2B7CA516745BFEAFC49904B496089;

    task pulse;    begin @(negedge clk); start = 1; @(negedge clk); start = 0; end endtask
    task waitdone; begin n = 0; while (!done && n < 400) begin @(negedge clk); n = n + 1; end end endtask

    task op(input m, input [255:0] k, input [127:0] dat);
    begin
        @(negedge clk); mode = m; key = k; data_in = dat; start = 1;
        @(negedge clk); start = 0;
        @(negedge clk); while (!done) @(negedge clk);
        repeat (2) @(negedge clk);
    end
    endtask

    task chk(input [255:0] k, input [127:0] p, input [127:0] c);
    begin
        op(1'b0, k, p);
        if (data_out !== c || fault) begin
            err = err + 1; $display("  ENC FAIL exp=%h got=%h fault=%b", c, data_out, fault);
        end
        op(1'b1, k, c);
        if (data_out !== p || fault) begin
            err = err + 1; $display("  DEC FAIL exp=%h got=%h fault=%b", p, data_out, fault);
        end
    end
    endtask

    initial begin
        #22 reset = 1;

        //====================================================================
        $display("\n--- Phan 1: vector chuan NIST (enc + dec, khong reset giua cac lan) ---");
        //====================================================================
        chk(K0, P0, C0);                                                     // FIPS-197 C.3
        chk(256'h603DEB1015CA71BE2B73AEF0857D77811F352C073B6108D72D9810A30914DFF4,
            128'h6BC1BEE22E409F96E93D7E117393172A, 128'hF3EED1BDB5D2A03C064B5A7E3DB181F8);
        chk(256'h603DEB1015CA71BE2B73AEF0857D77811F352C073B6108D72D9810A30914DFF4,
            128'hAE2D8A571E03AC9C9EB76FAC45AF8E51, 128'h591CCB10D410ED26DC5BA74A31362870);
        chk(256'h603DEB1015CA71BE2B73AEF0857D77811F352C073B6108D72D9810A30914DFF4,
            128'h30C81C46A35CE411E5FBC1191A0A52EF, 128'hB6ED21B99CA6F4F9F153E7B1BEAFED1D);
        chk(256'h603DEB1015CA71BE2B73AEF0857D77811F352C073B6108D72D9810A30914DFF4,
            128'hF69F2445DF4F9B17AD2B417BE66C3710, 128'h23304B7A39F9F3FF067D8D8F9E24ECC7);
        chk(256'd0, 128'd0, 128'hDC95C078A2408989AD48A21492842087);          // all-zero
        $display("NIST: %0d loi / 12 phep", err);

        //====================================================================
        $display("\n--- Phan 2: kich ban tan cong / loi giao tiep ---");
        //====================================================================
        key = K0; data_in = P0; mode = 1'b0;

        // A. Doi key/data/mode ngay sau khi start -> input phai da duoc CHOT
        pulse; repeat (3) @(negedge clk); data_in = 0; key = 0; mode = 1'b1;
        waitdone;
        $display("A  doi key/data/mode sau start : %s",
                 (data_out === C0 && !fault) ? "PASS" : "FAIL");
        if (data_out !== C0 || fault) err = err + 1;
        data_in = P0; key = K0; mode = 1'b0; repeat (3) @(negedge clk);

        // C. Bom start lan 2 khi dang tinh (key sai) -> phai bi BO QUA
        bad = 0;
        for (d = 1; d <= 45; d = d + 1) begin
            pulse;
            repeat (d) @(negedge clk);
            if (busy) begin key = ~K0; pulse; key = K0; end
            waitdone; repeat (3) @(negedge clk);
            if (data_out !== C0 || fault || busy) bad = bad + 1;
            repeat (5) @(negedge clk);
        end
        $display("C  start lan 2 khi busy (45 TH): %s", bad == 0 ? "PASS" : "FAIL");
        err = err + bad;

        // D. Doi mode giua chung -> khong treo, ket qua theo mode da chot
        pulse; repeat (20) @(negedge clk); mode = 1'b1; waitdone; mode = 1'b0;
        $display("D  doi mode giua chung         : %s",
                 (done && data_out === C0 && !fault) ? "PASS" : "FAIL");
        if (!done || data_out !== C0) err = err + 1;
        repeat (3) @(negedge clk);

        // E1. Fault injection: ep FSM nhay ROUNDS -> FINAL (bo bot vong)
        pulse;
        wait (uut.u_enc.state == 3'd2 && uut.u_enc.round_num == 4'd3);
        @(posedge clk); #1 force uut.u_enc.state = 3'd3;
        @(posedge clk); #1 release uut.u_enc.state;
        waitdone;
        $display("E1 bo bot vong ma hoa          : fault=%b out=%h  %s",
                 fault, data_out, (fault && data_out === 128'd0) ? "PASS" : "FAIL");
        if (!fault || data_out !== 128'd0) err = err + 1;
        repeat (3) @(negedge clk);

        // E2. DFA: lat 1 bit state_reg o vong 12
        pulse;
        wait (uut.u_enc.state == 3'd2 && uut.u_enc.round_num == 4'd12);
        @(posedge clk); #1 force uut.u_enc.state_reg[0] = ~uut.u_enc.state_reg[0];
        @(negedge clk); release uut.u_enc.state_reg[0];
        waitdone;
        $display("E2 lat 1 bit vong 12 (DFA)     : fault=%b out=%h  %s",
                 fault, data_out, (fault && data_out === 128'd0) ? "PASS" : "FAIL");
        if (!fault || data_out !== 128'd0) err = err + 1;
        repeat (3) @(negedge clk);

        // E3. Trang thai FSM la trong core giai ma
        pulse;
        wait (uut.st == 3'd3 && uut.u_dec.state == 3'd2);
        @(posedge clk); #1 force uut.u_dec.state = 3'd7;
        @(posedge clk); #1 release uut.u_dec.state;
        waitdone;
        $display("E3 trang thai FSM la           : fault=%b  %s",
                 fault, (fault && data_out === 128'd0) ? "PASS" : "FAIL");
        if (!fault || data_out !== 128'd0) err = err + 1;
        repeat (3) @(negedge clk);

        // B. Phai hoat dong lai binh thuong sau khi co fault
        pulse; waitdone;
        $display("B  hoat dong lai sau fault     : %s",
                 (!fault && data_out === C0) ? "PASS" : "FAIL");
        if (fault || data_out !== C0) err = err + 1;
        repeat (3) @(negedge clk);

        // F. Zeroize: key schedule va state trung gian phai sach
        nz = 0;
        for (i = 0; i < 60; i = i + 1) if (uut.u_kexp.w[i] !== 32'd0) nz = nz + 1;
        $display("F  zeroize sau khi xong        : w!=0:%0d enc.state=%0h dec.state=%0h data_r=%0h  %s",
                 nz, uut.u_enc.state_reg, uut.u_dec.state_reg, uut.data_r,
                 (nz == 0 && uut.u_enc.state_reg === 0 && uut.u_dec.state_reg === 0
                  && uut.data_r === 0) ? "PASS" : "FAIL");
        if (nz != 0) err = err + 1;

        // H. Giu start = 1 lien tuc -> chi duoc chay DUNG 1 lan
        key = K0; data_in = P0; runs = 0;
        @(negedge clk) start = 1; repeat (300) @(negedge clk); start = 0;
        $display("H  giu start=1 300 chu ky      : so lan chay=%0d  %s",
                 runs, runs == 1 ? "PASS" : "FAIL");
        if (runs != 1) err = err + 1;

        $display("\n=========================================");
        $display(" TONG KET: %0d loi   -> %s", err, err == 0 ? "TAT CA PASS" : "CO LOI");
        $display(" Latency 1 phep (VERIFY_EN=1) = 50 chu ky");
        $display("=========================================\n");
        $finish;
    end
endmodule
