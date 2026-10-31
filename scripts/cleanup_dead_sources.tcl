# ============================================================================
# cleanup_dead_sources.tcl
#   Go cac module CHET khoi project (file van con nguyen tren dia).
#
# CACH CHAY: trong Vivado Tcl Console, sau khi da chay add_new_sources.tcl:
#     cd D:/HOC_TAP/CODE_VHDL/Aes_system
#     source cleanup_dead_sources.tcl
#
# VI SAO CHUNG CHET:
#   Kien truc GOC:  aes256_enc_dec_top
#                     |- Aes256_FSM      -> Aes256_key_expansion_FSM + Aes_data_FSM
#                     |- Aes256_dec_FSM  -> Aes256_key_expansion_dec + aes256_data_dec_fsm
#   Moi nhanh co key expansion RIENG  => 2 ban sao khoa trong flip-flop (~3840 FF).
#
#   Kien truc MOI:  aes256_enc_dec_top
#                     |- Aes256_key_expansion_FSM   (MOT khoi, dung chung)
#                     |- Aes_data_FSM
#                     |- aes256_data_dec_fsm
#   Top goi thang cac loi, nen 2 wrapper tro thanh vo dung. Vivado van hien chung
#   nhu "root" rieng trong Design Sources vi khong ai goi -> nhin lung tung.
#
# LUU Y: remove_files CHI go khoi project, KHONG xoa file tren dia.
#        Muon quay lai kien truc cu thi them lai bang add_files.
# ============================================================================

set dead_rtl [list \
    Aes256_FSM.v \
    Aes256_dec_FSM.v \
    Aes256_key_expansion_dec.v \
]

# Hai TB nay chi test 2 wrapper da chet -> go luon, neu khong se loi "module khong ton tai"
set dead_tb [list \
    Aes256_FSM_tb.v \
    Aes256_dec_FSM_tb.v \
]

proc _drop {names} {
    set n 0
    foreach f $names {
        set objs [get_files -quiet "*/$f"]
        if {[llength $objs] == 0} {
            puts "  khong co trong project: $f"
            continue
        }
        remove_files $objs
        puts "  da go: $f"
        incr n
    }
    return $n
}

puts "\n=== Go RTL chet ==="
set a [_drop $dead_rtl]
puts "\n=== Go testbench chet ==="
set b [_drop $dead_tb]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "\n============================================================"
puts " Da go [expr {$a + $b}] file khoi project. File van con tren dia."
puts ""
puts " Sau buoc nay Design Sources con dung 4 root, moi root la MOT TOP"
puts " that su - day la co y, khong phai rac:"
puts "   aes256_enc_dec_top          ban hardened, khong mask"
puts "   aes256_enc_dec_top_cached   them cache key schedule"
puts "   aes256_masked_top           them masking chong DPA"
puts "   aes256_masked_top_mk        mask ca key expansion"
puts ""
puts " Vivado chi tong hop cay duoi top dang chon, cac root con lai"
puts " khong vao bitstream. Nho khoa top bang: synth_top <ten>"
puts "============================================================"
