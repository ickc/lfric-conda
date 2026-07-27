#!/usr/bin/env python3
"""Read a dependencies.yaml / sources.yaml and print "<name>\t<ref>\t<source>".

The upstream-native shape is a mapping of repo name -> {source:, ref:}. Both this
repo's top-level sources.yaml (the staged vendor/ pins) and a science suite's own
dependencies.yaml (its per-suite source axis) use it, so both are read here.

PyYAML is in the environment, but this also has to run *before* any environment
exists (scripts/stage-sources.sh on a bare checkout), so it falls back to a
minimal parser for the flat scalar form the files actually use.

A repo may declare a single {source, ref} or a list of them; the FIRST entry (the
base ref) is taken -- merging a fork branch onto a tag, which upstream's
dependencies.yaml allows, is not supported here.
"""

import sys


def _fallback(path):
    """Parse the flat `name:` / indented `key: value` form, no PyYAML."""
    data, cur = {}, None
    for raw in open(path):
        line = raw.rstrip("\n")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if not line[:1].isspace() and line.rstrip().endswith(":"):
            cur = line.strip()[:-1]
            data[cur] = {}
        elif cur is not None and ":" in line:
            key, _, value = line.strip().partition(":")
            key = key.lstrip("- ").strip()
            value = value.strip()
            # Drop an inline comment: the refs are written `ref: <tag>   # <sha>`,
            # and without this the value would carry the comment into `git rev-parse`.
            for sep in (" #", "\t#"):
                i = value.find(sep)
                if i != -1:
                    value = value[:i].rstrip()
            data[cur].setdefault(key, value.strip("'\""))
    return data


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: read-deps.py <dependencies.yaml>")
    path = sys.argv[1]
    try:
        import yaml

        with open(path) as fh:
            data = yaml.safe_load(fh) or {}
    except Exception:
        data = _fallback(path)

    for name, spec in (data or {}).items():
        if isinstance(spec, list):
            spec = spec[0] if spec else {}
        spec = spec or {}
        print("{}\t{}\t{}".format(name, spec.get("ref", "") or "", spec.get("source", "") or ""))


if __name__ == "__main__":
    main()
