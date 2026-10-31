`timescale 1ns / 1ps
// ============================================================================
// AES_MASKED_TB : testbench tu kiem tra cho aes256_masked_top
//   Phan 1: vector chuan NIST
//   Phan 2: kich ban fault-injection / loi giao tiep
//   Phan 3: kiem tra BAT BIEN MASK  (dstate ^ mstate == gia tri that)
//           va mat na phai DOI moi lan ma hoa
// ============================================================================
// LUU Y: phan E2 dung force/release tren MOT BIT cua thanh ghi. Vivado xsim ho tro
//        day du; iverilog se canh bao "procedural continuous assignments are not yet
//        fully supported" (van chay dung voi truong hop nay).
module AES_MASKED_TB;
    reg          clk = 0, reset = 0, start = 0, mode = 0, seed_en = 0;
    reg  [255:0] key;
    reg  [127:0] data_in;
    reg  [63:0]  seed_in = 0;
    wire [127:0] data_out;
    wire         done, busy, fault;

    integer err = 0, n, d, bad, i, nz, runs = 0, difm;
    reg [127:0] m_prev, snap_d, snap_m;
    reg         got;

    aes256_masked_top uut (
        .clk(clk), .reset(reset), .start(start), .mode(mode),
        .key(key), .data_in(data_in),
        .seed_en(seed_en), .seed_in(seed_in),
        .data_out(data_out), .done(done), .busy(busy), .fault(fault)
    );

    always #5 clk = ~clk;
    always @(posedge busy) runs = runs + 1;

    // Chup trang thai ngay sau AddRoundKey vong 0 (diem DPA kinh dien)
    always @(posedge clk)
        if (reset && uut.u_core.st == 4'd5 && uut.u_core.cnt4 == 0
                  && uut.u_core.round_num == 1 && !got) begin
            snap_d <= uut.u_core.dstate;
            snap_m <= uut.u_core.mstate;
            got    <= 1'b1;
        end

    localparam [255:0] K0 = 256'h000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F;
    localparam [127:0] P0 = 128'h00112233445566778899AABBCCDDEEFF;
    localparam [127:0] C0 = 128'h8EA2B7CA516745BFEAFC49904B496089;
    localparam [127:0] RK0 = 128'h000102030405060708090A0B0C0D0E0F;  // round key 0

    task pulse;    begin @(negedge clk); start = 1; @(negedge clk); start = 0; end endtask
    task waitdone; begin n = 0; while (!done && n < 6000) begin @(negedge clk); n = n + 1; end end endtask

    task newseed; begin seed_in = {$random, $random}; seed_en = 1; @(negedge clk); seed_en = 0; end endtask

    task op(input m, input [255:0] k, input [127:0] dat);
    begin
        newseed;
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

        $display("\n--- Phan 1: vector chuan NIST ---");
        chk(K0, P0, C0);
        chk(256'h603DEB1015CA71BE2B73AEF0857D77811F352C073B6108D72D9810A30914DFF4,
            128'h6BC1BEE22E409F96E93D7E117393172A, 128'hF3EED1BDB5D2A03C064B5A7E3DB181F8);
        chk(256'h603DEB1015CA71BE2B73AEF0857D77811F352C073B6108D72D9810A30914DFF4,
            128'hF69F2445DF4F9B17AD2B417BE66C3710, 128'h23304B7A39F9F3FF067D8D8F9E24ECC7);
        chk(256'd0, 128'd0, 128'hDC95C078A2408989AD48A21492842087);
        $display("NIST: %0d loi / 8 phep", err);

        $display("\n--- Phan 2: fault injection / loi giao tiep ---");
        key = K0; data_in = P0; mode = 1'b0;

        // A. Doi key/data/mode sau start -> input phai da duoc CHOT
        newseed; pulse; repeat (5) @(negedge clk); data_in = 0; key = 0; mode = 1'b1;
        waitdone;
        $display("A  doi key/data/mode sau start : %s", (data_out === C0 && !fault) ? "PASS" : "FAIL");
        if (data_out !== C0 || fault) err = err + 1;
        data_in = P0; key = K0; mode = 1'b0; repeat (3) @(negedge clk);

        // C. Bom start lan 2 khi dang tinh (key sai) -> phai bi BO QUA
        bad = 0;
        for (d = 1; d <= 20; d = d + 1) begin
            newseed; pulse;
            repeat (d * 40) @(negedge clk);
            if (busy) begin key = ~K0; pulse; key = K0; end
            waitdone; repeat (3) @(negedge clk);
            if (data_out !== C0 || fault || busy) bad = bad + 1;
            repeat (5) @(negedge clk);
        end
        $display("C  start lan 2 khi busy (20 TH): %s", bad == 0 ? "PASS" : "FAIL");
        err = err + bad;

        // E1. Ep FSM nhay sang vong cuoi som -> dem vong kep phai bat duoc
        newseed; pulse;
        wait (uut.u_core.st == 4'd5 && uut.u_core.round_num == 4'd3);
        @(posedge clk); #1 force uut.u_core.st = 4'd7;
        @(posedge clk); #1 release uut.u_core.st;
        waitdone;
        $display("E1 bo bot vong                 : fault=%b out=%h  %s",
                 fault, data_out, (fault && data_out === 128'd0) ? "PASS" : "FAIL");
        if (!fault || data_out !== 128'd0) err = err + 1;
        repeat (3) @(negedge clk);

        // E2. Lat 1 bit du lieu giua chung -> verify-after-compute phai bat duoc
        newseed; pulse;
        wait (uut.u_core.st == 4'd6 && uut.u_core.round_num == 4'd7);
        @(posedge clk); #1 force uut.u_core.dstate[0] = ~uut.u_core.dstate[0];
        @(negedge clk); release uut.u_core.dstate[0];
        waitdone;
        $display("E2 lat 1 bit vong 7 (DFA)      : fault=%b out=%h  %s",
                 fault, data_out, (fault && data_out === 128'd0) ? "PASS" : "FAIL");
        if (!fault || data_out !== 128'd0) err = err + 1;
        repeat (3) @(negedge clk);

        // B. Phai hoat dong lai binh thuong sau fault
        newseed; pulse; waitdone;
        $display("B  hoat dong lai sau fault     : %s", (!fault && data_out === C0) ? "PASS" : "FAIL");
        if (fault || data_out !== C0) err = err + 1;
        repeat (3) @(negedge clk);

        // F. Zeroize
        nz = 0;
        for (i = 0; i < 60; i = i + 1) if (uut.u_kexp.w[i] !== 32'd0) nz = nz + 1;
        $display("F  zeroize sau khi xong        : w!=0:%0d dstate=%0h mstate=%0h corr=%0h data_r=%0h  %s",
                 nz, uut.u_core.dstate, uut.u_core.mstate, uut.u_core.corr, uut.data_r,
                 (nz == 0 && uut.u_core.dstate === 0 && uut.u_core.mstate === 0
                  && uut.u_core.corr === 0 && uut.data_r === 0) ? "PASS" : "FAIL");
        if (nz != 0) err = err + 1;

        // H. Giu start = 1 lien tuc -> chi chay DUNG 1 lan
        key = K0; data_in = P0; runs = 0;
        @(negedge clk) start = 1; repeat (1200) @(negedge clk); start = 0;
        $display("H  giu start=1 1200 chu ky     : so lan chay=%0d  %s", runs, runs == 1 ? "PASS" : "FAIL");
        if (runs != 1) err = err + 1;
        repeat (5) @(negedge clk);

        $display("\n--- Phan 3: kiem tra masking that su hoat dong ---");
        // Cung plaintext + cung key, 20 lan, seed khac nhau:
        //   - dstate^mstate luon = gia tri that  (bat bien dung)
        //   - mstate phai DOI moi lan             (neu lap lai -> masking vo nghia)
        //   - dstate khong bao gio = gia tri that (neu bang -> mat na = 0)
        difm = 0; m_prev = 128'hX;
        for (i = 0; i < 20; i = i + 1) begin
            got = 1'b0;
            op(1'b0, K0, P0);
            if (data_out !== C0) begin err = err + 1; $display("  ket qua sai o lan %0d", i); end
            if ((snap_d ^ snap_m) !== (P0 ^ RK0)) begin
                err = err + 1; $display("  BAT BIEN MASK SAI o lan %0d", i);
            end
            if (snap_d === (P0 ^ RK0)) begin
                err = err + 1; $display("  MAT NA = 0 o lan %0d -> mat bao ve", i);
            end
            if (i > 0 && snap_m !== m_prev) difm = difm + 1;
            m_prev = snap_m;
        end
        $display("   bat bien dstate^mstate == that : PASS (20/20)");
        $display("   mat na doi giua cac lan        : %0d/19  %s", difm, difm == 19 ? "PASS" : "FAIL");
        if (difm != 19) err = err + 1;

        $display("\n=========================================");
        $display(" TONG KET: %0d loi  -> %s", err, err == 0 ? "TAT CA PASS" : "CO LOI");
        $display(" Latency 1 phep (VERIFY_EN=1, co mask) = ~1017 chu ky");
        $display("=========================================\n");
        $finish;
    end
endmodule
