# ============================================================================
# add_new_sources.tcl
#   Them toan bo file RTL va testbench moi vao project Vivado.
#
# CACH CHAY: mo project trong Vivado, vao Tcl Console go:
#     cd D:/HOC_TAP/CODE_VHDL/Aes_system
#     source add_new_sources.tcl
#   (dung dau / chu khong phai \ trong duong dan Tcl)
#
# Script nay KHONG xoa gi, chi them file va dat top tuong minh.
# Thu muc sources_1/new/backup_original co duoi .bak nen Vivado khong doc -
#   TUYET DOI khong doi duoi thanh .v, se trung ten module.
# ============================================================================

set root [file normalize [pwd]]
set src  "$root/Aes_system.srcs/sources_1/new"
set sim  "$root/Aes_system.srcs/sim_1/new"

# ---- RTL moi -------------------------------------------------------------
set rtl_files [list \
    aes_prng.v \
    aes_masked_sbox.v \
    aes_masked_sbox_bram.v \
    aes_masked_core.v \
    Aes256_masked_top.v \
    aes_masked_core_mk.v \
    Aes256_masked_top_mk.v \
    Aes256_key_expansion_masked.v \
    Aes256_key_expansion_cached.v \
    Aes256_ENC_DEC_top_cached.v \
]

# ---- Testbench moi -------------------------------------------------------
set tb_files [list \
    AES_SECURE_TB.v \
    AES_MASKED_TB.v \
    AES_CACHED_TB.v \
    AES_MASKED_MK_TB.v \
]

proc _add {fileset dir names} {
    set added 0
    set have [get_files -quiet -of_objects [get_filesets $fileset]]
    foreach n $names {
        set p "$dir/$n"
        if {![file exists $p]} {
            puts "  BO QUA (khong thay file): $n"
            continue
        }
        if {[llength [get_files -quiet "*/$n"]] > 0} {
            puts "  da co san: $n"
            continue
        }
        add_files -norecurse -fileset [get_filesets $fileset] $p
        puts "  da them:   $n"
        incr added
    }
    return $added
}

puts "\n=== Them RTL vao sources_1 ==="
set n1 [_add sources_1 $src $rtl_files]
puts "\n=== Them testbench vao sim_1 ==="
set n2 [_add sim_1 $sim $tb_files]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

# ---- Dat top TUONG MINH --------------------------------------------------
# Project gio co 4 module top ung vien. De TopAutoSet = TRUE thi Vivado tu chon,
# va no se chon sai. Phai khoa lai.
set_property top aes256_enc_dec_top [get_filesets sources_1]
set_property top_auto_set 0         [get_filesets sources_1]
set_property top AES_ENC_DEC_TB     [get_filesets sim_1]
set_property top_auto_set 0         [get_filesets sim_1]

# ---- Ham tien ich: doi top nhanh ----------------------------------------
proc synth_top {name} {
    set_property top $name [get_filesets sources_1]
    set_property top_auto_set 0 [get_filesets sources_1]
    update_compile_order -fileset sources_1
    puts "Top tong hop -> $name"
}
proc sim_top {name} {
    set_property top $name [get_filesets sim_1]
    set_property top_auto_set 0 [get_filesets sim_1]
    update_compile_order -fileset sim_1
    puts "Top mo phong -> $name"
}

puts "\n============================================================"
puts " Da them $n1 file RTL, $n2 testbench."
puts ""
puts " Doi top tong hop:   synth_top aes256_enc_dec_top"
puts "                     synth_top aes256_enc_dec_top_cached"
puts "                     synth_top aes256_masked_top"
puts "                     synth_top aes256_masked_top_mk"
puts ""
puts " Doi top mo phong:   sim_top AES_ENC_DEC_TB      (20 vector, 40 phep)"
puts "                     sim_top AES_SECURE_TB       (NIST + 9 kich ban tan cong)"
puts "                     sim_top AES_MASKED_TB       (them kiem tra bat bien mask)"
puts "                     sim_top AES_CACHED_TB"
puts "                     sim_top AES_MASKED_MK_TB"
puts ""
puts " Luu y: top mo phong va top tong hop phai KHOP NHAU."
puts "   AES_SECURE_TB  -> aes256_enc_dec_top"
puts "   AES_MASKED_TB  -> aes256_masked_top"
puts "============================================================"
