import re
import sys
from dataclasses import dataclass, field

import xarray

from janelia_emrp.msem.field_of_view_layout import MFovPosition
from janelia_emrp.msem.ingestion_ibeammsem.assembly import get_xys_sfov_and_paths
from janelia_emrp.msem.ingestion_ibeammsem.id import get_all_magc_ids, get_serial_ids, get_region_ids, get_magc_ids
from janelia_emrp.msem.ingestion_ibeammsem.roi import get_mfovs

SERIAL_NAME_LEN = 3  # 400+ slabs per wafer
REGION_NAME_LEN = 2  # usually only a few regions per slab, but allow for up to 99

MAX_NUMBER_OF_SCANS = 500

@dataclass
class SlabInfo:
    wafer_short_prefix: str
    """short prefix for wafer that gets prepended to all project and stack names
    
    For data sets that only have one wafer, this should be an empty string.
    For data sets with multiple wafers, this should be something like 'w60_'.
    """
    serial_id: int
    """order in which the slabs were physically cut"""
    magc_id: int = field(compare=False)
    """magc ID.
    
    order in which the slabs were originally defined by the user
    with the MagFinder plugin in the .magc file
    """
    region: int
    first_mfov: int = field(compare=False)
    last_mfov: int = field(compare=False)
    serial_name: str = field(init=False, repr=False)
    stack_name: str = field(init=False)

    def __post_init__(self):
        self.serial_name = f"{self.serial_id:0{SERIAL_NAME_LEN}}"
        self.stack_name = f"{self.wafer_short_prefix}s{self.serial_name}_r{self.region:0{REGION_NAME_LEN}}"

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
    
    @property
    def mfovs(self)->list[int]:
        """MFOV IDs of the SlabInfo."""
        return list(range(self.first_mfov, self.last_mfov + 1))

@dataclass
class ContiguousOrderedSlabGroup:
    ordered_slabs: list[SlabInfo]

    def to_render_project_name(self,
                               slabs_per_group: int) -> str:
        assert len(self.ordered_slabs) > 0, "must have at least one ordered slab to derive a project name"
        first_slab = self.ordered_slabs[0]
        first_group_serial_id = int((first_slab.serial_id / slabs_per_group)) * slabs_per_group
        last_group_serial_id = first_group_serial_id + slabs_per_group - 1
        return f"{first_slab.wafer_short_prefix}serial_{first_group_serial_id:0{SERIAL_NAME_LEN}}_to_{last_group_serial_id:0{SERIAL_NAME_LEN}}"


def load_slab_info(xlog: xarray.Dataset,
                   wafer_short_prefix: str,
                   number_of_slabs_per_group: int) -> list[ContiguousOrderedSlabGroup]:

    magc_ids = get_all_magc_ids(xlog=xlog).tolist()

    slabs: list[SlabInfo] = []
    magc_ids_without_regions: list[int] = []
    for slab in magc_ids:
        id_serial=get_serial_ids(xlog=xlog,magc_ids=[slab])[0]
        mfovs = get_mfovs(xlog=xlog, slab=slab)
        region_ids = get_region_ids(xlog=xlog, slab=slab, mfovs=mfovs)
        if len(region_ids) == 0:
            magc_ids_without_regions.append(slab)
            continue
        id_region = region_ids[0]

        slabs.append(
            SlabInfo(wafer_short_prefix=wafer_short_prefix,
                     serial_id=id_serial,
                     region=id_region,
                     magc_id=slab,
                     first_mfov=0,
                     last_mfov=0))

        for j in range(1, len(region_ids)):
            if region_ids[j] != id_region:
                id_region = region_ids[j]
                slabs.append(
                    SlabInfo(wafer_short_prefix=wafer_short_prefix,
                             serial_id=id_serial,
                             region=id_region,
                             magc_id=slab,
                             first_mfov=j,
                             last_mfov=j))
            else:
                slabs[-1].last_mfov = j

    if len(magc_ids_without_regions) > 0:
        print(
            f"found {len(magc_ids_without_regions)} magc ids"
            f" without regions: {magc_ids_without_regions}, "
            "this occurs when the block is sectioned before/after the ROI starts/ends,"
        )

    if len(slabs) == 0:
        return []

    mfov_counts = [len(slab.mfovs) for slab in slabs]
    average_mfov_count = sum(mfov_counts) / len(mfov_counts)
    print(
        f"found {len(slabs)} region slabs"
        f" with {max(mfov_counts)} max mfovs"
        f" and {average_mfov_count:.0f} average mfovs"
    )    
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

# w60_s296_r00...
STACK_PATTERN = re.compile(r"(.*_)s(\d{3})_r(\d{2}).*")

def build_slab_info_from_stack_name(xlog: xarray.Dataset,
                                    stack_name: str) -> SlabInfo:
    # w60_s296_r00
    stack_pattern_match = STACK_PATTERN.match(stack_name)
    if not stack_pattern_match:
        raise RuntimeError(f"failed to parse stack_name {stack_name}")

    wafer_short_prefix = stack_pattern_match.group(1)
    serial_id = int(stack_pattern_match.group(2))
    region = int(stack_pattern_match.group(3))

    try:
        magc_id = get_magc_ids(xlog=xlog, serial_ids=[serial_id])[0]
    except ValueError as value_error:
        raise RuntimeError from value_error

    mfovs = get_mfovs(xlog=xlog, slab=magc_id)
    region_ids = get_region_ids(xlog=xlog, slab=magc_id, mfovs=mfovs)
    first_mfov = None
    last_mfov = None
    for i in range(len(region_ids)):
        if region_ids[i] == region:
            if first_mfov is None:
                first_mfov = i
            last_mfov = i
        elif region_ids[i] > region:
            break

    return SlabInfo(wafer_short_prefix=wafer_short_prefix,
                    serial_id=serial_id,
                    region=region,
                    magc_id=magc_id,
                    first_mfov=first_mfov,
                    last_mfov=last_mfov)

def main(argv: list[str]):
    print(f"opening {argv[1]} ...")
    xlog = xarray.open_zarr(argv[1])

    print(f"loading slab info with wafer_short_prefix {argv[2]} and {argv[3]} number_of_slabs_per_group ...")
    number_of_slabs_per_group=int(argv[3])
    slab_groups = load_slab_info(xlog=xlog,
                                 wafer_short_prefix=argv[2],
                                 number_of_slabs_per_group=number_of_slabs_per_group)
    print("")
    for slab_group in slab_groups:
        print(f"render project: {slab_group.to_render_project_name(number_of_slabs_per_group)} "
              f"({len(slab_group.ordered_slabs)} slab regions):")
        for slab_info in slab_group.ordered_slabs:
            print(f"  {slab_info}")


if __name__ == '__main__':
    if len(sys.argv) == 4:
        main(sys.argv)
    else:
        print("USAGE: slab_info.py <xlog_path> <wafer_short_prefix> <number_of_slabs_per_group>")
        # main(["go", "/groups/hess/hesslab/ibeammsem/system_02/wafers/wafer_60/xlog/xlog_wafer_60.zarr", "w60_", "10"])
        # main(["go", "/groups/hess/hesslab/ibeammsem/system_02/wafers/wafer_61/xlog/xlog_wafer_61.zarr", "w61_", "10"])
