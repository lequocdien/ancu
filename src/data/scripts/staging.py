"""GeoJSON → stage.sql: nạp vào schema `ingest` (staging) để admin duyệt (data-strategy.md 2b).

Chỉ dùng thư viện chuẩn. Không kết nối DB — sinh file SQL, người dùng chạy bằng psql / DBeaver:

    python3 -I src/data/scripts/build_data.py --stage src/crawler/runs/<run>/features.geojson
    python3 -I src/data/scripts/build_data.py --stage-manual --entities routes,nodes
    psql "<connection string>" -v ON_ERROR_STOP=1 -f src/data/out/stage.sql

Kiểm tra 2 tầng: ở đây chỉ CẤU TRÚC (kiểu, UUID, hình học, thuộc tính lạ, contract). Nghiệp vụ (mã danh mục, vùng MVP,
đủ cặp giá…) do trigger ở DB ghi vào `validation_errors` — thấy trong `ingest.pending_review` khi duyệt.

File của crawler (contract_version 1):

    {"type": "FeatureCollection",
     "ancu": {"contract_version": 1, "entity": "projects", "source": "so_xay_dung_hcm", "run_ref": "2026-11-08_so_xay_dung_hcm"},
     "features": [{"type": "Feature", "geometry": null | {...},
                   "properties": {"id": "<uuid>", ...thuộc tính của entity..., "_crawled_at": "...", "_evidence": "...", "_raw": {...}}}]}
"""
from __future__ import annotations

import json
import re
import uuid
from datetime import datetime

CONTRACT_VERSION = 1
UUID_RE = re.compile(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
SOURCE_RE = re.compile(r"^[a-z0-9_]{2,40}$")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
ACCURACIES = ("chinh_xac", "gan_dung", "minh_hoa")
META_KEYS = {"_crawled_at", "_evidence", "_raw"}

STR, INT, NUM, BOOL, DATE = "chuỗi", "số nguyên", "số", "boolean", "ngày YYYY-MM-DD"

# (thuộc tính → cột, kiểu). Staging LỎNG: chỉ `id` bắt buộc; thiếu trường nghiệp vụ → DB ghi validation_errors.
ENTITIES = {
    "routes": {
        "table": "route_candidates",
        "geometry": ("LineString", "MultiLineString"),
        "geometry_column": "geom",
        "geometry_required": False,
        "fields": {"name": STR, "type": STR, "status": STR, "expected_year": INT, "color_hex": STR,
                   "geometry_accuracy": STR, "source_url": STR},
    },
    "nodes": {
        "table": "node_candidates",
        "geometry": ("Point",),
        "geometry_column": "location",
        "geometry_required": False,
        "fields": {"route_id": STR, "name": STR, "type": STR, "geometry_accuracy": STR},
    },
    "projects": {
        "table": "project_candidates",
        "geometry": ("Point",),
        "geometry_column": "location",
        # Thông báo của Sở chỉ có địa chỉ → admin đặt vị trí khi duyệt.
        "geometry_required": False,
        "fields": {"name": STR, "address": STR, "ward_code": STR, "service_area": STR, "status": STR,
                   "legal_status": STR, "application_start": DATE, "application_end": DATE,
                   "price_min": NUM, "price_max": NUM, "price_is_estimated": BOOL, "unit_count": INT,
                   "developer": STR, "cover_image_url": STR, "source_url": STR},
    },
}

# Thuộc tính của file vẽ tay (contract cũ) không đưa vào staging: verified_at do người duyệt đặt.
MANUAL_IGNORED = {"verified_at"}


class StagingError(Exception):
    def __init__(self, problems: list[str]):
        super().__init__(f"{len(problems)} vấn đề")
        self.problems = problems


# ---------- Kiểm tra cấu trúc ----------

def _type_ok(value, kind: str) -> bool:
    if kind == STR:
        return isinstance(value, str) and value.strip() != ""
    if kind == INT:
        return isinstance(value, int) and not isinstance(value, bool)
    if kind == NUM:
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    if kind == BOOL:
        return isinstance(value, bool)
    if kind == DATE:
        if not isinstance(value, str) or not DATE_RE.match(value):
            return False
        try:
            datetime.strptime(value, "%Y-%m-%d")
            return True
        except ValueError:
            return False
    return False


def _position_ok(pos) -> bool:
    return (isinstance(pos, list) and len(pos) == 2 and all(isinstance(v, (int, float)) and not isinstance(v, bool) for v in pos)
            and 102.0 <= pos[0] <= 110.0 and 8.0 <= pos[1] <= 23.5)


def _check_geometry(geom, spec, where: str, problems: list[str]) -> None:
    if geom is None:
        if spec["geometry_required"]:
            problems.append(f"{where}: thiếu geometry")
        return
    if not isinstance(geom, dict) or geom.get("type") not in spec["geometry"]:
        problems.append(f"{where}: geometry phải là {' / '.join(spec['geometry'])} hoặc null")
        return
    coords = geom.get("coordinates")
    if geom["type"] == "Point":
        lines = [[coords]]
    elif geom["type"] == "LineString":
        lines = [coords]
    else:
        lines = coords if isinstance(coords, list) else None
    if not lines:
        problems.append(f"{where}: geometry rỗng")
        return
    for line in lines:
        if not isinstance(line, list) or (geom["type"] != "Point" and len(line) < 2):
            problems.append(f"{where}: mỗi đoạn tuyến cần ≥ 2 điểm")
            return
        if not all(_position_ok(p) for p in line):
            problems.append(f"{where}: tọa độ phải [lng, lat] trong khung Việt Nam (lng 102–110, lat 8–23.5)")
            return


def check_feature(entity: str, feature, where: str, problems: list[str], *, manual: bool = False) -> None:
    spec = ENTITIES[entity]
    if not isinstance(feature, dict) or feature.get("type") != "Feature" or not isinstance(feature.get("properties"), dict):
        problems.append(f"{where}: phải là Feature có 'properties'")
        return
    props = feature["properties"]
    fid = props.get("id")
    if not isinstance(fid, str) or not UUID_RE.match(fid):
        problems.append(f"{where}: 'id' phải là UUID (ổn định giữa các lần crawl — UUID v5 từ khóa tự nhiên)")
    else:
        where = f"{where} (id={fid})"
    allowed = set(spec["fields"]) | META_KEYS | {"id"} | (MANUAL_IGNORED if manual else set())
    for name in sorted(set(props) - allowed):
        problems.append(f"{where}: thuộc tính lạ '{name}' (contract v{CONTRACT_VERSION})")
    for name, kind in spec["fields"].items():
        value = props.get(name)
        if value is not None and not _type_ok(value, kind):
            problems.append(f"{where}: '{name}' phải là {kind}, nhận {json.dumps(value, ensure_ascii=False)}")
    accuracy = props.get("geometry_accuracy")
    if accuracy is not None and accuracy not in ACCURACIES:
        problems.append(f"{where}: 'geometry_accuracy' phải là {' / '.join(ACCURACIES)}")
    if "_raw" in props and not isinstance(props["_raw"], dict):
        problems.append(f"{where}: '_raw' phải là object")
    _check_geometry(feature.get("geometry"), spec, where, problems)


def read_crawler_file(fc) -> tuple[dict, list[dict]]:
    """Trả (header `ancu`, features). Ném StagingError nếu sai contract."""
    problems: list[str] = []
    if not isinstance(fc, dict) or fc.get("type") != "FeatureCollection" or not isinstance(fc.get("features"), list):
        raise StagingError(["gốc phải là FeatureCollection có mảng 'features'"])
    header = fc.get("ancu")
    if not isinstance(header, dict):
        raise StagingError(["thiếu khối 'ancu' (contract_version, entity, source)"])
    if header.get("contract_version") != CONTRACT_VERSION:
        problems.append(f"contract_version phải là {CONTRACT_VERSION}, nhận {header.get('contract_version')!r}")
    if header.get("entity") not in ENTITIES:
        problems.append(f"entity phải là {' / '.join(ENTITIES)}, nhận {header.get('entity')!r}")
    if not isinstance(header.get("source"), str) or not SOURCE_RE.match(header["source"]):
        problems.append("source phải là mã [a-z0-9_]{2,40}")
    if problems:
        raise StagingError(problems)
    seen: set[str] = set()
    for i, feat in enumerate(fc["features"]):
        check_feature(header["entity"], feat, f"features[{i}]", problems)
        fid = (feat.get("properties") or {}).get("id") if isinstance(feat, dict) else None
        if isinstance(fid, str):
            if fid.lower() in seen:
                problems.append(f"features[{i}]: id trùng trong cùng file")
            seen.add(fid.lower())
    if problems:
        raise StagingError(problems)
    return header, fc["features"]


# ---------- Sinh SQL ----------

def lit(value) -> str:
    """Literal SQL an toàn."""
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
    return "'" + str(value).replace("'", "''") + "'"


def _wkt_number(v: float) -> str:
    return repr(float(v)).rstrip("0").rstrip(".") if isinstance(v, float) else str(v)


def geometry_sql(geom) -> str:
    if geom is None:
        return "null"
    kind, coords = geom["type"], geom["coordinates"]
    def pts(line):
        return ", ".join(f"{_wkt_number(x)} {_wkt_number(y)}" for x, y in line)
    if kind == "Point":
        wkt = f"POINT({_wkt_number(coords[0])} {_wkt_number(coords[1])})"
    else:
        lines = [coords] if kind == "LineString" else coords
        wkt = "MULTILINESTRING(" + ", ".join(f"({pts(line)})" for line in lines) + ")"
    return f"'SRID=4326;{wkt}'::extensions.geography"


def candidates_sql(entity: str, features: list[dict], batch_id: str, *, default_accuracy: str | None = None) -> str:
    spec = ENTITIES[entity]
    columns = ["batch_id", "id", *spec["fields"], spec["geometry_column"], "raw", "evidence_url", "crawled_at"]
    rows = []
    for feat in features:
        props = feat["properties"]
        values = [lit(batch_id), lit(props["id"].lower())]
        for name in spec["fields"]:
            value = props.get(name)
            if name == "geometry_accuracy" and value is None:
                value = default_accuracy
            values.append(lit(value))
        values.append(geometry_sql(feat.get("geometry")))
        raw = props.get("_raw") if isinstance(props.get("_raw"), dict) else {k: v for k, v in props.items() if not k.startswith("_")}
        values.append(lit(json.dumps(raw, ensure_ascii=False, sort_keys=True)) + "::jsonb")
        values.append(lit(props.get("_evidence")))
        values.append(lit(props.get("_crawled_at")) + ("::timestamptz" if props.get("_crawled_at") else ""))
        rows.append("  (" + ", ".join(values) + ")")
    return (f"insert into ingest.{spec['table']} ({', '.join(columns)}) values\n" + ",\n".join(rows) + ";\n")


def stage_sql(batches: list[tuple[str, list[dict]]], *, source: str, run_ref: str | None, silent: bool,
              note: str | None, default_accuracy: str | None = None, batch_id: str | None = None) -> str:
    """Một đợt (batch) gồm nhiều entity — tuyến trước ga (ga tham chiếu tuyến cùng đợt)."""
    batch_id = batch_id or str(uuid.uuid4())
    order = {"routes": 0, "nodes": 1, "projects": 2}
    parts = [
        "-- SINH TỰ ĐỘNG bởi src/data/scripts/build_data.py --stage. Chạy: psql \"<cloud>\" -v ON_ERROR_STOP=1 -f <file>\n",
        "-- Sau đó duyệt trong DBeaver: select * from ingest.pending_review where batch_id = "
        f"{lit(batch_id)};\n",
        "begin;\n",
        "insert into ingest.batches (id, source, run_ref, contract_version, silent, note) values "
        f"({lit(batch_id)}, {lit(source)}, {lit(run_ref)}, {CONTRACT_VERSION}, {lit(silent)}, {lit(note)});\n",
    ]
    for entity, features in sorted(batches, key=lambda b: order[b[0]]):
        if features:
            parts.append(candidates_sql(entity, features, batch_id, default_accuracy=default_accuracy))
    parts.append("commit;\n")
    parts.append("select entity, change, name, changed_fields, moved_m, validation_errors, needs_location\n"
                 f"from ingest.pending_review where batch_id = {lit(batch_id)} order by entity, name;\n")
    return "".join(parts)
