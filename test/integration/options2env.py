#!/usr/bin/env python3
"""Emit `export KEY=value` lines for a feature's option defaults, UPPERCASED.

devcontainer passes option values to install.sh as `export <OPTION_ID_UPPER>`.
Values are shlex-quoted so the emitted file safely sources under /bin/sh.
"""
import json
import sys


def main():
    path = sys.argv[1]
    with open(path) as fh:
        data = json.load(fh)
    for key, spec in data.get("options", {}).items():
        default = spec.get("default", "")
        # Normalize booleans to lowercase for shell
        if isinstance(default, bool):
            v = "true" if default else "false"
        else:
            v = str(default)
        # shell-escape value
        import shlex
        # do not quote entire value, just escape
        # Use shlex.quote when value contains spaces etc.
        if any(c in v for c in " \t\n\"'\\$`"):
            v = shlex.quote(v)
        print(f"export {key}={v}")


if __name__ == "__main__":
    main()
