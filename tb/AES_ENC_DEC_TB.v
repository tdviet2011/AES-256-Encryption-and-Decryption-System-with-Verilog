`timescale 1ns / 1ps
// ============================================================================
// AES_ENC_DEC_TB - testbench goc, DA SUA
//
// LOI CU: test 6..20 de gia tri mong doi la 128'h0 (placeholder chua dien),
//         nen log bao "ENCRYPT : FAIL" du phan cung tinh DUNG.
//         Vi du test 17 phan cung cho CFB8C9BB9C763062B57E24ACA2DB21B5 -
//         trung khop voi AES-256 chuan, nhung bi so voi 0 nen bao FAIL.
//
// DA SUA: dien gia tri mong doi that cho test 6..20, tinh bang thu vien AES
//         chuan (doc lap voi thiet ke, KHONG lay tu ket qua phan cung).
//         Them bo dem pass/fail va dong tong ket o cuoi.
// ============================================================================

module AES_ENC_DEC_TB;

    reg         clk;
    reg         reset;
    reg         start;
    reg         mode;         // 0: Encrypt, 1: Decrypt
    reg [255:0] key;
    reg [127:0] data_in;

    wire [127:0] data_out;
    wire         done;

    reg [127:0] original_plaintext;
    reg [127:0] temp_ciphertext;

    // Bo dem ket qua: truoc day testbench khong tong ket nen phai doc tay 40 dong log
    integer pass_cnt = 0;
    integer fail_cnt = 0;
    integer test_id  = 0;
    integer wd       = 0;

    // Instantiate Module Hợp Nhất
    aes256_enc_dec_top uut (
        .clk      (clk),
        .reset    (reset),
        .start    (start),
        .mode     (mode),
        .key      (key),
        .data_in  (data_in),
        .data_out (data_out),
        .done     (done)
    );

    // Clock 100MHz
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Task thực thi
    // LOI CU: task nay doi start/reset bang #50/#20/#10, tuc la dung tren cung
    //   luoi thoi gian voi canh len cua clk (ca hai deu la boi so 10ns).
    //   Day la race kinh dien cua testbench: trinh mo phong co the lay mau start
    //   TRUOC khi no kip len, nen xung start bi bo lo va wait(done) treo vinh vien.
    // DA SUA: moi kich thich deu doi tai CANH XUONG, cach xa canh lay mau.
    //   Them bo dem timeout de neu co treo thi bao loi chu khong quay vo han.
    task run_process;
    begin
        start = 0;
        reset = 0; repeat (5) @(negedge clk);
        reset = 1; repeat (2) @(negedge clk);

        start = 1; @(negedge clk);
        start = 0;

        wd = 0;
        while (!done && wd < 5000) begin @(negedge clk); wd = wd + 1; end
        if (wd >= 5000) begin
            $display("LOI: timeout - done khong bao gio len (test %0d)", test_id);
            fail_cnt = fail_cnt + 1;
        end
        repeat (5) @(negedge clk);
    end
    endtask

    task run_test;
    input [255:0] key_in;
    input [127:0] plain_in;
    input [127:0] expected_cipher;
begin
    key = key_in;
    original_plaintext = plain_in;
    test_id = test_id + 1;

    //================ Encrypt =================
    $display("\n========== TEST %0d ==========", test_id);
    $display("PLAINTEXT  = %h", plain_in);
    $display("KEY        = %h", key_in);

    mode    = 1'b0;
    data_in = plain_in;

    run_process();
    temp_ciphertext = data_out;

    $display("CIPHERTEXT = %h", temp_ciphertext);

    if(temp_ciphertext == expected_cipher) begin
        $display("ENCRYPT : PASS");
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("ENCRYPT : FAIL");
        $display("EXPECTED= %h", expected_cipher);
        fail_cnt = fail_cnt + 1;
    end

    //================ Decrypt =================
    mode    = 1'b1;
    data_in = temp_ciphertext;

    run_process();

    $display("DECRYPT  = %h", data_out);

    if(data_out == plain_in) begin
        $display("DECRYPT : PASS");
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("DECRYPT : FAIL");
        $display("EXPECTED= %h", plain_in);
        fail_cnt = fail_cnt + 1;
    end

    $display("==========================================");
    #100;
end
endtask
initial begin 
           #20;

//=====================================================
// Test 1 - NIST FIPS-197
//=====================================================
run_test(
256'h000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F,
128'h00112233445566778899AABBCCDDEEFF,
128'h8EA2B7CA516745BFEAFC49904B496089
);

//=====================================================
// Test 2 - NIST SP800-38A Block 1
//=====================================================
run_test(
256'h603DEB1015CA71BE2B73AEF0857D77811F352C073B6108D72D9810A30914DFF4,
128'h6BC1BEE22E409F96E93D7E117393172A,
128'hF3EED1BDB5D2A03C064B5A7E3DB181F8
);

//=====================================================
// Test 3 - NIST SP800-38A Block 2
//=====================================================
run_test(
256'h603DEB1015CA71BE2B73AEF0857D77811F352C073B6108D72D9810A30914DFF4,
128'hAE2D8A571E03AC9C9EB76FAC45AF8E51,
128'h591CCB10D410ED26DC5BA74A31362870
);

//=====================================================
// Test 4 - NIST SP800-38A Block 3
//=====================================================
run_test(
256'h603DEB1015CA71BE2B73AEF0857D77811F352C073B6108D72D9810A30914DFF4,
128'h30C81C46A35CE411E5FBC1191A0A52EF,
128'hB6ED21B99CA6F4F9F153E7B1BEAFED1D
);

//=====================================================
// Test 5 - NIST SP800-38A Block 4
//=====================================================
run_test(
256'h603DEB1015CA71BE2B73AEF0857D77811F352C073B6108D72D9810A30914DFF4,
128'hF69F2445DF4F9B17AD2B417BE66C3710,
128'h23304B7A39F9F3FF067D8D8F9E24ECC7
);

//=====================================================
// Test 6 - All Zero
//=====================================================
run_test(
256'h0000000000000000000000000000000000000000000000000000000000000000,
128'h00000000000000000000000000000000,
128'hDC95C078A2408989AD48A21492842087
);

//=====================================================
// Test 7 - All One
//=====================================================
run_test(
256'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
128'hD5F93D6D3311CB309F23621B02FBD5E2
);

//=====================================================
// Test 8
//=====================================================
run_test(
256'h0000000000000000000000000000000000000000000000000000000000000000,
128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
128'hACDACE8078A32B1A182BFA4987CA1347
);

//=====================================================
// Test 9
//=====================================================
run_test(
256'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
128'h00000000000000000000000000000000,
128'h4BF85F1B5D54ADBC307B0A048389ADCB
);

//=====================================================
// Test 10
//=====================================================
run_test(
256'h5555555555555555555555555555555555555555555555555555555555555555,
128'h55555555555555555555555555555555,
128'h345F77309858D7B78CEC9F93BFB5D362
);

//=====================================================
// Test 11
//=====================================================
run_test(
256'hAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA,
128'hAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA,
128'h00F0122444705643812EEC3DC6770693
);

//=====================================================
// Test 12
//=====================================================
run_test(
256'h000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F,
128'h000102030405060708090A0B0C0D0E0F,
128'h5A6E045708FB7196F02E553D02C3A692
);

//=====================================================
// Test 13
//=====================================================
run_test(
256'hFFFEFDFCFBFAF9F8F7F6F5F4F3F2F1F0EFEEEDECEBEAE9E8E7E6E5E4E3E2E1E0,
128'hFFFEFDFCFBFAF9F8F7F6F5F4F3F2F1F0,
128'h12654993D69F0A1C4CEB2262699A5FC8
);

//=====================================================
// Test 14
//=====================================================
run_test(
256'h0123456789ABCDEFFEDCBA987654321000112233445566778899AABBCCDDEEFF,
128'h89ABCDEF01234567FEDCBA9876543210,
128'h90B3CB9C314A599DB337A93971F92F2C
);

//=====================================================
// Test 15
//=====================================================
run_test(
256'h89ABCDEF0123456787654321FEDCBA9800112233445566778899AABBCCDDEEFF,
128'h0123456789ABCDEFFEDCBA9876543210,
128'hAB26A83B6148E775708A40F49B646DD2
);

//=====================================================
// Test 16
//=====================================================
run_test(
256'h13579BDF2468ACE0FEDCBA98765432100123456789ABCDEFFEDCBA9876543210,
128'hFEDCBA98765432100123456789ABCDEF,
128'h16AB0CD941C84DCC7372F608128B311F
);

//=====================================================
// Test 17
//=====================================================
run_test(
256'h8000000000000000000000000000000000000000000000000000000000000000,
128'h80000000000000000000000000000000,
128'hCFB8C9BB9C763062B57E24ACA2DB21B5
);

//=====================================================
// Test 18
//=====================================================
run_test(
256'h0000000000000000000000000000000000000000000000000000000000000001,
128'h00000000000000000000000000000001,
128'hC9D2B5DB15FD8902A6EBF478C3B78014
);

//=====================================================
// Test 19
//=====================================================
run_test(
256'hAA55AA55AA55AA55AA55AA55AA55AA55AA55AA55AA55AA55AA55AA55AA55AA55,
128'h55AA55AA55AA55AA55AA55AA55AA55AA,
128'hB3837695D9EEAB4EAD07A7012F4260D5
);

//=====================================================
// Test 20
//=====================================================
run_test(
256'h0000000000000000000000000000000000000000000000000000000000000002,
128'h00000000000000000000000000000002,
128'h3386C37D97490DB60459A741775DE705
);

$display("\n==========================================");
$display(" TONG KET: %0d PASS, %0d FAIL / %0d phep", pass_cnt, fail_cnt, pass_cnt+fail_cnt);
$display("==========================================\n");
$finish;
end
       
        
endmodule