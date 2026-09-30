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

    test_sh = os.path.join(ROOT, "test", "templates", name, "test.sh")
    if not os.path.isfile(test_sh):
        fail(f"{name}: test/templates/{name}/test.sh missing")
    else:
        check_shebang(test_sh)


def check_config_types(path, data):
    """Type-check the devcontainer fields these configs actually set.

    Hand-transcribed from devContainer.base.schema.json rather than fetched at
    run time, so this stays runnable offline like the rest of this file. It
    covers the fields used here, not the whole spec.

    The point is to catch values of the wrong shape. A permissive CLI reads
    hostRequirements.gpu = "all", decides it is a string, and hands it back
    without complaint -- the field is an enum of [true, false, "optional"], so
    the value is not merely wrong, it is a type the schema does not have. That
    mistake passed `devcontainer upgrade`, passed read-configuration, and
    passed this file's other checks, and only surfaced when VS Code's stricter
    bundled CLI read the same file. Nothing downstream of the CLI catches it,
    so the check has to live here.
    """
    for key, expected in (
        ("privileged", bool),
        ("init", bool),
        ("updateRemoteUserUID", bool),
        ("remoteUser", str),
        ("workspaceFolder", str),
    ):
        if key in data and not isinstance(data[key], expected):
            fail(
                f"{path}: '{key}' must be {expected.__name__}, got "
                f"{type(data[key]).__name__} ({data[key]!r})"
            )

    for key in ("capAdd", "securityOpt", "runArgs"):
        val = data.get(key)
        if val is None:
            continue
        if not isinstance(val, list) or not all(isinstance(v, str) for v in val):
            fail(f"{path}: '{key}' must be an array of strings")

    ports = data.get("forwardPorts")
    if ports is not None:
        if not isinstance(ports, list):
            fail(f"{path}: 'forwardPorts' must be an array")
        else:
            for p in ports:
                # bool subclasses int in Python, so True would pass an int
                # check and is not a valid port.
                if isinstance(p, bool) or not isinstance(p, (int, str)):
                    fail(
                        f"{path}: 'forwardPorts' entry {p!r} must be an integer "
                        f"or a 'host:port' string"
                    )
                elif isinstance(p, int) and not (0 <= p <= 65535):
                    fail(f"{path}: 'forwardPorts' entry {p} is outside 0-65535")

    env = data.get("containerEnv")
    if env is not None:
        if not isinstance(env, dict):
            fail(f"{path}: 'containerEnv' must be an object")
        else:
            for k, v in env.items():
                if not isinstance(v, str):
                    fail(
                        f"{path}: 'containerEnv' value for '{k}' must be a "
                        f"string, got {type(v).__name__}"
                    )

    req = data.get("hostRequirements")
    if req is None:
        return
    if not isinstance(req, dict):
        fail(f"{path}: 'hostRequirements' must be an object")
        return
    if "gpu" in req:
        gpu = req["gpu"]
        # bool before any int test: True/False are ints in Python, so an int
        # check would wave through 1 and 0.
        if not (isinstance(gpu, bool) or gpu == "optional" or isinstance(gpu, dict)):
            fail(
                f"{path}: hostRequirements.gpu must be true, false, "
                f'"optional", or an object; got {gpu!r}. Note "all" is the '
                f"Docker --gpus spelling and is not valid for this field"
            )
    if "cpus" in req and (isinstance(req["cpus"], bool) or not isinstance(req["cpus"], int)):
        fail(f"{path}: 'hostRequirements.cpus' must be an integer")
    for key in ("memory", "storage"):
        if key in req and not isinstance(req[key], str):
            fail(f"{path}: 'hostRequirements.{key}' must be a string")

    probe = data.get("userEnvProbe")
    if probe is not None and probe not in (
        "none",
        "loginShell",
        "loginInteractiveShell",
        "interactiveShell",
    ):
        fail(f"{path}: 'userEnvProbe' has invalid value {probe!r}")


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

    # Every overrideFeatureInstallOrder entry must be an exact key from
    # "features". The CLI resolves a bare name as a *legacy* feature from the
    # default collection and hard-fails before any install runs, so a shorthand
    # like "apt-get-packages" breaks the whole boot.
    checked_orders = 0
    checked_configs = 0
    devcontainers = []
    for base in (os.path.join(ROOT, ".devcontainer"),
                 os.path.join(SRC, "templates")):
        if not os.path.isdir(base):
            continue
        if base.endswith("templates"):
            for name in sorted(os.listdir(base)):
                cand = os.path.join(base, name, ".devcontainer", "devcontainer.json")
                if os.path.isfile(cand):
                    devcontainers.append(cand)
        else:
            cand = os.path.join(base, "devcontainer.json")
            if os.path.isfile(cand):
                devcontainers.append(cand)

    for path in devcontainers:
        data = read_json(path)
        if not isinstance(data, dict):
            continue
        check_config_types(path, data)
        checked_configs += 1
        order = data.get("overrideFeatureInstallOrder")
        if order is None:
            continue
        feature_keys = set(data.get("features") or {})
        for entry in order:
            if entry not in feature_keys:
                fail(
                    f"{path}: overrideFeatureInstallOrder entry '{entry}' is not a "
                    f"key in 'features' (CLI would treat it as a legacy feature and "
                    f"abort the build)"
                )
        missing = feature_keys - set(order)
        if missing:
            fail(
                f"{path}: overrideFeatureInstallOrder omits {sorted(missing)}; "
                f"list every feature so the order is explicit"
            )
        checked_orders += 1

    if errors:
        print(f"schema-check FAILED ({len(errors)} issue(s)):")
        for e in errors:
            print(f"  - {e}")
        sys.exit(1)
    print(
        f"schema-check OK: {feats} feature(s), {templs} template(s), "
        f"{cfg_templs} config template(s), "
        f"{checked_configs} devcontainer config(s) type-checked, "
        f"{checked_orders} install order(s) validated"
    )


if __name__ == "__main__":
    main()