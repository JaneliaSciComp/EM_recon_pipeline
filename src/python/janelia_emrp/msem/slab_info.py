import sys
from dataclasses import dataclass, field

import xarray

from janelia_emrp.msem.field_of_view_layout import MFovPosition
from janelia_emrp.msem.ingestion_ibeammsem.assembly import get_xys_sfov_and_paths
from janelia_emrp.msem.ingestion_ibeammsem.id import get_all_magc_ids, get_serial_ids, get_region_ids
from janelia_emrp.msem.ingestion_ibeammsem.roi import get_mfovs

WAFER_NAME_LEN = 2   # wafers 60 and 61
SERIAL_NAME_LEN = 3  # 400+ slabs per wafer
REGION_NAME_LEN = 2  # usually only a few regions per slab, but allow for up to 99

MAX_NUMBER_OF_MFOVS = 100
MAX_NUMBER_OF_SCANS = 500

@dataclass
class SlabInfo:
    wafer_id: int
    serial_id: int                                     # order in which the slabs were physically cut
    region: int
    magc_id: int = field(compare=False)                # order in which the slabs were originally defined by the user with the MagFinder plugin in the .magc file
    first_mfov: int = field(compare=False)
    last_mfov: int = field(compare=False)
    serial_name: str = field(init=False, repr=False)
    stack_name: str = field(init=False)

    def __post_init__(self):
        self.serial_name = f"{self.serial_id:0{SERIAL_NAME_LEN}}"
        self.stack_name = f"w{self.wafer_id:0{WAFER_NAME_LEN}}_s{self.serial_name}_r{self.region:0{REGION_NAME_LEN}}"

    def build_mfov_position_list(self,
                                 xlog: xarray.Dataset,
                                 scan: int = 0) -> list[MFovPosition]:
        mfov_position_list = []
        for mfov in range(self.first_mfov, self.last_mfov + 1):
            mfov_path_list, mfov_xys = get_xys_sfov_and_paths(xlog=xlog,
                                                              scan=scan,
                                                              slab=self.magc_id,
                                                              mfov=mfov)
            sfov_1_stage_x, sfov_1_stage_y = mfov_xys[0]
            mfov_position_list.append(MFovPosition(mfov, int(sfov_1_stage_x), int(sfov_1_stage_y)))

        return mfov_position_list


@dataclass
class ContiguousOrderedSlabGroup:
    ordered_slabs: list[SlabInfo]

    def to_render_project_name(self) -> str:
        assert len(self.ordered_slabs) > 0, "must have at least one ordered slab to derive a project name"
        return f"serial_{self.ordered_slabs[0].serial_name}_to_{self.ordered_slabs[-1].serial_name}"


def load_slab_info(xlog: xarray.Dataset,
                   wafer_id: int,
                   number_of_slabs_per_group: int) -> list[ContiguousOrderedSlabGroup]:

    magc_ids = get_all_magc_ids(xlog=xlog).tolist()
    serial_ids = get_serial_ids(xlog=xlog, magc_ids=magc_ids)

    slabs: list[SlabInfo] = []
    for i in range(len(magc_ids)):
        id_serial=serial_ids[i]
        slab = magc_ids[i]
        mfovs = get_mfovs(xlog=xlog, slab=slab)
        region_ids = get_region_ids(xlog=xlog, slab=slab, mfovs=mfovs)
        id_region = region_ids[0]

        slabs.append(
            SlabInfo(wafer_id=wafer_id,
                     serial_id=id_serial,
                     region=id_region,
                     magc_id=slab,
                     first_mfov=0,
                     last_mfov=0))

        for j in range(1, len(region_ids)):
            if region_ids[j] != id_region:
                id_region = region_ids[j]
                slabs.append(
                    SlabInfo(wafer_id=wafer_id,
                             serial_id=id_serial,
                             region=id_region,
                             magc_id=slab,
                             first_mfov=j,
                             last_mfov=j))
            else:
                slabs[-1].last_mfov = j

    if len(slabs) == 0:
        return []

    sorted_slabs = sorted(slabs, key=lambda si: si.stack_name)

    slab_group: ContiguousOrderedSlabGroup = ContiguousOrderedSlabGroup(ordered_slabs=[sorted_slabs[0]])
    slab_groups: list[ContiguousOrderedSlabGroup] = []
    last_serial_id = sorted_slabs[0].serial_id
    serial_id_count = 1

    for i in range(1, len(sorted_slabs)):
        slab_info = sorted_slabs[i]
        if slab_info.serial_id != last_serial_id:
            last_serial_id = slab_info.serial_id
            serial_id_count += 1
        if serial_id_count > number_of_slabs_per_group:
            slab_groups.append(slab_group)
            slab_group = ContiguousOrderedSlabGroup(ordered_slabs=[slab_info])
            serial_id_count = 1
        else:
            slab_group.ordered_slabs.append(slab_info)

    slab_groups.append(slab_group)

    return slab_groups


def main(argv: list[str]):
    print(f"opening {argv[1]} ...")
    xlog = xarray.open_zarr(argv[1])

    print(f"loading slab info with wafer_id {argv[2]} and {argv[3]} number_of_slabs_per_group ...")
    slab_groups = load_slab_info(xlog=xlog,
                                 wafer_id=int(argv[2]),
                                 number_of_slabs_per_group=int(argv[3]))
    for slab_group in slab_groups:
        print(f"render project: {slab_group.to_render_project_name()} "
              f"({len(slab_group.ordered_slabs)} slab regions):")
        for slab_info in slab_group.ordered_slabs:
            print(f"  {slab_info}")


if __name__ == '__main__':
    if len(sys.argv) == 4:
        main(sys.argv)
    else:
        print("USAGE: slab_info.py <xlog path> <wafer id> <number_of_slabs_per_group>")
        # main(["go", "/groups/hess/hesslab/ibeammsem/system_02/wafers/wafer_60/xlog/xlog_wafer_60.zarr", "60", "10"])
