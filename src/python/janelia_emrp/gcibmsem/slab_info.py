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

    def stack_name(self) -> str:
        return f"cut_{self.cut_index:04d}_s{self.name}_acquire"


@dataclass
class ContiguousOrderedSlabGroup:
    first_cut_index: int
    last_cut_index: int
    ordered_slabs: List[SlabInfo]

    def to_render_project_name(self, wafer_name: str):
        return f"{wafer_name}_cut_{self.first_cut_index:04d}_to_{self.last_cut_index:04d}"


def load_slab_info(annotations_csv_path: Path,
                   max_number_of_scans: int,
                   number_of_slabs_per_group: int) -> list[ContiguousOrderedSlabGroup]:
    section_id_to_stage_order = {}
    serial_order_to_section_id = {}
    with open(annotations_csv_path, 'r') as data_file:
        # section_id,section_center_x,section_center_y,section_angle,roi_center_x,roi_center_y,roi_angle,magnet_x,magnet_y,landmark_x,landmark_y,stage_order,serial_order
        # 0,23807.8066406,20754.3613281,-48.4199960769,23784.621655,20696.7351581,-48.4198976059,,,3979.47998047,40357.2695312,39,4,,,,,,,,,21367.3339844,21099.6660156,,,,,,,,,,,22924.0,21461.0,,,,,,,,,,,23469.5,20512.5,,
        for row in csv.reader(data_file, delimiter=","):
            if "section_id" == row[0]:
                continue
            section_id = int(row[0])
            stage_order = int(row[11])
            serial_order = int(row[12])
            section_id_to_stage_order[section_id] = stage_order
            serial_order_to_section_id[serial_order] = section_id

    slab_name_to_info = {}
    first_z_to_slab_name = {}
    for section_id in section_id_to_stage_order:
        stage_order = section_id_to_stage_order[section_id]
        cut_index = serial_order_to_section_id[stage_order]

        scope_slab_index = section_id + 1
        slab_name = f"{scope_slab_index:03d}"
        first_scan_z = cut_index * max_number_of_scans
        slab_name_to_info[slab_name] = SlabInfo(name=slab_name,
                                                acquisition_index=section_id,
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
    slab_group_list = load_slab_info(annotations_csv_path=Path(argv[1]),
                                     max_number_of_scans=int(argv[2]),
                                     number_of_slabs_per_group=int(argv[3]))
    for slab_group in slab_group_list:
        print(f"render project: {slab_group.to_render_project_name('wafer')} ({len(slab_group.ordered_slabs)} slabs):")
        for slab_info in slab_group.ordered_slabs:
            print(f"  {slab_info}")


if __name__ == '__main__':
    if len(sys.argv) == 4:
        main(sys.argv)
    else:
        print("USAGE: slab_info.py <annotations_csv_path> <max_number_of_scans> <number_of_slabs_per_group>")
        # main(["go", "/nrs/hess/render/raw/wafer_52/annotations.csv", "35", "10"])
