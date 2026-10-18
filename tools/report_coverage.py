#!/usr/bin/env python3
"""
tools/report_coverage.py - Merge UCDB files and generate coverage reports.
"""
import argparse
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_COV_DIR = ROOT / 'build' / 'coverage'


def find_vcover():
    return os.environ.get('VCOVER', 'vcover')


def merge_ucdbs(vcover, cov_dir, out_ucdb):
    ucdb_files = [
        f for f in cov_dir.glob('*.ucdb')
        if f.name != out_ucdb.name
    ]
    if not ucdb_files:
        print(f"[report_coverage] No UCDB files found in {cov_dir}", file=sys.stderr)
        return False

    print(f"[report_coverage] Found {len(ucdb_files)} UCDB files to merge:")
    for f in sorted(ucdb_files):
        print(f"  - {f.name}")

    if len(ucdb_files) == 1:
        # Single UCDB: copy or merge
        import shutil
        shutil.copy2(ucdb_files[0], out_ucdb)
        print(f"[report_coverage] Single file copied to {out_ucdb.name}")
        return True

    cmd = [vcover, 'merge', out_ucdb.as_posix()] + [f.as_posix() for f in sorted(ucdb_files)]
    print(f"[report_coverage] Running: {' '.join(cmd)}")
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"[report_coverage ERROR] vcover merge failed (exit code {res.returncode}):\n{res.stderr or res.stdout}", file=sys.stderr)
        return False
    print(f"[report_coverage] Merged UCDB created: {out_ucdb}")
    return True


def generate_reports(vcover, ucdb_file, cov_dir, make_html=True):
    if not ucdb_file.is_file():
        print(f"[report_coverage ERROR] UCDB file does not exist: {ucdb_file}", file=sys.stderr)
        return False

    # 1. Summary Report (stdout and file)
    summary_file = cov_dir / 'summary.txt'
    cmd_summary = [vcover, 'report', '-summary', ucdb_file.as_posix()]
    res_summary = subprocess.run(cmd_summary, capture_output=True, text=True)
    if res_summary.returncode != 0:
        print(f"[report_coverage ERROR] vcover report -summary failed:\n{res_summary.stderr or res_summary.stdout}", file=sys.stderr)
        return False

    print("\n" + "=" * 70)
    print(" COVERAGE SUMMARY REPORT")
    print("=" * 70)
    print(res_summary.stdout.strip())
    print("=" * 70 + "\n")
    summary_file.write_text(res_summary.stdout, encoding='utf-8')
    print(f"[report_coverage] Summary written to: {summary_file}")

    # 2. Detailed Report
    details_file = cov_dir / 'details.txt'
    cmd_details = [vcover, 'report', '-details', '-output', details_file.as_posix(), ucdb_file.as_posix()]
    res_details = subprocess.run(cmd_details, capture_output=True, text=True)
    if res_details.returncode == 0:
        print(f"[report_coverage] Detailed report written to: {details_file}")
    else:
        print(f"[report_coverage WARNING] Detailed report failed:\n{res_details.stderr}", file=sys.stderr)

    # 3. HTML Report
    if make_html:
        html_dir = cov_dir / 'html'
        html_dir.mkdir(parents=True, exist_ok=True)
        cmd_html = [vcover, 'report', '-html', '-output', html_dir.as_posix(), ucdb_file.as_posix()]
        res_html = subprocess.run(cmd_html, capture_output=True, text=True)
        if res_html.returncode == 0:
            print(f"[report_coverage] HTML report generated at: {html_dir / 'index.html'}")
        else:
            print(f"[report_coverage WARNING] HTML report generation warning/error:\n{res_html.stderr}", file=sys.stderr)

    return True


def main():
    parser = argparse.ArgumentParser(description="Merge QuestaSim UCDB files and generate coverage reports.")
    parser.add_argument('--dir', type=Path, default=DEFAULT_COV_DIR, help="Directory containing UCDB files")
    parser.add_argument('--out', type=str, default='total.ucdb', help="Output merged UCDB filename")
    parser.add_argument('--no-html', action='store_true', help="Do not generate HTML report")
    parser.add_argument('--target', type=Path, default=None, help="Specific UCDB file to report without merging")
    args = parser.parse_args()

    vcover = find_vcover()
    cov_dir = args.dir.resolve()
    cov_dir.mkdir(parents=True, exist_ok=True)

    if args.target:
        target_ucdb = args.target.resolve()
        if not target_ucdb.is_file():
            print(f"Target UCDB file not found: {target_ucdb}", file=sys.stderr)
            sys.exit(1)
        ok = generate_reports(vcover, target_ucdb, cov_dir, make_html=not args.no_html)
        sys.exit(0 if ok else 1)

    out_ucdb = cov_dir / args.out
    if not merge_ucdbs(vcover, cov_dir, out_ucdb):
        sys.exit(1)

    ok = generate_reports(vcover, out_ucdb, cov_dir, make_html=not args.no_html)
    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    main()
