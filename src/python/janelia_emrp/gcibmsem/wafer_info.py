from dataclasses import dataclass, field
from pathlib import Path
from typing import List

import sys

from janelia_emrp.gcibmsem.slab_info import load_slab_info, ContiguousOrderedSlabGroup


@dataclass
class WaferInfo:
    name: str
    base_path: Path
    resolution: List[float]
    slab_group_list: list[ContiguousOrderedSlabGroup] = field(compare=False)
    scan_paths: List[Path]


def load_wafer_info(wafer_base_path: Path,
                    number_of_slabs_per_group: int) -> WaferInfo:

    # <storage_root>/<wafer_id>/<scan_id>/<slab_stage_id>/<mFOV>/<sFOV>.png
    # /nrs/hess/render/raw/wafer_52
    #   /wafer_52_scan_000_20220401_20-19-52/002_/000003/002_000003_001_2022-04-01T1723012239596.png

    annotations_csv_path = Path(wafer_base_path, "annotations.csv")
    if not annotations_csv_path.exists():
        raise RuntimeError(f"cannot find {annotations_csv_path}")

    scan_paths = []
    for relative_scan_path in wafer_base_path.glob("wafer_*_scan_*"):
        scan_path = Path(wafer_base_path, relative_scan_path)
        if scan_path.is_dir():
            scan_paths.append(scan_path)

    slab_group_list = load_slab_info(annotations_csv_path=annotations_csv_path,
                                     max_number_of_scans=len(scan_paths),
                                     number_of_slabs_per_group=number_of_slabs_per_group)

    # TODO: parse resolution from experiment.yml or resolution.json (wafer_52 resolution hard-coded here)
    resolution = [8.0, 8.0, 10.0]

    return WaferInfo(name=wafer_base_path.name,
                     base_path=wafer_base_path,
                     resolution=resolution,
                     slab_group_list=slab_group_list,
                     scan_paths=scan_paths)


def main(argv: List[str]):
    wafer_info = load_wafer_info(wafer_base_path=Path(argv[1]),
                                 number_of_slabs_per_group=int(argv[2]))
    print(f"name: {wafer_info.name}")
    print(f"base_path: {wafer_info.base_path}")

    print(f"\nslab info ({len(wafer_info.slab_group_list)} groups):")
    for slab_group in wafer_info.slab_group_list:
        project = slab_group.to_render_project_name(wafer_info.name)
        print(f"  render project: {project} ({len(slab_group.ordered_slabs)} slabs):")
        for slab_info in slab_group.ordered_slabs:
            print(f"    {slab_info}")

    print(f"\nscan_paths ({len(wafer_info.scan_paths)} scans):")
    for scan_path in wafer_info.scan_paths:
        print(f"  {scan_path}")


if __name__ == '__main__':
    if len(sys.argv) == 3:
        main(sys.argv)
    else:
        print("USAGE: wafer_info.py <wafer_base_path> <number_of_slabs_per_group>")
