#!/usr/bin/env python3
"""Build or verify the deterministic mod-native-reagents Schema-3 EPF."""
from __future__ import annotations
import argparse, hashlib, json, tempfile, zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUTPUT = ROOT / "mod-native-reagents.epf"
STAMP = (1980, 1, 1, 0, 0, 0)

def safe(value: str) -> str:
    path = Path(value)
    if not value or path.is_absolute() or ".." in path.parts or "\\" in value:
        raise ValueError("unsafe EPF member: " + value)
    return path.as_posix()

def members() -> list[str]:
    manifest = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8"))
    result = {"manifest.json", safe(manifest["clientFrameXml"]["stockTocSource"])}
    result.update(safe(row["source"]) for row in manifest["content"])
    return sorted(result)

def build(output: Path) -> None:
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for member in members():
            source = ROOT / member
            if not source.is_file(): raise FileNotFoundError(member)
            info = zipfile.ZipInfo(member, STAMP); info.compress_type = zipfile.ZIP_DEFLATED; info.external_attr = 0o100644 << 16
            archive.writestr(info, source.read_bytes())

def digest(path: Path) -> str: return hashlib.sha256(path.read_bytes()).hexdigest()

def main() -> None:
    parser = argparse.ArgumentParser(); parser.add_argument("--check", action="store_true"); args = parser.parse_args()
    if args.check:
        if not OUTPUT.is_file(): raise SystemExit("missing " + str(OUTPUT))
        with tempfile.TemporaryDirectory(prefix="native-reagents-epf-") as directory:
            candidate = Path(directory) / OUTPUT.name; build(candidate)
            if digest(candidate) != digest(OUTPUT): raise SystemExit("checked-in EPF is stale")
        print("verified", OUTPUT, digest(OUTPUT))
    else:
        build(OUTPUT); print("built", OUTPUT, digest(OUTPUT))
if __name__ == "__main__": main()
