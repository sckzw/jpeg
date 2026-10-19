# =====================================================================
# tools/vsim_ai_debug.tcl
# QuestaSim / ModelSim Tcl Socket Server for AI-assisted Debugging
# =====================================================================

puts "================================================================="
puts " \[vsim_ai_debug\] Initializing QuestaSim AI Debug Environment"
puts "================================================================="

# 1. 便利なヘルパーコマンドの定義
proc now {} {
    if {[info exists ::now]} {
        return $::now
    }
    set t "0"
    catch {set t [examine -radix time \$now]}
    return $t
}

proc json_escape {str} {
    return [string map [list \
        "\\" "\\\\" \
        "\"" "\\\"" \
        "\n" "\\n"  \
        "\r" "\\r"  \
        "\t" "\\t"  \
    ] $str]
}

proc save_cov {{filename "build/coverage/ai_debug.ucdb"}} {
    set dir [file dirname $filename]
    if {$dir ne "." && $dir ne ""} {
        catch {file mkdir $dir}
    }
    set st [catch {coverage save -directive -cvg -codeAll $filename} res]
    if {$st == 0} {
        puts "\[vsim_ai_debug\] Coverage saved to $filename"
        return "Coverage saved to $filename"
    } else {
        puts "\[vsim_ai_debug ERROR\] Failed to save coverage: $res"
        error $res
    }
}

# Coverage auto-save on exit if coverage is active
if {[catch {coverage attribute} _cov_attr] == 0} {
    set cov_file "build/coverage/ai_debug.ucdb"
    catch {file mkdir [file dirname $cov_file]}
    catch {coverage save -onexit -directive -cvg -codeAll $cov_file}
    puts "\[vsim_ai_debug\] Coverage onexit save registered: $cov_file"
}

# 2. 波形ロギングの事前登録 (全階層の信号をWLFへ記録)
puts "\[vsim_ai_debug\] Registering full waveform logging: log -r /* ..."
if {[catch {log -r /*} err]} {
    puts "\[vsim_ai_debug WARNING\] log -r /* warning: $err"
} else {
    puts "\[vsim_ai_debug\] Waveform logging enabled."
}

# 3. 波形ウィンドウ (Wave Window) の表示と初期信号の追加
catch {view wave}
catch {view structure}
catch {view signals}

catch {
    add wave -divider "Testbench Control"
    add wave -radix hex /*/clk /*/rst_n
    add wave -divider "APB Registers"
    add wave -radix hex /*/psel /*/penable /*/pwrite /*/paddr /*/pwdata /*/prdata
    add wave -divider "DUT Top"
    add wave -radix hex /*/dut/*
}

# 4. クライアント接続・コマンド受信・実行処理
proc vsim_handle_client {sock addr port} {
    fconfigure $sock -buffering line -blocking 0 -encoding utf-8
    fileevent $sock readable [list vsim_process_cmd $sock]
}

proc vsim_process_cmd {sock} {
    if {[eof $sock]} {
        close $sock
        return
    }

    gets $sock line
    set line [string trim $line]
    if {[string length $line] == 0} {
        return
    }

    # 実行する Tcl コマンドと引数をそのまま Transcript に出力
    puts $line

    # 受信したコマンドをQuestaSimグローバル名前空間で実行
    set status [catch {uplevel #0 $line} result]

    # 結果がある場合やエラー時はそのまま出力
    if {$status != 0} {
        puts "** ERROR: $result"
    } elseif {[string length $result] > 0} {
        puts "# $result"
    }

    # シミュレーション現在時刻
    set cur_time [now]

    # JSONレスポンスの生成
    set esc_res [json_escape $result]
    set resp "{\"status\": $status, \"now\": \"$cur_time\", \"result\": \"$esc_res\"}"
    
    catch {
        puts $sock $resp
        flush $sock
    }
}

# 5. ホストアドレス・ポート番号設定とサーバーソケットのバインド
set VSIM_HOST "127.0.0.1"
if {[info exists env(VSIM_HOST)]} {
    set VSIM_HOST $env(VSIM_HOST)
}

set VSIM_PORT 5678
if {[info exists env(VSIM_PORT)]} {
    set VSIM_PORT $env(VSIM_PORT)
}

if {[catch {socket -server vsim_handle_client -myaddr $VSIM_HOST $VSIM_PORT} srv_sock]} {
    puts "\[vsim_ai_debug ERROR\] Failed to start server on ${VSIM_HOST}:${VSIM_PORT}: $srv_sock"
} else {
    puts "-----------------------------------------------------------------"
    puts " \[vsim_ai_debug\] AI Debug Socket Server is READY on ${VSIM_HOST}:${VSIM_PORT}"
    puts " - run -all is NOT executed (simulation stopped at 0ns)."
    puts " - All signals are logged via 'log -r /*'."
    puts " - MCP Server can now connect and control the simulation."
    puts "-----------------------------------------------------------------"
}
