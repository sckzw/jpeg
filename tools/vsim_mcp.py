#!/usr/bin/env python3
"""
tools/vsim_mcp.py - QuestaSim Remote Control MCP Server for AI Debugging
"""
import json
import os
import socket
import sys
from typing import List, Optional
from mcp.server.fastmcp import FastMCP

# Initialize FastMCP Server
mcp = FastMCP("QuestaSim Controller")

VSIM_HOST = os.environ.get("VSIM_HOST", "127.0.0.1")
VSIM_PORT = int(os.environ.get("VSIM_PORT", 5678))


def send_tcl_command(cmd: str, timeout: float = 30.0) -> dict:
    """Send a single Tcl command to QuestaSim socket server and parse the JSON response."""
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(timeout)
    try:
        s.connect((VSIM_HOST, VSIM_PORT))
        # Ensure single line command
        cmd_clean = cmd.replace("\r", " ").replace("\n", " ").strip()
        s.sendall((cmd_clean + "\n").encode("utf-8"))

        chunks = []
        while True:
            chunk = s.recv(4096)
            if not chunk:
                break
            chunks.append(chunk)
            if b"\n" in chunk:
                break

        raw_resp = b"".join(chunks).decode("utf-8", errors="replace").strip()
        if not raw_resp:
            return {"status": -1, "now": "unknown", "result": "Empty response from QuestaSim"}
        return json.loads(raw_resp)
    except socket.timeout:
        return {
            "status": -1,
            "now": "unknown",
            "result": f"Socket timeout ({timeout}s) waiting for QuestaSim response. The command might still be executing.",
        }
    except Exception as e:
        return {
            "status": -1,
            "now": "unknown",
            "result": f"Connection error to QuestaSim at {VSIM_HOST}:{VSIM_PORT}: {e}. Is QuestaSim running with tools/vsim_ai_debug.tcl?",
        }
    finally:
        s.close()


@mcp.tool()
def vsim_exec(command: str) -> str:
    """
    Execute any arbitrary Tcl command directly in QuestaSim console.
    Example commands:
      - 'step'
      - 'checkpoint'
      - 'bp sim/jpeg_tool_tb.sv 515'
      - 'describe /jpeg_tool_tb/dut'
    """
    res = send_tcl_command(command)
    status_str = "OK" if res.get("status") == 0 else f"ERROR({res.get('status')})"
    return f"[{status_str} at {res.get('now', '0')}]\n{res.get('result', '')}"


@mcp.tool()
def vsim_run(time_spec: str = "100 ns") -> str:
    """
    Run simulation for a specified duration.
    NOTE: Do NOT use '-all' unless a breakpoint is set, to avoid hanging the simulation.
    :param time_spec: Duration with unit, e.g., '100 ns', '10 us', '1 ms', '1000'
    """
    res = send_tcl_command(f"run {time_spec}")
    if res.get("status") == 0:
        return f"Ran {time_spec}. Simulation time now: {res.get('now')}"
    return f"Failed to run {time_spec}: {res.get('result')}"


@mcp.tool()
def vsim_run_cycles(cycles: int = 100, clk_period_ns: float = 3.90625) -> str:
    """
    Run simulation for a given number of clock cycles (default ~256MHz, 3.906ns).
    :param cycles: Number of clock cycles to advance
    :param clk_period_ns: Clock period in nanoseconds (default 3.90625ns = 256MHz)
    """
    total_ns = cycles * clk_period_ns
    return vsim_run(f"{total_ns:.2f} ns")


@mcp.tool()
def vsim_examine(signal: str, radix: str = "hex") -> str:
    """
    Read the current value of a signal, register, or net.
    :param signal: Hierarchical path, e.g. '/jpeg_tool_tb/dut/state' or 'dut/rst_n'
    :param radix: Representation format: 'hex', 'dec', 'bin', 'unsigned', 'ascii', 'sym'
    """
    res = send_tcl_command(f"examine -radix {radix} {signal}")
    if res.get("status") == 0:
        return f"{signal} = {res.get('result')} (at {res.get('now')})"
    return f"Examine error for {signal}: {res.get('result')}"


@mcp.tool()
def vsim_examine_multiple(signals: List[str], radix: str = "hex") -> str:
    """
    Read values of multiple signals in a single call.
    :param signals: List of signal paths
    :param radix: Format: 'hex', 'dec', 'bin', 'unsigned'
    """
    lines = []
    for sig in signals:
        res = send_tcl_command(f"examine -radix {radix} {sig}")
        val = res.get("result", "ERR") if res.get("status") == 0 else f"ERROR: {res.get('result')}"
        lines.append(f"{sig} = {val}")
    return "\n".join(lines)


@mcp.tool()
def vsim_add_wave(signals: str, radix: str = "hex") -> str:
    """
    Add signal(s) to the QuestaSim GUI waveform window.
    :param signals: Signal path or wildcard (e.g. '/jpeg_tool_tb/dut/u_quant/*' or '/jpeg_tool_tb/clk')
    :param radix: Radix format: 'hex', 'dec', 'bin', 'unsigned', 'ascii'
    """
    cmd = f"add wave -radix {radix} {signals}"
    res = send_tcl_command(cmd)
    if res.get("status") == 0:
        return f"Successfully added to waveform: {signals}"
    return f"Failed to add wave {signals}: {res.get('result')}"


@mcp.tool()
def vsim_delete_wave(signals: str = "*") -> str:
    """
    Delete signal(s) from the QuestaSim GUI waveform window.
    :param signals: Signal path or pattern to delete (e.g. '/jpeg_tool_tb/psel' or '*' for all signals)
    """
    cmd = f"delete wave {signals}"
    res = send_tcl_command(cmd)
    if res.get("status") == 0:
        return f"Successfully deleted from waveform: {signals}"
    return f"Failed to delete wave {signals}: {res.get('result')}"


@mcp.tool()
def vsim_clear_wave() -> str:
    """
    Clear all signals from the QuestaSim GUI waveform window.
    """
    return vsim_delete_wave("*")


@mcp.tool()
def vsim_get_now() -> str:
    """Get the current simulation time."""
    res = send_tcl_command("now")
    return f"Current simulation time: {res.get('now', res.get('result', 'unknown'))}"


@mcp.tool()
def vsim_wave_zoom_full() -> str:
    """Fit waveform window to display the entire simulated time range (Zoom Full)."""
    res = send_tcl_command("wave zoomfull")
    return "Wave zoom full executed." if res.get("status") == 0 else f"Error: {res.get('result')}"


@mcp.tool()
def vsim_find_signals(pattern: str = "/*") -> str:
    """
    Search for signals/nets/registers matching a wildcard pattern.
    :param pattern: e.g. '/jpeg_tool_tb/dut/*', '*valid*', '*state*'
    """
    res = send_tcl_command(f"find signals -r {pattern}")
    if res.get("status") == 0:
        sigs = res.get("result", "").split()
        if len(sigs) > 50:
            return f"Found {len(sigs)} signals. Showing first 50:\n" + "\n".join(sigs[:50]) + "\n... (truncated)"
        return "\n".join(sigs) if sigs else "No matching signals found."
    return f"Find error: {res.get('result')}"


@mcp.tool()
def vsim_restart() -> str:
    """
    Restart the simulation back to time 0, and re-arm full waveform logging (log -r /*).
    """
    res = send_tcl_command("restart -f")
    if res.get("status") != 0:
        return f"Restart failed: {res.get('result')}"
    # Re-enable waveform logging
    log_res = send_tcl_command("log -r /*")
    return f"Restarted to 0ns. Waveform logging re-armed: {log_res.get('result', 'OK')}"


@mcp.tool()
def vsim_set_breakpoint(location: str) -> str:
    """
    Set a simulation breakpoint.
    :param location: e.g. 'sim/jpeg_tool_tb.sv:520' or 'dut/u_quant/q_valid==1'
    """
    res = send_tcl_command(f"bp {location}")
    if res.get("status") == 0:
        return f"Breakpoint set: {location} (id: {res.get('result')})"
    return f"Failed to set breakpoint: {res.get('result')}"


if __name__ == "__main__":
    mcp.run()
