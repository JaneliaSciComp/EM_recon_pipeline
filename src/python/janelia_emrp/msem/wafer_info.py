import argparse
from dataclasses import dataclass, field
from pathlib import Path
from typing import List

import sys

from janelia_emrp.msem.slab_info import load_slab_info, ContiguousOrderedSlabGroup


@dataclass
class WaferInfo:
    name: str
    base_path: Path
    resolution: List[float]
    slab_group_list: list[ContiguousOrderedSlabGroup] = field(compare=False)
    scan_paths: List[Path]

    def print_me(self):
        print(f"name: {self.name}")
        print(f"base_path: {self.base_path}")

        print(f"\nslab info ({len(self.slab_group_list)} groups):")
        for slab_group in self.slab_group_list:
            project = slab_group.to_render_project_name()
            print(f"  render project: {project} ({len(slab_group.ordered_slabs)} slabs):")
            for slab_info in slab_group.ordered_slabs:
                print(f"    {slab_info}")

        print(f"\nscan_paths ({len(self.scan_paths)} scans):")
        for scan_path in self.scan_paths:
            print(f"  {scan_path}")


def load_wafer_info(wafer_base_path: Path,
                    number_of_slabs_per_group: int,
                    exclude_scan_name_list: list[str]) -> WaferInfo:

    # <storage_root>/<wafer_id>/imaging/msem/<simple_scan_name>/<scan_id>/<slab_name>_/<mFOV>/<sFOV>.png
    # /nrs/hess/render/raw/wafer_53/imaging/msem/scan_003/wafer_53_scan_003_20220501_08-46-34
    #   /012_/000003/012_000003_042_2022-05-01T0618013636729.png

    scan_paths = []
    for relative_scan_path in wafer_base_path.glob("imaging/msem/scan_???/*_scan_*"):
        scan_path = Path(wafer_base_path, relative_scan_path)
        if scan_path.is_dir():
            simple_scan_name = scan_path.parent.name
            if len(exclude_scan_name_list) == 0 or simple_scan_name not in exclude_scan_name_list:
                scan_paths.append(scan_path)

    if len(scan_paths) == 0:
        raise ValueError(f"no scan paths found in {wafer_base_path} with exclude_scan_names {exclude_scan_name_list}")

    simple_scan_name = scan_paths[0].parent.name
    ordering_scan_csv_path = wafer_base_path / "ordering" / f"{simple_scan_name}.csv"

    if not ordering_scan_csv_path.exists():
        raise ValueError(f"cannot find {ordering_scan_csv_path}")

    slab_group_list = load_slab_info(ordering_scan_csv_path=ordering_scan_csv_path,
                                     number_of_slabs_per_group=number_of_slabs_per_group)

    # TODO: parse resolution from /nrs/hess/data/hess_wafer_53/raw/resolution.json (wafer_53 resolution hard-coded here)
    resolution = [8.0, 8.0, 8.0]

    return WaferInfo(name=wafer_base_path.name,
                     base_path=wafer_base_path,
                     resolution=resolution,
                     slab_group_list=slab_group_list,
                     scan_paths=scan_paths)


def build_wafer_info_parent_parser() -> argparse.ArgumentParser:
    # see https://docs.python.org/3/library/argparse.html#parents
    parent_parser = argparse.ArgumentParser(add_help=False)
    parent_parser.add_argument(
        "--wafer_base_path",
        help="Base path for wafer data (e.g. /nrs/hess/render/raw/wafer_53)",
        required=True,
    )
    parent_parser.add_argument(
        "--number_of_slabs_per_render_project",
        help="Number of slabs to group together into one render project",
        type=int,
        default=10
    )
    # NOTE: to exclude entire slabs, we decided to simply delete the stack after import
    parent_parser.add_argument(
        "--exclude_scan_name",
        help="Exclude these scan names from the render stacks (e.g. scan_000)",
        nargs='+',
        default=[]
    )
    return parent_parser


def main(arg_list: list[str]):
    parser = argparse.ArgumentParser(
        description="Parse and print wafer metadata.",
        parents=[build_wafer_info_parent_parser()]
    )
    args = parser.parse_args(args=arg_list)

    wafer_info = load_wafer_info(wafer_base_path=Path(args.wafer_base_path),
                                 number_of_slabs_per_group=args.number_of_slabs_per_render_project,
                                 exclude_scan_name_list=args.exclude_scan_name)
    wafer_info.print_me()


if __name__ == '__main__':
    main(sys.argv[1:])
    # main([
    #     "--wafer_base_path", "/nrs/hess/data/hess_wafer_53/raw",
    #     "--exclude_scan_name", "scan_000"
    # ])
