`timescale 1ns / 1ps
// ============================================================================
// AES_CACHED_TB : kiem tra aes256_enc_dec_top_cached
//   - Key schedule chi duoc tinh lai KHI KHOA DOI
//   - Ket qua van dung chuan NIST
//   - zeroize xoa sach khoa khoi flip-flop
// ============================================================================
module AES_CACHED_TB;
    reg          clk = 0, reset = 0, start = 0, mode = 0, zeroize = 0;
    reg  [255:0] key;
    reg  [127:0] data_in;
    wire [127:0] data_out;
    wire         done, busy, fault, key_cached;

    integer i, err = 0, cyc, recalc = 0, nz, lat1 = 0, lat2 = 0, r1, r3;

    aes256_enc_dec_top_cached uut (
        .clk(clk), .reset(reset), .start(start), .mode(mode), .key(key),
        .data_in(data_in), .zeroize(zeroize), .data_out(data_out),
        .done(done), .busy(busy), .fault(fault), .key_cached(key_cached));

    always #5 clk = ~clk;
    // Dem so lan THUC SU chay lai key schedule
    always @(posedge clk)
        if (reset && uut.u_kexp.state == 2'd1 && uut.u_kexp.step_cal == 0) recalc = recalc + 1;

    localparam [255:0] KA = 256'h000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F;
    localparam [127:0] PA = 128'h00112233445566778899AABBCCDDEEFF;
    localparam [127:0] CA = 128'h8EA2B7CA516745BFEAFC49904B496089;
    localparam [255:0] KB = 256'h603DEB1015CA71BE2B73AEF0857D77811F352C073B6108D72D9810A30914DFF4;
    localparam [127:0] PB = 128'h6BC1BEE22E409F96E93D7E117393172A;
    localparam [127:0] CB = 128'hF3EED1BDB5D2A03C064B5A7E3DB181F8;

    task op(input m, input [255:0] k, input [127:0] dat);
    begin
        @(negedge clk); mode = m; key = k; data_in = dat; start = 1;
        @(negedge clk); start = 0;
        cyc = 1; while (!done && cyc < 4000) begin @(negedge clk); cyc = cyc + 1; end
        repeat (3) @(negedge clk);
    end
    endtask

    initial begin
        #22 reset = 1;

        // 1. 30 block CUNG MOT KHOA -> chi duoc tinh key schedule dung 1 lan
        recalc = 0;
        for (i = 0; i < 30; i = i + 1) begin
            op(1'b0, KA, PA ^ i);
            if (i == 0) lat1 = cyc; else if (i == 1) lat2 = cyc;
        end
        r1 = recalc;
        $display("1. 30 block cung khoa     : tinh key schedule %0d lan  %s", r1, r1 == 1 ? "PASS" : "FAIL");
        $display("   latency block dau=%0d, block sau=%0d -> tiet kiem %0d chu ky/block",
                 lat1, lat2, lat1 - lat2);
        if (r1 != 1) err = err + 1;

        // 2. Ket qua van dung chuan NIST (ca enc va dec)
        op(1'b0, KA, PA); if (data_out !== CA || fault) begin err=err+1; $display("   ENC A FAIL"); end
        op(1'b1, KA, CA); if (data_out !== PA || fault) begin err=err+1; $display("   DEC A FAIL"); end
        op(1'b0, KB, PB); if (data_out !== CB || fault) begin err=err+1; $display("   ENC B FAIL"); end
        op(1'b1, KB, CB); if (data_out !== PB || fault) begin err=err+1; $display("   DEC B FAIL"); end
        $display("2. vector chuan NIST      : %s", err == 0 ? "PASS" : "FAIL");

        // 3. Doi khoa qua lai -> phai tinh lai moi lan (cache chi giu 1 khoa)
        recalc = 0;
        for (i = 0; i < 6; i = i + 1) op(1'b0, (i % 2) ? KB : KA, PA);
        r3 = recalc;
        $display("3. doi khoa A/B/A/B 6 lan : tinh lai %0d lan  %s", r3, r3 == 6 ? "PASS" : "FAIL");
        if (r3 != 6) err = err + 1;

        // 4. zeroize: khoa phai bien mat khoi flip-flop
        op(1'b0, KA, PA);
        @(negedge clk) zeroize = 1; @(negedge clk) zeroize = 0; repeat (2) @(negedge clk);
        nz = 0; for (i = 0; i < 60; i = i + 1) if (uut.u_kexp.w[i] !== 32'd0) nz = nz + 1;
        $display("4. zeroize cuoi phien     : w!=0:%0d cache=%0h valid=%b  %s",
                 nz, uut.u_kexp.key_cache, uut.u_kexp.key_valid,
                 (nz == 0 && uut.u_kexp.key_cache === 0 && uut.u_kexp.key_valid === 0) ? "PASS" : "FAIL");
        if (nz != 0) err = err + 1;

        // 5. Sau zeroize van chay dung (phai tinh lai tu dau)
        op(1'b0, KA, PA);
        $display("5. chay lai sau zeroize   : %s", (data_out === CA && !fault) ? "PASS" : "FAIL");
        if (data_out !== CA) err = err + 1;

        $display("\n========= TONG KET: %0d loi -> %s =========\n",
                 err, err == 0 ? "TAT CA PASS" : "CO LOI");
        $finish;
    end
endmodule
