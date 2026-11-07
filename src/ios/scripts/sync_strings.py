#!/usr/bin/env python3
"""Đồng bộ AnCu/Resources/Localizable.xcstrings từ các file .stringsdata do build sinh ra.

Xcode IDE tự làm việc này khi build; `xcodebuild` thì không. Chạy sau một lần build:

    python3 -I scripts/sync_strings.py build/DerivedData

- Key mới trong code → thêm vào catalog (ngôn ngữ nguồn: vi, giá trị = key).
- Key không còn trong code → đánh dấu `extractionState: stale` (không xóa, giữ bản dịch nếu có).
"""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CATALOG = ROOT / "AnCu" / "Resources" / "Localizable.xcstrings"


def collect_keys(derived_data: pathlib.Path) -> set[str]:
    keys: set[str] = set()
    pattern = "Build/Intermediates.noindex/AnCu.build/*/AnCu.build/Objects-normal/*/*.stringsdata"
    for path in derived_data.glob(pattern):
        data = json.loads(path.read_text(encoding="utf-8"))
        for entry in data.get("tables", {}).get("Localizable", []):
            keys.add(entry["key"])
    return keys


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    keys = collect_keys(pathlib.Path(sys.argv[1]))
    if not keys:
        print("Không tìm thấy .stringsdata — hãy build trước.", file=sys.stderr)
        return 1

    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    strings: dict = catalog.setdefault("strings", {})

    added = [key for key in keys if key not in strings]
    for key in added:
        strings[key] = {}

    stale = 0
    for key, entry in strings.items():
        if key in keys:
            entry.pop("extractionState", None)
        else:
            entry["extractionState"] = "stale"
            stale += 1

    catalog["strings"] = dict(sorted(strings.items()))
    CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"{len(keys)} key trong code · thêm {len(added)} · stale {stale}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
