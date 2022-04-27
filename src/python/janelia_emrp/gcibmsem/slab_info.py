import csv
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import List


@dataclass
class SlabInfo:
    name: str
    acquisition_index: int = field(compare=False)
    cut_index: int = field(compare=False)
    first_scan_z: int = field(compare=False)


def load_slab_info(annotations_csv_path: Path,
                   max_number_of_scans: int) -> dict[str, SlabInfo]:
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
    for section_id in section_id_to_stage_order:
        stage_order = section_id_to_stage_order[section_id]
        cut_index = serial_order_to_section_id[stage_order]

        scope_slab_index = section_id + 1
        slab_name = f"{scope_slab_index:03d}_"
        slab_name_to_info[slab_name] = SlabInfo(name=slab_name,
                                                acquisition_index=section_id,
                                                cut_index=cut_index,
                                                first_scan_z=(cut_index * max_number_of_scans))

    return slab_name_to_info


def main(argv: List[str]):
    slab_name_to_info = load_slab_info(annotations_csv_path=Path(argv[1]),
                                       max_number_of_scans=int(argv[2]))
    for slab_name in sorted(slab_name_to_info.keys()):
        print(slab_name_to_info[slab_name])


if __name__ == '__main__':
    if len(sys.argv) == 3:
        main(sys.argv)
    else:
        print("USAGE: slab_info.py <annotations_csv_path> <max_number_of_scans>")
