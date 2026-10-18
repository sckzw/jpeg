#!/usr/bin/env python3
"""
tools/check_uninitialized_ff.py
Connects to QuestaSim Tcl server and audits signals/registers in DUT that have
uninitialized / undefined values ('x', 'X', 'z', 'Z').
"""
import sys
from pathlib import Path
from collections import defaultdict
from vsim_mcp import send_tcl_command

def examine_signal(sig):
    res = send_tcl_command(f"examine -radix bin {sig}")
    if res.get("status") == 0:
        return res.get("result", "").strip()
    return None

def main():
    print("=================================================================")
    print(" Auditing Uninitialized (X / Z) Signals in DUT (/jpeg_tool_tb/dut)")
    print("=================================================================")

    time_res = send_tcl_command("now")
    cur_time = time_res.get("now", time_res.get("result", "unknown"))
    print(f"Current Simulation Time: {cur_time} ps\n")

    # 1. 全信号の取得
    print("Fetching signals under /jpeg_tool_tb/dut/* ...")
    res = send_tcl_command("find signals -r /jpeg_tool_tb/dut/*")
    if res.get("status") != 0:
        print(f"Error fetching signals: {res.get('result')}")
        return 1

    all_signals = res.get("result", "").split()
    print(f"Total signals found in DUT: {len(all_signals)}")

    # 2. 値の取得と不定値 ('x', 'z') の検出
    uninitialized = []
    by_module = defaultdict(list)

    print("Examining signal values...")
    for idx, sig in enumerate(all_signals):
        val = examine_signal(sig)
        if val is None:
            continue
        
        # Check for X or Z in value (e.g. 1'bx, 16'bxxxxxxxx, etc.)
        val_lower = val.lower()
        if 'x' in val_lower or 'z' in val_lower:
            # 階層パスからモジュール名を抽出
            # 例: /jpeg_tool_tb/dut/u_quant/... -> u_quant
            parts = sig.split('/')
            # parts: ['', 'jpeg_tool_tb', 'dut', 'submodule', ...]
            submod = parts[3] if len(parts) > 3 else "top_ports_or_wires"
            uninitialized.append((sig, val, submod))
            by_module[submod].append((sig, val))

    print(f"\n=================================================================")
    print(f" AUDIT RESULT: Found {len(uninitialized)} signals with undefined (X/Z) values")
    print(f"=================================================================\n")

    for mod, sigs in sorted(by_module.items()):
        print(f"### Submodule: {mod} ({len(sigs)} undefined signals)")
        for sig, val in sorted(sigs):
            short_name = sig.replace(f"/jpeg_tool_tb/dut/{mod}/", "")
            print(f"  - {short_name:<40} = {val}")
        print()

    # レポートファイルにも保存
    report_file = Path("build/uninitialized_ff_report.txt")
    report_file.parent.mkdir(parents=True, exist_ok=True)
    with open(report_file, "w", encoding="utf-8") as f:
        f.write(f"QuestaSim DUT Undefined Signal Audit Report\n")
        f.write(f"Simulation Time: {cur_time} ps\n")
        f.write(f"Total undefined signals: {len(uninitialized)} / {len(all_signals)}\n\n")
        for mod, sigs in sorted(by_module.items()):
            f.write(f"[{mod}] ({len(sigs)})\n")
            for sig, val in sorted(sigs):
                f.write(f"  {sig} = {val}\n")
            f.write("\n")
    print(f"Saved full report to: {report_file.as_posix()}")

if __name__ == '__main__':
    sys.exit(main() or 0)
