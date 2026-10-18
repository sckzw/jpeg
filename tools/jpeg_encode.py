#!/usr/bin/env python3
"""Convenience entry point for PNG -> RTL JPEG."""
import sys
from jpeg_tool import main
if __name__ == '__main__':
    sys.exit(main(['encode', *sys.argv[1:]]))
