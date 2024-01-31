import csv
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

# determined by microscope operator
NAME_LEN = 3

@dataclass
class SlabInfo:
    id_serial: int
    id_magc: int = field(compare=False)
    id_stage: int = field(compare=False)
    first_scan_z: int = field(compare=False)
    serial_name: str = field(init=False, repr=False)
    dir_name: str = field(init=False)
    stack_name: str = field(init=False)
    
    def __post_init__(self):
        self.serial_name= f"{self.id_serial:0{NAME_LEN}}"
        self.dir_name = f"{self.id_stage + 1:0{NAME_LEN}}_"
        self.stack_name= f"s{self.serial_name}_m{self.id_magc:0{NAME_LEN}}"


@dataclass
class ContiguousOrderedSlabGroup:
    ordered_slabs: list[SlabInfo]
    last_id_serial: Optional[int] = None
    """assigned later, but currently unused"""

    def to_render_project_name(self) -> str:
        assert len(self.ordered_slabs) > 0, "must have at least one ordered slab to derive a project name"
        return f"slab_{self.ordered_slabs[0].serial_name}_to_{self.ordered_slabs[-1].serial_name}"


def load_slab_info(ordering_scan_csv_path: Path,
                   max_number_of_scans: int,
                   number_of_slabs_per_group: int) -> list[ContiguousOrderedSlabGroup]:
    """
    Ordering Scan CSV Format:
    
    magc_to_serial,serial_to_magc,magc_to_stage,stage_to_magc,serial_to_stage,stage_to_serial,angles_in_serial_order
    261,209,188,385,95,188,-18.261
    
    magc order:
      order in which the slabs were originally defined by the user with the MagFinder plugin in the .magc file
    stage order:
      order in which the slabs are acquired by the microscope to minimize stage travel
      encoded into scan subdirectories by the scope (e.g. wafer_53_scan_003_20220501_08-46-34/001_ , 002_, ...)
    serial order:
      order in which the slabs were physically cut
      
    note:
        we cannot do the following because id_magc is not guaranteed to be contiguous:
            for id_magc in range(0, len(magc_to_serial))
        instead, if we only need to iterate through all id_magc in no particular order, then use
            for id_magc in serial_to_magc:
        because serial_to_magc is guaranteed to contain all id_magc
    """
    if not ordering_scan_csv_path.exists():
        raise ValueError(f"cannot find {ordering_scan_csv_path}")

    magc_to_serial: list[int] = []
    magc_to_stage: list[int] = []
    serial_to_magc: list[int] = []
    with ordering_scan_csv_path.open('r') as ordering_scan_csv_file:
        for row in csv.reader(ordering_scan_csv_file, delimiter=","):
            if "magc_to_serial" == row[0]:
                continue
            magc_to_serial.append(int(row[0]))
            magc_to_stage.append(int(row[2]))
            serial_to_magc.append(int(row[1]))

    slabs: list[SlabInfo] = []
    for id_magc in serial_to_magc:
        id_serial = magc_to_serial[id_magc]
        id_stage = magc_to_stage[id_magc]
        first_scan_z = (id_serial * max_number_of_scans) + 1  # make first z 1 instead of 0 to maintain old convention
        slabs.append(
            SlabInfo(id_magc=id_magc,
                     id_serial=id_serial,
                     id_stage=id_stage,
                     first_scan_z=first_scan_z,))

    slab_group: Optional[ContiguousOrderedSlabGroup] = None
    slab_groups: list[ContiguousOrderedSlabGroup] = []

    for slab_info in sorted(slabs, key=lambda si: si.id_serial):
        if slab_group is None or len(slab_group.ordered_slabs) >= number_of_slabs_per_group:
            if slab_group is not None:
                slab_groups.append(slab_group)
            slab_group = ContiguousOrderedSlabGroup(ordered_slabs=[slab_info])
        else:
            slab_group.last_id_serial = slab_info.id_serial # why?
            slab_group.ordered_slabs.append(slab_info)

    if slab_group is not None:
        slab_groups.append(slab_group)

    return slab_groups


def main(argv: list[str]):
    slab_groups = load_slab_info(ordering_scan_csv_path=Path(argv[1]),
                                     max_number_of_scans=int(argv[2]),
                                     number_of_slabs_per_group=int(argv[3]))
    for slab_group in slab_groups:
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