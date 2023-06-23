import csv
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import List, Optional


@dataclass
class SlabInfo:
    name: str
    acquisition_index: int = field(compare=False)
    cut_index: int = field(compare=False)
    first_scan_z: int = field(compare=False)

    def dir_name(self) -> str:
        return f"{self.name}_"

    def slab_index(self) -> int:
        return self.acquisition_index + 1

    def cut_name(self):
        return "{cut_index:0{name_len}d}".format(cut_index=self.cut_index, name_len=len(self.name))

    def stack_name(self) -> str:
        return f"c{self.cut_name()}_s{self.name}_v01"

    def __str__(self):
        return f"SlabInfo(name='{self.name}', acquisition_index={self.acquisition_index}, " \
               f"cut_index={self.cut_index}, first_scan_z={self.first_scan_z}, stack_name='{self.stack_name()}')"


@dataclass
class ContiguousOrderedSlabGroup:
    first_cut_index: int
    last_cut_index: int
    ordered_slabs: List[SlabInfo]

    def to_render_project_name(self):
        assert len(self.ordered_slabs) > 0, "must have at least one ordered slab to derive a project name"
        return f"cut_{self.ordered_slabs[0].cut_name()}_to_{self.ordered_slabs[-1].cut_name()}"


def load_slab_info(ordering_dir_path: Path,
                   slab_name_width: int,
                   max_number_of_scans: int,
                   number_of_slabs_per_group: int) -> list[ContiguousOrderedSlabGroup]:
    magc_id_to_stage_order = {}
    serial_order_to_magc_id = {}

    first_scan_csv_path = ordering_dir_path / "scan_000.csv"
    with open(first_scan_csv_path, 'r') as first_scan_csv_file:
        # magc_to_serial,serial_to_magc,magc_to_stage,stage_to_magc,serial_to_stage,stage_to_serial,angles_in_serial_order
        # 261,209,188,385,95,188,-18.261
        line_number = 0
        for row in csv.reader(first_scan_csv_file, delimiter=","):
            line_number = line_number + 1
            if "magc_to_serial" == row[0]:
                continue
            magc_id = line_number - 2
            serial_order = int(row[0])
            stage_order = int(row[2])
            magc_id_to_stage_order[magc_id] = stage_order
            serial_order_to_magc_id[serial_order] = magc_id

    slab_name_to_info = {}
    first_z_to_slab_name = {}
    for magc_id in magc_id_to_stage_order:
        stage_order = magc_id_to_stage_order[magc_id]
        cut_index = serial_order_to_magc_id[stage_order]

        scope_slab_index = magc_id + 1
        slab_name = "{slab_index:0{name_len}d}".format(slab_index=scope_slab_index, name_len=slab_name_width)
        first_scan_z = cut_index * max_number_of_scans
        slab_name_to_info[slab_name] = SlabInfo(name=slab_name,
                                                acquisition_index=magc_id,
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
    slab_group_list = load_slab_info(ordering_dir_path=Path(argv[1]),
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
        print("USAGE: slab_info.py <ordering_dir_path> <max_number_of_scans> <number_of_slabs_per_group>")
        # main(["go", "/nrs/hess/render/raw/wafer_53/ordering", "48", "10"])
