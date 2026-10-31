`timescale 1ns / 1ps
// ============================================================================
// AES_MASKED_MK_TB : kiem tra aes256_masked_top_mk
//   Phan 1: vector chuan NIST
//   Phan 2: cache key schedule (chi tinh lai khi khoa doi) + zeroize
//   Phan 3: bat bien mask VOI ROUND KEY DA MASK, va key schedule khong luu tho
//   Phan 4: fault injection
//
// Doi SYNC_RAM=1 de kiem tra ban dung Block RAM (bang S-box doc dong bo).
// LUU Y: phan fault dung force/release -> Vivado xsim ho tro day du; iverilog
//        se canh bao "procedural continuous assignments..." (van chay dung).
// ============================================================================
module AES_MASKED_MK_TB;
    parameter SYNC_RAM = 0;          // 0 = LUTRAM, 1 = Block RAM

    reg          clk = 0, reset = 0, start = 0, mode = 0, seed_en = 0, zeroize = 0;
    reg  [255:0] key;
    reg  [127:0] data_in;
    reg  [63:0]  seed_in = 0;
    wire [127:0] data_out;
    wire         done, busy, fault, key_cached;

    integer i, d, n, bad, err = 0, cyc, recalc = 0, nz, lat1 = 0, lat2 = 0, difm = 0, runs = 0;
    reg [127:0] m_prev, snap_d, snap_m;
    reg         got;

    aes256_masked_top_mk #(.SYNC_RAM(SYNC_RAM)) uut (
        .clk(clk), .reset(reset), .start(start), .mode(mode), .key(key),
        .data_in(data_in), .zeroize(zeroize), .seed_en(seed_en), .seed_in(seed_in),
        .data_out(data_out), .done(done), .busy(busy), .fault(fault), .key_cached(key_cached));

    always #5 clk = ~clk;
    always @(posedge busy) runs = runs + 1;
    always @(posedge clk)
        if (reset && uut.u_kexp.st == 3'd1 && uut.u_kexp.kcnt == 0) recalc = recalc + 1;
    // Chup trang thai ngay sau AddRoundKey vong 0
    always @(posedge clk)
        if (reset && uut.u_core.st == 4'd5 && uut.u_core.cnt5 == 0
                  && uut.u_core.round_num == 1 && !got) begin
            snap_d <= uut.u_core.dstate; snap_m <= uut.u_core.mstate; got <= 1'b1;
        end

    localparam [255:0] KA  = 256'h000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F;
    localparam [127:0] PA  = 128'h00112233445566778899AABBCCDDEEFF;
    localparam [127:0] CA  = 128'h8EA2B7CA516745BFEAFC49904B496089;
    localparam [127:0] RK0 = 128'h000102030405060708090A0B0C0D0E0F;   // round key 0 cua KA
    localparam [255:0] KB  = 256'h603DEB1015CA71BE2B73AEF0857D77811F352C073B6108D72D9810A30914DFF4;
    localparam [127:0] PB  = 128'h6BC1BEE22E409F96E93D7E117393172A;
    localparam [127:0] CB  = 128'hF3EED1BDB5D2A03C064B5A7E3DB181F8;

    task ns;       begin seed_in = {$random, $random}; seed_en = 1; @(negedge clk); seed_en = 0; end endtask
    task pulse;    begin @(negedge clk); start = 1; @(negedge clk); start = 0; end endtask
    task waitdone; begin n = 0; while (!done && n < 9000) begin @(negedge clk); n = n + 1; end end endtask

    task op(input m, input [255:0] k, input [127:0] dat);
    begin
        ns;
        @(negedge clk); mode = m; key = k; data_in = dat; start = 1;
        @(negedge clk); start = 0;
        cyc = 1; while (!done && cyc < 9000) begin @(negedge clk); cyc = cyc + 1; end
        repeat (3) @(negedge clk);
    end
    endtask

    initial begin
        #22 reset = 1;

        $display("\n--- Phan 1: vector chuan NIST (SYNC_RAM=%0d) ---", SYNC_RAM);
        op(1'b0, KA, PA); if (data_out !== CA || fault) begin err=err+1; $display("   ENC A FAIL got=%h", data_out); end
        op(1'b1, KA, CA); if (data_out !== PA || fault) begin err=err+1; $display("   DEC A FAIL"); end
        op(1'b0, KB, PB); if (data_out !== CB || fault) begin err=err+1; $display("   ENC B FAIL"); end
        op(1'b1, KB, CB); if (data_out !== PB || fault) begin err=err+1; $display("   DEC B FAIL"); end
        $display("NIST: %0d loi / 4 phep  %s", err, err == 0 ? "PASS" : "FAIL");

        $display("\n--- Phan 2: cache key schedule ---");
        recalc = 0;
        for (i = 0; i < 15; i = i + 1) begin
            op(1'b0, KA, PA ^ i);
            if (i == 0) lat1 = cyc; else if (i == 1) lat2 = cyc;
        end
        $display("2a 15 block cung khoa     : tinh lai %0d lan  %s", recalc, recalc <= 1 ? "PASS" : "FAIL");
        $display("   latency dau=%0d, sau=%0d -> tiet kiem %0d chu ky/block", lat1, lat2, lat1 - lat2);
        if (recalc > 1) err = err + 1;

        $display("\n--- Phan 3: masking that su hoat dong ---");
        difm = 0; m_prev = 128'hX;
        for (i = 0; i < 15; i = i + 1) begin
            got = 1'b0;
            op(1'b0, KA, PA);
            if (data_out !== CA) begin err = err + 1; $display("   ket qua sai lan %0d", i); end
            if ((snap_d ^ snap_m) !== (PA ^ RK0)) begin
                err = err + 1; $display("   BAT BIEN MASK SAI lan %0d", i);
            end
            if (snap_d === (PA ^ RK0)) begin err = err + 1; $display("   MAT NA = 0 lan %0d", i); end
            if (i > 0 && snap_m !== m_prev) difm = difm + 1;
            m_prev = snap_m;
        end
        $display("3a bat bien dstate^mstate == that (15 lan) : PASS neu khong co dong SAI o tren");
        $display("3b mat na doi giua cac lan                 : %0d/14  %s", difm, difm == 14 ? "PASS" : "FAIL");
        if (difm != 14) err = err + 1;
        nz = 0; for (i = 0; i < 60; i = i + 1) if (uut.u_kexp.wm[i] === 32'd0) nz = nz + 1;
        $display("3c key schedule: so word co mat na = 0     : %0d/60  %s",
                 nz, nz == 0 ? "PASS (khong luu round key tho)" : "FAIL");
        if (nz != 0) err = err + 1;

        $display("\n--- Phan 4: fault injection / loi giao tiep ---");
        key = KA; data_in = PA; mode = 1'b0;

        ns; pulse; repeat (5) @(negedge clk); data_in = 0; key = 0; mode = 1'b1; waitdone;
        $display("A  doi key/data/mode sau start  : %s", (data_out === CA && !fault) ? "PASS" : "FAIL");
        if (data_out !== CA || fault) err = err + 1;
        data_in = PA; key = KA; mode = 1'b0; repeat (3) @(negedge clk);

        bad = 0;
        for (d = 1; d <= 12; d = d + 1) begin
            ns; pulse; repeat (d * 60) @(negedge clk);
            if (busy) begin key = ~KA; pulse; key = KA; end
            waitdone; repeat (3) @(negedge clk);
            if (data_out !== CA || fault || busy) bad = bad + 1;
            repeat (5) @(negedge clk);
        end
        $display("C  start lan 2 khi busy (12 TH) : %s", bad == 0 ? "PASS" : "FAIL");
        err = err + bad;

        ns; pulse; wait (uut.u_core.st == 4'd5 && uut.u_core.round_num == 4'd3);
        @(posedge clk); #1 force uut.u_core.st = 4'd7;
        @(posedge clk); #1 release uut.u_core.st;
        waitdone;
        $display("E1 bo bot vong                  : fault=%b  %s", fault,
                 (fault && data_out === 128'd0) ? "PASS" : "FAIL");
        if (!fault || data_out !== 128'd0) err = err + 1;
        repeat (3) @(negedge clk);

        ns; pulse; wait (uut.u_core.st == 4'd6 && uut.u_core.round_num == 4'd7);
        @(posedge clk); #1 force uut.u_core.dstate[0] = ~uut.u_core.dstate[0];
        @(negedge clk); release uut.u_core.dstate[0];
        waitdone;
        $display("E2 lat 1 bit du lieu (DFA)      : fault=%b  %s", fault,
                 (fault && data_out === 128'd0) ? "PASS" : "FAIL");
        if (!fault || data_out !== 128'd0) err = err + 1;
        repeat (3) @(negedge clk);

        ns; pulse; wait (uut.u_core.st == 4'd6 && uut.u_core.round_num == 4'd5);
        force uut.rkey[0] = ~uut.rkey[0];
        repeat (40) @(negedge clk); release uut.rkey[0];
        waitdone;
        $display("E3 lat 1 bit round key          : fault=%b  %s", fault,
                 (fault && data_out === 128'd0) ? "PASS" : "FAIL");
        if (!fault || data_out !== 128'd0) err = err + 1;
        repeat (3) @(negedge clk);

        ns; pulse; waitdone;
        $display("B  hoat dong lai sau fault      : %s", (!fault && data_out === CA) ? "PASS" : "FAIL");
        if (fault || data_out !== CA) err = err + 1;
        repeat (3) @(negedge clk);

        runs = 0;
        @(negedge clk) start = 1; repeat (2500) @(negedge clk); start = 0;
        $display("H  giu start=1 2500 chu ky      : so lan chay=%0d  %s", runs, runs == 1 ? "PASS" : "FAIL");
        if (runs != 1) err = err + 1;
        repeat (5) @(negedge clk);

        @(negedge clk) zeroize = 1; @(negedge clk) zeroize = 0; repeat (2) @(negedge clk);
        nz = 0;
        for (i = 0; i < 60; i = i + 1)
            if (uut.u_kexp.wd[i] !== 32'd0 || uut.u_kexp.wm[i] !== 32'd0) nz = nz + 1;
        $display("F  zeroize cuoi phien           : w!=0:%0d cache=%0h valid=%b  %s",
                 nz, uut.u_kexp.key_cache, uut.u_kexp.key_valid,
                 (nz == 0 && uut.u_kexp.key_cache === 0 && uut.u_kexp.key_valid === 0) ? "PASS" : "FAIL");
        if (nz != 0) err = err + 1;

        op(1'b0, KA, PA);
        $display("G  chay lai sau zeroize         : %s", (data_out === CA && !fault) ? "PASS" : "FAIL");
        if (data_out !== CA) err = err + 1;

        $display("\n=========================================");
        $display(" SYNC_RAM=%0d  TONG KET: %0d loi -> %s", SYNC_RAM, err, err == 0 ? "TAT CA PASS" : "CO LOI");
        $display("=========================================\n");
        $finish;
    end
endmodule
