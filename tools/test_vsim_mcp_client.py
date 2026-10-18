#!/usr/bin/env python3
"""
Quick self-test script for QuestaSim Tcl socket server and MCP functions.
"""
import subprocess
import time
import sys
from pathlib import Path
from vsim_mcp import send_tcl_command

ROOT = Path(__file__).resolve().parents[1]

def main():
    print("Testing connection to QuestaSim Tcl Server (port 5678)...")
    res = send_tcl_command("now")
    print(f"now: {res}")
    
    res = send_tcl_command("examine -radix hex /jpeg_tool_tb/clk")
    print(f"clk: {res}")
    
    res = send_tcl_command("run 100 ns")
    print(f"run 100ns: {res}")
    
    res = send_tcl_command("now")
    print(f"now after run: {res}")

if __name__ == '__main__':
    main()
