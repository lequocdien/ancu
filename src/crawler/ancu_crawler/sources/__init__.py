"""Đăng ký nguồn. Mỗi nguồn: một module, một class kế thừa `Source`, khai báo trong SOURCES.

Thêm nguồn mới: khảo sát trang (robots.txt, điều khoản, cấu trúc) → ghi vào sources.json → viết parser +
test bằng HTML/PDF mẫu lưu trong tests/fixtures (không gọi mạng trong test).
"""
from __future__ import annotations

from .base import Source

SOURCES: dict[str, type[Source]] = {}


def register(cls: type[Source]) -> type[Source]:
    if cls.name in SOURCES:
        raise ValueError(f"nguồn trùng tên: {cls.name}")
    SOURCES[cls.name] = cls
    return cls
