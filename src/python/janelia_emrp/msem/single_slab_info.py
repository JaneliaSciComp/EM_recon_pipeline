"""
This module defines classes and utilities for multi-SEM wafers
that have a single large slab (without an xlog file describing it).
"""

import re
import statistics
import sys
from dataclasses import dataclass
from operator import attrgetter
from pathlib import Path

from PIL import Image
from pydantic import BaseModel, PrivateAttr, model_validator

from janelia_emrp.msem.field_of_view_layout import MFovPosition
from janelia_emrp.msem.slab_info import STACK_PATTERN

# scan_000303/mfov_0019/corrected_sfov_083.png
PATH_PATTERN = re.compile(r"scan_(\d{6})/mfov_(\d{4})/corrected_sfov_(\d{3}).png")

class SfovInfo(BaseModel):
    path: str
    x: float
    y: float

    _scan: int = PrivateAttr()
    _mfov: int = PrivateAttr()
    _sfov: int = PrivateAttr()

    @model_validator(mode="after")
    def _derive_private_bits(self):
        match = PATH_PATTERN.fullmatch(self.path)
        if not match:
            raise ValueError(f"invalid SFOV path format: {self.path}")
        self._scan = int(match.group(1))
        self._mfov = int(match.group(2))
        self._sfov = int(match.group(3))
        return self

    @property
    def scan(self) -> int: return self._scan

    @property
    def mfov(self) -> int: return self._mfov

    @property
    def sfov(self) -> int: return self._sfov


@dataclass(frozen=True)
class SfovFullPathWithXY:
    sfov_number: int
    fullpath: Path
    x: int
    y: int


@dataclass(slots=True)
class ScanMfov:
    scan_number: int
    mfov_number: int
    center_x: int
    center_y: int
    sfov_list: list[SfovFullPathWithXY]

    def to_mfov_position(self) -> MFovPosition:
        return MFovPosition(self.mfov_number, self.center_x, self.center_y)

    def get_scan_path(self) -> Path | None:
        """Returns the path of the scan directory containing this MFOV
           e.g. /nrs/hess/Hayworth/DATA_Wafer66_ForRenderTest/scan_000303"""
        scan_path = None
        if len(self.sfov_list) > 0:
            first_full_path = self.sfov_list[0].fullpath
            scan_pattern = re.compile(r"^scan_\d+$")
            for parent in first_full_path.parents:
                if scan_pattern.match(parent.name):
                    scan_path = parent
                    break
        return scan_path

    @classmethod
    def from_sfov_info_list(cls,
                            root_directory: Path,
                            sfov_info_list: list[SfovInfo]) -> "ScanMfov":
        if not sfov_info_list:
            raise ValueError("sfov_info_list must not be empty")

        scan = sfov_info_list[0].scan
        mfov = sfov_info_list[0].mfov
        sfov_numbers_seen = set()
        for sfov_info in sfov_info_list:
            if sfov_info.scan != scan:
                raise ValueError(f"{sfov_info.path} has scan {sfov_info.scan} instead of {scan}")
            if sfov_info.mfov != mfov:
                raise ValueError(f"{sfov_info.path} has MFOV {sfov_info.mfov} instead of {mfov}")
            if sfov_info.sfov in sfov_numbers_seen:
                raise ValueError(f"duplicate SFOV number {sfov_info.sfov} in MFOV {mfov} of scan {scan}")
            sfov_numbers_seen.add(sfov_info.sfov)

        s_list = [
            SfovFullPathWithXY(
                sfov_number=s.sfov,
                fullpath=root_directory / s.path,
                x=int(s.x),
                y=int(s.y),
            )
            for s in sfov_info_list
        ]

        s_list.sort(key=attrgetter("sfov_number")) # change to attrgetter("x","y") for spatial order

        cx_f = statistics.fmean(p.x for p in s_list)
        cy_f = statistics.fmean(p.y for p in s_list)
        center_x = round(cx_f)
        center_y = round(cy_f)

        return cls(
            scan_number=scan,
            mfov_number=mfov,
            center_x=center_x,
            center_y=center_y,
            sfov_list=s_list,
        )

class SingleSlabInfo(BaseModel):
    root_directory: str
    owner: str
    project: str
    stack: str
    render_host: str
    resolution_x: float
    resolution_y: float
    resolution_z: float
    sfov_info_list: list[SfovInfo]

    _wafer_id: str = PrivateAttr()

    @model_validator(mode="after")
    def _derive_private_bits(self):
        # w66_s000_r00
        match = STACK_PATTERN.fullmatch(self.stack)
        if not match:
            raise ValueError(f"failed to parse stack name: {self.stack}")
        prefix = match.group(1)
        self._wafer_id = prefix[1:len(prefix)-1]  # remove leading 'w' and trailing '_'
        return self

    @property
    def wafer_short_prefix(self) -> str: return f"w{self._wafer_id}_"

    @property
    def wafer_id(self) -> str: return self._wafer_id

    def __str__(self):
        return (
            "SingleSlabInfo("
            f"root_directory={self.root_directory}, owner={self.owner}, "
            f"project={self.project}, stack={self.stack}, render_host={self.render_host}, "
            f"wafer_short_prefix={self._wafer_short_prefix}, "
            f"sfov_count={len(self.sfov_info_list)})"
        )

    def get_full_sfov_path(self, sfov_index: int) -> Path:
        return Path(self.root_directory) / self.sfov_info_list[sfov_index].path

    def get_tile_width_and_height(self) -> tuple[int, int]:
        first_sfov_full_path = self.get_full_sfov_path(0)
        with Image.open(first_sfov_full_path) as img:
             width, height = img.size
        # for sfov_info in self.sfov_info_list:
        #    full_path_str = self.get_full_sfov_path_str(sfov_info.sfov())
        #    with Image.open(full_path_str) as img:
        #        if img.size != (width, height):
        #            raise ValueError(f"SFOV image size mismatch: {full_path_str} has size {img.size}, "
        #                             f"but {first_sfov_full_path_str} has size  {width}x{height}")
        return width, height

    def map_sfov_info_list(self) -> dict[int, list[ScanMfov]]:
        # scan -> mfov -> list[SfovInfo]
        by_scan_then_mfov: dict[int, dict[int, list[SfovInfo]]] = {}

        for s in self.sfov_info_list:
            mfov_map = by_scan_then_mfov.setdefault(s.scan, {})
            mfov_map.setdefault(s.mfov, []).append(s)

        root = Path(self.root_directory)

        out: dict[int, list[ScanMfov]] = {}
        for scan, by_mfov in by_scan_then_mfov.items():
            # one ScanMfov per MFOV in this scan
            scan_mfovs = [
                ScanMfov.from_sfov_info_list(root, sfov_infos)
                for _, sfov_infos in by_mfov.items()
            ]
            scan_mfovs.sort(key=lambda sm: sm.mfov_number)
            out[scan] = scan_mfovs

        return out


def load_single_slab_info(json_path: Path) -> SingleSlabInfo:
    print(f"loading slab info from {json_path}")
    slab_info: SingleSlabInfo = SingleSlabInfo.model_validate_json(json_path.read_text())
    return slab_info


def main(argv: list[str]):
    json_path = Path(argv[1])
    slab_info = load_single_slab_info(json_path)
    print(f"{slab_info}")
    print(f"tile width and height: {slab_info.get_tile_width_and_height()}")

    scan_to_mfov_list = slab_info.map_sfov_info_list()
    sorted_scan_list = sorted(scan_to_mfov_list.keys())
    for scan in sorted_scan_list:
        mfov_list = scan_to_mfov_list[scan]
        print(f"Scan {scan} has {len(mfov_list)} MFOVs")
        for mfov in mfov_list:
            print(f"  MFOV {mfov.mfov_number} at ({mfov.center_x}, {mfov.center_y}) with {len(mfov.sfov_list)} SFOVs")


if __name__ == '__main__':
    if len(sys.argv) == 2:
        main(sys.argv)
    else:
        print("USAGE: single_slab_info.py <json_path>")
        # main(["go", "/nrs/hess/Hayworth/DATA_Wafer66_ForRenderTest/full_image_coordinates.txt.json"])
