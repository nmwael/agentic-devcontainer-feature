#!/usr/bin/env python3
"""Emit `export KEY=value` lines for a feature's option defaults, UPPERCASED.

devcontainer passes option values to install.sh as `export <OPTION_ID_UPPER>`.
Values are shlex-quoted so the emitted file safely sources under /bin/sh.
"""
import json
import shlex
import sys


def main():
    path = sys.argv[1]
    with open(path) as fh:
        data = json.load(fh)
    for key, spec in data.get("options", {}).items():
        default = spec.get("default", "")
        print(f"export {key.upper()}={shlex.quote(str(default))}")


if __name__ == "__main__":
    main()