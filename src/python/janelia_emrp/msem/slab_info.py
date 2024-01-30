import csv
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import List, Optional


@dataclass
class SlabInfo:
    stage_name: str
    cut_index: int = field(compare=False)
    first_scan_z: int = field(compare=False)

    def dir_name(self) -> str:
        return f"{self.stage_name}_"

    def cut_name(self):
        return "{cut_index:0{name_len}d}".format(cut_index=self.cut_index, name_len=len(self.stage_name))

    def stack_name(self) -> str:
        return f"c{self.cut_name()}_s{self.stage_name}_v01"

    def __str__(self):
        return f"SlabInfo(stage_name='{self.stage_name}', cut_index={self.cut_index}, " \
               f"first_scan_z={self.first_scan_z}, stack_name='{self.stack_name()}')"


@dataclass
class ContiguousOrderedSlabGroup:
    first_cut_index: int
    last_cut_index: int
    ordered_slabs: List[SlabInfo]

    def to_render_project_name(self):
        assert len(self.ordered_slabs) > 0, "must have at least one ordered slab to derive a project name"
        return f"cut_{self.ordered_slabs[0].cut_name()}_to_{self.ordered_slabs[-1].cut_name()}"


def load_slab_info(ordering_scan_csv_path: Path,
                   slab_name_width: int,
                   max_number_of_scans: int,
                   number_of_slabs_per_group: int) -> list[ContiguousOrderedSlabGroup]:
    if not ordering_scan_csv_path.exists():
        raise ValueError(f"cannot find {ordering_scan_csv_path}")

    # Ordering Scan CSV Format:
    #
    # magc_to_serial,serial_to_magc,magc_to_stage,stage_to_magc,serial_to_stage,stage_to_serial,angles_in_serial_order
    # 261,209,188,385,95,188,-18.261
    #
    # magc order:
    #   order in which the slabs were originally defined by the user with the MagFinder plugin in the .magc file
    # stage order:
    #   order in which the slabs are acquired by the microscope to minimize stage travel
    #   encoded into scan subdirectories by the scope (e.g. wafer_53_scan_003_20220501_08-46-34/001_ , 002_, ...)
    # serial order:
    #   order in which the slabs were physically cut

    stage_to_serial_list = []
    with open(ordering_scan_csv_path, 'r') as ordering_scan_csv_file:
        for row in csv.reader(ordering_scan_csv_file, delimiter=","):
            if "magc_to_serial" == row[0]:
                continue
            stage_to_serial_list.append(int(row[5]))

    slab_name_to_info = {}
    first_z_to_slab_name = {}
    for cut_index in range(0, len(stage_to_serial_list)):
        stage = stage_to_serial_list[cut_index]
        slab_name = "{stage:0{name_len}d}".format(stage=stage, name_len=slab_name_width)
        first_scan_z = cut_index * max_number_of_scans
        slab_name_to_info[slab_name] = SlabInfo(stage_name=slab_name,
                                                cut_index=cut_index,
                                                first_scan_z=first_scan_z)
        first_z_to_slab_name[first_scan_z] = slab_name

    slab_group_list = []
    slab_group: Optional[ContiguousOrderedSlabGroup] = None

    for first_z in sorted(first_z_to_slab_name.keys()):
        slab_name = first_z_to_slab_name[first_z]
        slab_info = slab_name_to_info[slab_name]

        if slab_group is None or len(slab_group.ordered_slabs) >= number_of_slabs_per_group:
            if slab_group is not None:
                slab_group_list.append(slab_group)
            slab_group = ContiguousOrderedSlabGroup(first_cut_index=slab_info.cut_index,
                                                    last_cut_index=slab_info.cut_index,
                                                    ordered_slabs=[slab_info])
        else:
            slab_group.last_cut_index = slab_info.cut_index
            slab_group.ordered_slabs.append(slab_info)

    if slab_group is not None:
        slab_group_list.append(slab_group)

    return slab_group_list


def main(argv: List[str]):
    slab_group_list = load_slab_info(ordering_scan_csv_path=Path(argv[1]),
                                     max_number_of_scans=int(argv[2]),
                                     number_of_slabs_per_group=int(argv[3]),
                                     slab_name_width=3)
    for slab_group in slab_group_list:
        print(f"render project: {slab_group.to_render_project_name()} "
              f"({len(slab_group.ordered_slabs)} slabs):")
        for slab_info in slab_group.ordered_slabs:
            print(f"  {slab_info}")


if __name__ == '__main__':
    if len(sys.argv) == 4:
        main(sys.argv)
    else:
        print("USAGE: slab_info.py <ordering_scan_csv_path> <max_number_of_scans> <number_of_slabs_per_group>")
        # main(["go", "/nrs/hess/data/hess_wafer_53/raw/ordering/scan_001.csv", "48", "10"])
