#!/usr/bin/env python3
"""PNG/JPEG CLI using Questa Sim simulation of jpeg_top for entropy and transform processing."""
import argparse
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
from PIL import Image
from jpeg_cpu import parse
from generate_vectors import jpeg
from reference import huffman

ROOT = Path(__file__).resolve().parents[1]
BUILD_DIR = ROOT / 'build'
TEMP_DIR = BUILD_DIR / 'tmp'
LOGS_DIR = BUILD_DIR / 'logs'
TOOL_BUILT = ROOT / 'build/work/_tool_built'
FORMATS = {'444': 0, '422': 1, '420': 2}


def dimensions(w, h, fmt):
    hs, vs = (1 if fmt == 0 else 2), (2 if fmt == 2 else 1)
    return [(w, h)] + [((w+hs-1)//hs, (h+vs-1)//vs)]*2


def write_table(job, kind, ident, words):
    (job/f'table{kind}_{ident}.bin').write_bytes(struct.pack('<'+'I'*len(words), *words))


def run_rtl(job, mode, w, h, fmt, select, input_size, restart_interval=0, gui=False):
    (job/'config.txt').write_text(f'{mode} {w} {h} {fmt} {select} {input_size} {restart_interval}\n')
    if not TOOL_BUILT.is_file():
        raise ValueError('RTL simulator is not built; run make jpeg-tools first')
    vsim = os.environ.get('VSIM', 'vsim')
    work = Path(os.environ.get('WORK', ROOT / 'build/work')).as_posix()
    TEMP_DIR.mkdir(parents=True, exist_ok=True)
    LOGS_DIR.mkdir(parents=True, exist_ok=True)
    log_path = job / 'transcript.log'
    wlf_path = job / 'vsim.wlf'
    ai_debug = gui or (os.environ.get('VSIM_AI_DEBUG', '0').lower() in ('1', 'true', 'yes'))

    coverage = os.environ.get('COVERAGE', '0').lower() in ('1', 'true', 'yes')
    coverage_dir = Path(os.environ.get('COVERAGE_DIR', ROOT / 'build/coverage'))
    cov_args = ['-coverage'] if coverage else []
    cov_ucdb = (coverage_dir / 'jpeg_tool_tb.ucdb').as_posix()
    cov_do = ['-do', f'coverage save -onexit -directive -cvg -codeAll {cov_ucdb}'] if coverage else []
    if coverage:
        coverage_dir.mkdir(parents=True, exist_ok=True)

    if ai_debug:
        tcl_script = (ROOT / 'tools/vsim_ai_debug.tcl').as_posix()
        # AI Debug mode: +acc enabled, GUI mode, waveform logging via log -r /*, no run -all, Tcl socket server
        cmd = [vsim, '-gui', '-l', log_path.as_posix(), '-wlf', wlf_path.as_posix(), '-voptargs=+acc', '-lib', work] + cov_args + [
               'jpeg_tool_tb', f'+JOB_DIR={job.as_posix()}'] + cov_do + ['-do', f'source {tcl_script}']
        print(f"[jpeg_tool] Launching QuestaSim in AI Debug mode (+acc, GUI, socket server)...")
        print(f"[jpeg_tool] Job directory: {job.as_posix()}")
        subprocess.run(cmd, check=True)
    else:
        # Normal fast mode: no +acc for max optimization speed, -c batch mode, run -all; quit
        cmd = [vsim, '-c', '-l', log_path.as_posix(), '-wlf', wlf_path.as_posix(), '-lib', work] + cov_args + [
               'jpeg_tool_tb', f'+JOB_DIR={job.as_posix()}'] + cov_do + ['-do', 'run -all; quit']
        try:
            subprocess.run(cmd, capture_output=True, text=True, check=True)
        except subprocess.CalledProcessError:
            if log_path.is_file():
                print(log_path.read_text(encoding='utf-8', errors='ignore'), file=sys.stderr)
            raise

    if log_path.is_file():
        import shutil
        shutil.copy2(log_path, LOGS_DIR / 'jpeg_tool.log')
        text = log_path.read_text(encoding='utf-8', errors='ignore')
        for line in text.splitlines():
            line_clean = line.lstrip('#').strip()
            if line_clean.startswith('RTL encode cycles=') or line_clean.startswith('RTL decode cycles='):
                print(line_clean)
    if wlf_path.is_file():
        import shutil
        shutil.copy2(wlf_path, LOGS_DIR / 'jpeg_tool.wlf')




def subsample(plane, w, h, hs, vs):
    """Box average with edge extension, rounding half upward."""
    cw, ch = (w+hs-1)//hs, (h+vs-1)//vs
    return bytes((sum(plane[min(y*vs+dy,h-1)*w+min(x*hs+dx,w-1)]
                      for dy in range(vs) for dx in range(hs)) + hs*vs//2)//(hs*vs)
                 for y in range(ch) for x in range(cw))


def encode(source, destination, quant=16, sampling='444', gui=False):
    if not 1 <= quant <= 255:
        raise ValueError('quant must be in 1..255')
    with Image.open(source) as image:
        if image.format != 'PNG':
            raise ValueError('encode input must be PNG')
        w, h = image.size
        if not 1 <= w <= 65535 or not 1 <= h <= 65535:
            raise ValueError('image dimensions must be in 1..65535')
        # PNG transparency is composited onto white before RGB -> YCbCr.
        rgba = image.convert('RGBA')
        background = Image.new('RGBA', image.size, (255, 255, 255, 255))
        rgb = Image.alpha_composite(background, rgba).convert('RGB')
        planes = [channel.tobytes() for channel in rgb.convert('YCbCr').split()]
    fmt = FORMATS[sampling]
    hs, vs = (1 if fmt == 0 else 2), (2 if fmt == 2 else 1)
    if fmt:
        planes[1:] = [subsample(p, w, h, hs, vs) for p in planes[1:]]
    dc_counts = [0]*16
    dc_counts[3] = 12
    dc_symbols = list(range(12))
    ac_counts = [0]*16
    ac_symbols = [0, 240] + [r*16+n for r in range(16) for n in range(1, 11)]
    ac_counts[7] = len(ac_symbols)
    dc, _ = huffman(dc_counts, dc_symbols)
    ac, _ = huffman(ac_counts, ac_symbols)
    qs = [[quant]*64 for _ in range(3)]

    ai_debug = gui or (os.environ.get('VSIM_AI_DEBUG', '0').lower() in ('1', 'true', 'yes'))
    if ai_debug:
        debug_dir = ROOT / 'build/debug_job'
        debug_dir.mkdir(parents=True, exist_ok=True)
        job = debug_dir
        for c in range(3):
            (job/f'q{c}.bin').write_bytes(bytes(qs[c]))
            (job/f'input{c}.bin').write_bytes(planes[c])
        for ident in range(2):
            write_table(job, 1, ident, dc)
            write_table(job, 2, ident, ac)
        run_rtl(job, 0, w, h, fmt, 0x210, sum(map(len, planes)), gui=gui)
        scan = (job/'output.scan').read_bytes()
    else:
        TEMP_DIR.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='jpeg-rtl-', dir=TEMP_DIR) as temporary:
            job = Path(temporary)
            for c in range(3):
                (job/f'q{c}.bin').write_bytes(bytes(qs[c]))
                (job/f'input{c}.bin').write_bytes(planes[c])
            for ident in range(2):
                write_table(job, 1, ident, dc)
                write_table(job, 2, ident, ac)
            run_rtl(job, 0, w, h, fmt, 0x210, sum(map(len, planes)), gui=gui)
            scan = (job/'output.scan').read_bytes()

    payload = jpeg(scan, w, h, fmt, qs, dc_counts, dc_symbols, ac_counts, ac_symbols)
    Path(destination).write_bytes(payload)
    print(f'JPEG: {destination} ({w}x{h}, {sampling}, Q={quant}, {len(payload)} bytes)')


def decode(source, destination, gui=False):
    info = parse(Path(source).read_bytes())
    w, h, fmt = info['width'], info['height'], info['format']
    dims = dimensions(w, h, fmt)
    dcids = list(dict.fromkeys(info['dcids']))
    acids = list(dict.fromkeys(info['acids']))
    select = sum((c | dcids.index(info['dcids'][c]) << 2 |
                  acids.index(info['acids'][c]) << 3) << (c*4) for c in range(3))

    ai_debug = gui or (os.environ.get('VSIM_AI_DEBUG', '0').lower() in ('1', 'true', 'yes'))
    if ai_debug:
        debug_dir = ROOT / 'build/debug_job'
        debug_dir.mkdir(parents=True, exist_ok=True)
        job = debug_dir
        for c in range(3):
            (job/f'q{c}.bin').write_bytes(bytes(info['qs'][info['qids'][c]]))
        for ident in range(2):
            write_table(job, 3, ident, info['hs'][dcids[min(ident, len(dcids)-1)]][1])
            write_table(job, 4, ident, info['hs'][16+acids[min(ident, len(acids)-1)]][1])
        (job/'input.scan').write_bytes(info['scan'])
        run_rtl(job, 1, w, h, fmt, select, len(info['scan']), info['restart_interval'], gui=gui)
        planes = [Image.frombytes('L', size, (job/f'output{c}.bin').read_bytes())
                  for c, size in enumerate(dims)]
    else:
        TEMP_DIR.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='jpeg-rtl-', dir=TEMP_DIR) as temporary:
            job = Path(temporary)
            for c in range(3):
                (job/f'q{c}.bin').write_bytes(bytes(info['qs'][info['qids'][c]]))
            for ident in range(2):
                write_table(job, 3, ident, info['hs'][dcids[min(ident, len(dcids)-1)]][1])
                write_table(job, 4, ident, info['hs'][16+acids[min(ident, len(acids)-1)]][1])
            (job/'input.scan').write_bytes(info['scan'])
            run_rtl(job, 1, w, h, fmt, select, len(info['scan']), info['restart_interval'], gui=gui)
            planes = [Image.frombytes('L', size, (job/f'output{c}.bin').read_bytes())
                      for c, size in enumerate(dims)]

    # Edge-aligned nearest-neighbour chroma expansion, also for odd dimensions.
    hs, vs = (1 if fmt == 0 else 2), (2 if fmt == 2 else 1)
    if fmt:
        for c in (1, 2):
            cw, ch = dims[c]
            planes[c] = planes[c].resize((cw*hs, ch*vs), Image.Resampling.NEAREST).crop((0, 0, w, h))
    Image.merge('YCbCr', planes).convert('RGB').save(destination, format='PNG')
    print(f'PNG: {destination} ({w}x{h})')


def main(argv=None):
    parser = argparse.ArgumentParser(description='PNG/JPEG conversion using Verilog RTL simulation')
    commands = parser.add_subparsers(dest='command', required=True)
    enc = commands.add_parser('encode', help='PNG -> baseline JPEG through RTL')
    enc.add_argument('input', type=Path)
    enc.add_argument('output', type=Path)
    enc.add_argument('--quant', type=int, default=16, help='uniform Q value 1..255, default 16; lower means less loss')
    enc.add_argument('--sampling', choices=FORMATS, default='444')
    enc.add_argument('--gui', '--ai-debug', dest='gui', action='store_true',
                     help='Launch QuestaSim in AI debug mode (+acc, GUI, socket server, no run -all)')
    dec = commands.add_parser('decode', help='baseline YCbCr JPEG -> PNG through RTL')
    dec.add_argument('input', type=Path)
    dec.add_argument('output', type=Path)
    dec.add_argument('--gui', '--ai-debug', dest='gui', action='store_true',
                     help='Launch QuestaSim in AI debug mode (+acc, GUI, socket server, no run -all)')
    args = parser.parse_args(argv)
    try:
        if args.input.resolve() == args.output.resolve():
            raise ValueError('input and output must be different files')
        if args.command == 'encode':
            encode(args.input, args.output, args.quant, args.sampling, gui=args.gui)
        else:
            decode(args.input, args.output, gui=args.gui)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f'ERROR: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
