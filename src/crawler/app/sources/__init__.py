"""Đăng ký nguồn — CHỈ code riêng của từng nguồn (phần dùng chung ở `core/`). Mỗi nguồn: một module, một class kế thừa `core.Source`.

Thêm nguồn mới: khảo sát trang (robots.txt, điều khoản, cấu trúc) → ghi vào sources.json → viết parser +
test bằng HTML/PDF mẫu lưu trong tests/fixtures (không gọi mạng trong test).
"""
from __future__ import annotations

from ..core.source import Source

SOURCES: dict[str, type[Source]] = {}


def register(cls: type[Source]) -> type[Source]:
    if cls.name in SOURCES:
        raise ValueError(f"nguồn trùng tên: {cls.name}")
    SOURCES[cls.name] = cls
    return cls


# Nguồn đã cài (import để chạy @register).
from . import so_xay_dung_hcm  # noqa: E402,F401
