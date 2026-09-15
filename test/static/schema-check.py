#!/usr/bin/env python3
"""Deterministic JSON schema validation for devcontainer features and templates.

Pure Python 3 stdlib - no network, no pip, no jq. Mirrors the field checks the
devcontainer CLI performs on publish plus repo-specific invariants (id == dir
name, semver versions, no bash-array option defaults, sh shebangs).

Exit 0 when everything validates, 1 otherwise.
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "src")
SEMVER = re.compile(r"^\d+\.\d+\.\d+$")

errors = []


def fail(msg):
    errors.append(msg)


def read_json(path):
    try:
        with open(path) as fh:
            return json.load(fh)
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"{path}: invalid JSON: {exc}")
        return None


def check_shebang(path, expected="#!/bin/sh"):
    with open(path) as fh:
        shebang = fh.readline().strip()
    if shebang != expected:
        fail(f"{path}: shebang is '{shebang}', expected '{expected}'")


def check_feature(name, path):
    data = read_json(os.path.join(path, "devcontainer-feature.json"))
    if data is None:
        return

    for key in ("id", "name", "version", "description"):
        if not isinstance(data.get(key), str) or not data.get(key):
            fail(f"{name}: missing or empty required key '{key}'")

    if data.get("id") != name:
        fail(f"{name}: id '{data.get('id')}' must equal directory name '{name}'")

    version = data.get("version", "")
    if not SEMVER.match(version):
        fail(f"{name}: version '{version}' is not semver (expected X.Y.Z)")

    install = os.path.join(path, "install.sh")
    if not os.path.isfile(install):
        fail(f"{name}: install.sh missing")
    else:
        check_shebang(install)

    options = data.get("options", {})
    if not isinstance(options, dict):
        fail(f"{name}: 'options' must be an object")
        return
    for opt, spec in options.items():
        if not isinstance(spec, dict):
            fail(f"{name}: option '{opt}' must be an object")
            continue
        if "description" not in spec:
            fail(f"{name}: option '{opt}' missing 'description'")
        default = spec.get("default")
        if isinstance(default, list):
            fail(f"{name}: option '{opt}' default must not be an array (bash-array footgun)")


def check_template(name, path):
    data = read_json(os.path.join(path, "devcontainer-template.json"))
    if data is None:
        return

    for key in ("id", "version", "name", "publisher", "description"):
        if not isinstance(data.get(key), str) or not data.get(key):
            fail(f"{name}: template missing or empty required key '{key}'")

    if not SEMVER.match(data.get("version", "")):
        fail(f"{name}: template version is not semver")

    # The template must ship its devcontainer definition at the dir root
    # or under .devcontainer/ (the CLI's variant convention).
    variants = [
        os.path.join(path, "devcontainer.json"),
        os.path.join(path, ".devcontainer", "devcontainer.json"),
    ]
    found = False
    for v in variants:
        if os.path.isfile(v):
            found = True
            if read_json(v) is None:
                return
    if not found:
        fail(f"{name}: no devcontainer.json at template root or .devcontainer/")

    test_sh = os.path.join(path, "test", "test.sh")
    if not os.path.isfile(test_sh):
        fail(f"{name}: test/test.sh missing")
    else:
        check_shebang(test_sh)


def main():
    if not os.path.isdir(SRC):
        fail(f"src/ directory not found at {SRC}")

    feats = templs = 0
    for name in sorted(os.listdir(SRC)):
        path = os.path.join(SRC, name)
        if not os.path.isdir(path):
            continue
        if os.path.isfile(os.path.join(path, "devcontainer-feature.json")):
            check_feature(name, path)
            feats += 1
        if os.path.isfile(os.path.join(path, "devcontainer-template.json")):
            check_template(name, path)
            templs += 1

    # Templates live under src/templates/<name>/, not src/<name>/
    tpl_base = os.path.join(SRC, "templates")
    if os.path.isdir(tpl_base):
        for name in sorted(os.listdir(tpl_base)):
            path = os.path.join(tpl_base, name)
            if os.path.isdir(path) and os.path.isfile(os.path.join(path, "devcontainer-template.json")):
                check_template(name, path)
                templs += 1

    # Validate shipped config templates under src/<feature>/templates/*.json
    cfg_templs = 0
    for dirpath, dirnames, filenames in os.walk(SRC):
        rel = os.path.relpath(dirpath, SRC)
        # Only look inside directories named "templates" one level under src/
        parts = rel.split(os.sep)
        if len(parts) != 2 or parts[1] != "templates":
            continue
        for fname in sorted(filenames):
            if not fname.endswith(".json"):
                continue
            fpath = os.path.join(dirpath, fname)
            data = read_json(fpath)
            if data is None:
                continue
            if not isinstance(data, dict):
                fail(f"{fpath}: config template must be a JSON object")
                continue
            if fname == "models.json":
                for key in ("model", "quant", "models_dir"):
                    if key not in data:
                        fail(f"{fpath}: missing required key '{key}'")
            elif fname == "bifrost.json":
                if "upstream" not in data:
                    fail(f"{fpath}: missing required key 'upstream'")
            cfg_templs += 1

    if errors:
        print(f"schema-check FAILED ({len(errors)} issue(s)):")
        for e in errors:
            print(f"  - {e}")
        sys.exit(1)
    print(f"schema-check OK: {feats} feature(s), {templs} template(s), {cfg_templs} config template(s) validated")


if __name__ == "__main__":
    main()