"""Contract đầu ra của crawler (v1) — khớp `src/data/scripts/staging.py`, nơi SỞ HỮU contract và kiểm tra ở biên.

Crawler chỉ ghi file, không bao giờ chạm DB:

    runs/<ngày>_<nguồn>/
      raw/              bản chụp HTML/PDF gốc (bằng chứng)
      features.geojson  {"type":"FeatureCollection","ancu":{contract_version, entity, source, run_ref},"features":[…]}
      report.json       số lượng, cảnh báo, lỗi parse
"""
from __future__ import annotations

import json
import pathlib
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone, timedelta

CONTRACT_VERSION = 1
ENTITIES = ("projects", "routes", "nodes")
VN_TZ = timezone(timedelta(hours=7))

# Namespace cố định cho UUID v5: cùng (nguồn, khóa tự nhiên) → cùng id ở mọi lần crawl
# → staging nhận ra bản cũ (superseded), duyệt = upsert giữ bookmark người dùng. KHÔNG ĐỔI.
ID_NAMESPACE = uuid.UUID("5b0e4f8a-1c3d-4e6f-9a2b-7c8d9e0f1a2b")


def stable_id(source: str, natural_key: str) -> str:
    """Khóa tự nhiên: mã dự án của nguồn, hoặc URL chuẩn hóa. Không dùng tên (tên hay bị sửa chính tả)."""
    key = natural_key.strip().lower()
    if not key:
        raise ValueError("natural_key rỗng")
    return str(uuid.uuid5(ID_NAMESPACE, f"{source}:{key}"))


def now_vn() -> str:
    return datetime.now(VN_TZ).isoformat(timespec="seconds")


@dataclass
class Run:
    """Một lần chạy của một nguồn. Thu feature + cảnh báo, rồi `write()` ra thư mục run."""

    source: str
    entity: str
    root: pathlib.Path
    started_at: datetime = field(default_factory=lambda: datetime.now(VN_TZ))
    features: list[dict] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)

    def __post_init__(self) -> None:
        if self.entity not in ENTITIES:
            raise ValueError(f"entity phải là {ENTITIES}")

    @property
    def ref(self) -> str:
        return f"{self.started_at:%Y-%m-%d_%H%M}_{self.source}"

    @property
    def directory(self) -> pathlib.Path:
        return self.root / self.ref

    @property
    def raw_dir(self) -> pathlib.Path:
        return self.directory / "raw"

    def add(self, natural_key: str, properties: dict, *, geometry: dict | None = None,
            evidence: str | None = None, raw: dict | None = None) -> str:
        """Thêm một feature. `properties` theo contract (không có `verified_at` — người duyệt đặt)."""
        if "verified_at" in properties or "id" in properties:
            raise ValueError("không truyền 'id' / 'verified_at' — id tính từ natural_key, verified_at do người duyệt đặt")
        fid = stable_id(self.source, natural_key)
        props = {"id": fid, **{k: v for k, v in properties.items() if v is not None}}
        props["_crawled_at"] = now_vn()
        if evidence:
            props["_evidence"] = evidence
        if raw is not None:
            props["_raw"] = raw
        self.features.append({"type": "Feature", "geometry": geometry, "properties": props})
        return fid

    def warn(self, message: str) -> None:
        self.warnings.append(message)

    def to_feature_collection(self) -> dict:
        return {
            "type": "FeatureCollection",
            "ancu": {"contract_version": CONTRACT_VERSION, "entity": self.entity, "source": self.source, "run_ref": self.ref},
            "features": self.features,
        }

    def write(self) -> pathlib.Path:
        self.directory.mkdir(parents=True, exist_ok=True)
        out = self.directory / "features.geojson"
        out.write_text(json.dumps(self.to_feature_collection(), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        report = {"source": self.source, "entity": self.entity, "run_ref": self.ref, "started_at": self.started_at.isoformat(),
                  "finished_at": now_vn(), "features": len(self.features), "warnings": self.warnings}
        (self.directory / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        return out
