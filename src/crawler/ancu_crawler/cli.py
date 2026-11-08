"""python -m ancu_crawler list | run <nguồn> [--limit N] [--out runs]"""
from __future__ import annotations

import argparse
import pathlib
import sys

from .contract import Run
from .fetch import Fetcher, FetchBlocked
from .sources import SOURCES

ROOT = pathlib.Path(__file__).resolve().parent.parent


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="ancu_crawler")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("list", help="liệt kê nguồn đã cài")
    run_cmd = sub.add_parser("run", help="chạy một nguồn → runs/<run>/features.geojson")
    run_cmd.add_argument("source")
    run_cmd.add_argument("--limit", type=int, help="giới hạn số mục (thử nghiệm)")
    run_cmd.add_argument("--out", default=str(ROOT / "runs"))
    run_cmd.add_argument("--interval", type=float, default=3.0, help="giây tối thiểu giữa 2 request cùng host")
    args = parser.parse_args(argv)

    if args.command == "list":
        if not SOURCES:
            print("Chưa có nguồn nào (xem sources.json — nguồn đang khảo sát).")
        for name, cls in sorted(SOURCES.items()):
            print(f"{name}\t{cls.entity}\t{', '.join(cls.start_urls)}")
        return 0

    cls = SOURCES.get(args.source)
    if cls is None:
        print(f"Không có nguồn '{args.source}'. Dùng: python -m ancu_crawler list", file=sys.stderr)
        return 2
    source = cls()
    run = Run(source=source.name, entity=source.entity, root=pathlib.Path(args.out))
    with Fetcher(evidence_dir=run.raw_dir, min_interval=args.interval) as fetcher:
        try:
            source.crawl(fetcher, run, limit=args.limit)
        except FetchBlocked as e:
            run.warn(str(e))
            print(f"DỪNG: {e}", file=sys.stderr)
    out = run.write()
    print(f"Đã ghi {out} — {len(run.features)} {run.entity}, {len(run.warnings)} cảnh báo")
    print(f"Tiếp: python3 -I src/data/scripts/build_data.py --stage {out}")
    return 0
