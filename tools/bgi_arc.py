#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
BGI/Ethornell 引擎封包 (ARC v1 / ARC v2) 解析与虚拟文件系统 (VFS) 模块。

支持：
- ARC v1 (`PackFile    `)：32 字节索引项（16 字节文件名 + uint32 offset + uint32 size + 8 字节保留）
- ARC v2 (`BURIKO ARC20`)：128 字节索引项（96 字节文件名 + uint32 offset + uint32 size + 24 字节保留）
- 多封包挂载与同名条目覆盖优先级核查（如 `data02150.arc` 覆盖 `data02200.arc`）
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import struct
from typing import Iterator


MAGIC_ARC_V1 = b"PackFile    "
MAGIC_ARC_V2 = b"BURIKO ARC20"


@dataclass(frozen=True)
class ArcEntry:
    """单个封包条目元数据。"""

    name: str
    rel_offset: int
    abs_offset: int
    size: int
    archive_path: Path
    archive_version: int


class BgiArchive:
    """BGI `.arc` 归档只读解析器（支持 v1 与 v2）。"""

    def __init__(self, path: Path | str) -> None:
        self.path = Path(path)
        self.version: int = 0
        self.entries: list[ArcEntry] = []
        self._by_name: dict[str, ArcEntry] = {}
        self._by_name_lower: dict[str, ArcEntry] = {}
        self._load_index()

    def _load_index(self) -> None:
        file_size = self.path.stat().st_size
        with self.path.open("rb") as f:
            hdr = f.read(16)
            if len(hdr) < 16:
                raise ValueError(f"归档头过短: {self.path}")
            magic = hdr[:12]
            count = struct.unpack_from("<I", hdr, 12)[0]
            if magic == MAGIC_ARC_V1:
                self.version = 1
                rec_size, name_len = 32, 16
            elif magic == MAGIC_ARC_V2:
                self.version = 2
                rec_size, name_len = 128, 96
            else:
                raise ValueError(f"未知的 BGI 归档魔数 {magic!r}: {self.path}")

            data_base = 16 + count * rec_size
            table = f.read(count * rec_size)
            if len(table) != count * rec_size:
                raise ValueError(f"索引表截断: {self.path}")

        entries: list[ArcEntry] = []
        by_name: dict[str, ArcEntry] = {}
        by_name_lower: dict[str, ArcEntry] = {}

        for i in range(count):
            rec = table[i * rec_size : (i + 1) * rec_size]
            raw_name = rec[:name_len].split(b"\x00", 1)[0]
            try:
                name = raw_name.decode("cp932")
            except UnicodeDecodeError:
                name = raw_name.decode("gbk", errors="replace")
            rel_offset, size = struct.unpack_from("<II", rec, name_len)
            abs_offset = data_base + rel_offset
            if abs_offset + size > file_size:
                raise ValueError(
                    f"条目越界 {self.path.name}::{name}: "
                    f"offset={abs_offset}, size={size}, file_size={file_size}"
                )
            entry = ArcEntry(
                name=name,
                rel_offset=rel_offset,
                abs_offset=abs_offset,
                size=size,
                archive_path=self.path,
                archive_version=self.version,
            )
            entries.append(entry)
            by_name[name] = entry
            by_name_lower[name.lower()] = entry

        self.entries = entries
        self._by_name = by_name
        self._by_name_lower = by_name_lower

    def __len__(self) -> int:
        return len(self.entries)

    def __contains__(self, name: str) -> bool:
        return name in self._by_name or name.lower() in self._by_name_lower

    def get_entry(self, name: str) -> ArcEntry:
        """按条目名查找元数据（优先精确匹配，其次大小写不敏感）。"""
        entry = self._by_name.get(name)
        if entry is None:
            entry = self._by_name_lower.get(name.lower())
        if entry is None:
            raise KeyError(f"在 {self.path.name} 中未找到条目: {name}")
        return entry

    def read_bytes(self, name: str, limit: int | None = None) -> bytes:
        """读取指定条目字节数据。"""
        entry = self.get_entry(name)
        read_len = entry.size if limit is None else min(entry.size, limit)
        with self.path.open("rb") as f:
            f.seek(entry.abs_offset)
            data = f.read(read_len)
        if len(data) != read_len:
            raise IOError(f"短读 {self.path.name}::{name}: 期望 {read_len}, 实际 {len(data)}")
        return data

    def iter_entries(self, limit: int | None = None) -> Iterator[tuple[ArcEntry, bytes]]:
        """顺序流式遍历归档中的全部条目数据。"""
        with self.path.open("rb") as f:
            for entry in self.entries:
                f.seek(entry.abs_offset)
                read_len = entry.size if limit is None else min(entry.size, limit)
                yield entry, f.read(read_len)


class BgiVfs:
    """
    BGI 虚拟文件系统：模拟原版引擎多归档挂载与优先级覆盖。

    在 BGI 引擎中，游戏根目录的补丁包（如 `sysprg2.arc`）与 `Archive/` 下序号
    较小的补丁归档（如 `data02150.arc`）会优先于主数据归档（如 `data02200.arc`）
    被查找命中，从而实现无码 CG 补丁、汉化补丁与 F12 透视补丁的无损覆盖。
    """

    def __init__(self, game_dir: Path | str, include_data02150_bak: bool = False) -> None:
        self.game_dir = Path(game_dir)
        self.archives: list[BgiArchive] = []
        self.index: dict[str, ArcEntry] = {}
        self.overrides: dict[str, list[ArcEntry]] = {}
        self._mount_all(include_data02150_bak=include_data02150_bak)

    def _mount_all(self, include_data02150_bak: bool) -> None:
        candidates: list[Path] = []
        # 1. 根目录系统/补丁归档：sysprg2 优先于 sysprg
        for root_name in ("sysprg2.arc", "sysprg.arc", "sysgrp.arc", "system.arc"):
            p = self.game_dir / root_name
            if p.is_file():
                candidates.append(p)

        # 2. Archive 目录按文件名升序挂载（例如 data02150.arc 先于 data02200.arc）
        archive_dir = self.game_dir / "Archive"
        if archive_dir.is_dir():
            arc_files = sorted(archive_dir.glob("*.arc"), key=lambda x: x.name.lower())
            if include_data02150_bak:
                bak = archive_dir / "data02150.arc.bak"
                if bak.is_file() and not (archive_dir / "data02150.arc").is_file():
                    arc_files.append(bak)
                    arc_files.sort(key=lambda x: x.name.lower())
            candidates.extend(arc_files)

        for arc_path in candidates:
            arc = BgiArchive(arc_path)
            self.archives.append(arc)
            for entry in arc.entries:
                key = entry.name.lower()
                self.overrides.setdefault(key, []).append(entry)
                # 先挂载的高优先级归档（序号更小者）胜出
                if key not in self.index:
                    self.index[key] = entry

    def get_entry(self, name: str) -> ArcEntry:
        """按 VFS 优先级查找有效条目。"""
        key = name.lower()
        if key not in self.index:
            raise KeyError(f"VFS 中未找到条目: {name}")
        return self.index[key]

    def read_bytes(self, name: str) -> bytes:
        """按 VFS 优先级读取有效条目字节。"""
        entry = self.get_entry(name)
        with entry.archive_path.open("rb") as f:
            f.seek(entry.abs_offset)
            return f.read(entry.size)

    def list_shadowed_entries(self) -> dict[str, list[ArcEntry]]:
        """列出被高优先级归档覆盖（存在多份同名定义）的条目。"""
        return {k: v for k, v in self.overrides.items() if len(v) > 1}
