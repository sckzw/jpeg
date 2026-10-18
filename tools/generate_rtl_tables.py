"""Generate/check the checked-in constant ROM functions from the contract model."""
from pathlib import Path
import argparse
from reference import C,ZIGZAG
ROOT=Path(__file__).resolve().parents[1]/'rtl'

def render():
    c='function signed [15:0] cval;\n input [2:0] k,n;\n begin\n case ({k,n})\n'
    for k,row in enumerate(C):
        for n,v in enumerate(row):c+=f" 6'd{k*8+n}: cval = {'-' if v<0 else ''}16'sd{abs(v)};\n"
    c+=' default: cval=0;\n endcase\n end\nendfunction\n'
    z='function [5:0] zigzag;\n input [5:0] idx;\n begin\n case (idx)\n'
    for i,v in enumerate(ZIGZAG):z+=f" 6'd{i}: zigzag=6'd{v};\n"
    z+=' default: zigzag=0;\n endcase\n end\nendfunction\n'
    return {'jpeg_c.vh':c,'jpeg_zigzag.vh':z}

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--check',action='store_true');args=ap.parse_args()
    for name,text in render().items():
        path=ROOT/name
        if args.check:
            if path.read_text()!=text:raise SystemExit(f'constant ROM mismatch: {path}')
        else:path.write_text(text)
    print('PASS constant ROMs' if args.check else 'generated constant ROMs')
if __name__=='__main__':main()
