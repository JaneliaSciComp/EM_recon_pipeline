import csv
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import List, Optional


@dataclass
class SlabInfo:
    id_serial: int
    id_magc: int = field(compare=False)
    id_stage: int = field(compare=False)
    first_scan_z: int = field(compare=False)
    name_len: int = field(compare=False)

    def serial_name(self) -> str:
        return f"{self.pad_id(self.id_serial)}"

    def dir_name(self) -> str:
        return f"{self.pad_id(self.id_stage + 1)}_"

    def stack_name(self) -> str:
        return f"s{self.serial_name()}_m{self.pad_id(self.id_magc)}"

    def pad_id(self, id_value: int) -> str:
        return "{id_value:0{name_len}d}".format(id_value=id_value, name_len=self.name_len)

    def __str__(self):
        return f"SlabInfo(id_serial='{self.id_serial}', id_magc={self.id_magc}, id_stage={self.id_stage}, " \
               f"first_scan_z={self.first_scan_z}, dir_name='{self.dir_name()}, stack_name='{self.stack_name()}')"


@dataclass
class ContiguousOrderedSlabGroup:
    ordered_slabs: List[SlabInfo]

    def to_render_project_name(self):
        assert len(self.ordered_slabs) > 0, "must have at least one ordered slab to derive a project name"
        return f"slab_{self.ordered_slabs[0].serial_name()}_to_{self.ordered_slabs[-1].serial_name()}"


def load_slab_info(ordering_scan_csv_path: Path,
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

    magc_to_serial_list = []
    magc_to_stage_list = []
    with open(ordering_scan_csv_path, 'r') as ordering_scan_csv_file:
        for row in csv.reader(ordering_scan_csv_file, delimiter=","):
            if "magc_to_serial" == row[0]:
                continue
            magc_to_serial_list.append(int(row[0]))
            magc_to_stage_list.append(int(row[2]))

    last_id_magc = len(magc_to_serial_list) - 1
    name_len = len(str(last_id_magc))

    slab_list = []
    for id_magc in range(0, len(magc_to_serial_list)):
        id_serial = magc_to_serial_list[id_magc]
        id_stage = magc_to_stage_list[id_magc]
        first_scan_z = (id_serial * max_number_of_scans) + 1  # make first z 1 instead of 0 to maintain old convention
        slab_list.append(
            SlabInfo(id_magc=id_magc,
                     id_serial=id_serial,
                     id_stage=id_stage,
                     first_scan_z=first_scan_z,
                     name_len=name_len))

    slab_group_list = []
    slab_group: Optional[ContiguousOrderedSlabGroup] = None

    for slab_info in sorted(slab_list, key=lambda si: si.id_serial):
        if slab_group is None or len(slab_group.ordered_slabs) >= number_of_slabs_per_group:
            if slab_group is not None:
                slab_group_list.append(slab_group)
            slab_group = ContiguousOrderedSlabGroup(ordered_slabs=[slab_info])
        else:
            slab_group.last_id_serial = slab_info.id_serial
            slab_group.ordered_slabs.append(slab_info)

    if slab_group is not None:
        slab_group_list.append(slab_group)

    return slab_group_list


def main(argv: List[str]):
    slab_group_list = load_slab_info(ordering_scan_csv_path=Path(argv[1]),
                                     max_number_of_scans=int(argv[2]),
                                     number_of_slabs_per_group=int(argv[3]))
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
