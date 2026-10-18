#!/usr/bin/env python3
"""Convenience entry point for JPEG -> RTL PNG."""
import sys
from jpeg_tool import main
if __name__ == '__main__':
    sys.exit(main(['decode', *sys.argv[1:]]))
