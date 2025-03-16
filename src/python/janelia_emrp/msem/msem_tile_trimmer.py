import argparse
import logging
import sys
import traceback
from pathlib import Path
from typing import List, Any

import xarray

from janelia_emrp.msem.ingestion_ibeammsem.roi import get_roi_sfovs
from janelia_emrp.msem.ingestion_ibeammsem.metrics import get_resin_mask
from janelia_emrp.msem.tile_id import TileID
from janelia_emrp.msem.ingestion_ibeammsem.constant import N_BEAMS
from janelia_emrp.msem.slab_info import build_slab_info_from_stack_name
from janelia_emrp.render.web_service_request import RenderRequest
from janelia_emrp.root_logger import init_logger

program_name = "msem_tile_trimmer.py"

logger = logging.getLogger(__name__)


def create_trimmed_stacks(render_ws_host_and_port: str,
                          render_owner: str,
                          render_project: str,
                          render_stack_list: list[str],
                          dilation: int,
                          wafer_xlog_path: Path):

    func_name = "create_trimmed_stacks"

    logger.info(f"{func_name}: opening {wafer_xlog_path}")

    if not wafer_xlog_path.exists():
        raise RuntimeError(f"cannot find wafer xlog: {wafer_xlog_path}")

    xlog = xarray.open_zarr(wafer_xlog_path)

    for stack in render_stack_list:
        logger.info(f"{func_name}: trimming stack {stack} with dilation {dilation}")

        slab_info = build_slab_info_from_stack_name(xlog=xlog, stack_name=stack)

        logger.info(f"{func_name}: loaded slab_info: {slab_info}")

        roi_names = {}
        total_sfov_count = len(slab_info) * N_BEAMS
        for mfov in slab_info.mfovs:
            for zero_based_sfov_id in get_roi_sfovs(xlog=xlog, slab=slab_info.magc_id, mfov=mfov, dilation=dilation):
                one_based_sfov_id = zero_based_sfov_id + 1 # to keep consistent with the scope SFOV file names
                roi_names[f"{mfov:04}_s{one_based_sfov_id:02}"] = True

        if len(roi_names) == 0:
            logger.warning(f"{func_name}: skipping stack {stack} because no SFOVs are within the ROI, "
                           f"consider using a dilation value larger than {dilation}")
            continue
        if len(roi_names) == total_sfov_count:
            logger.warning(f"{func_name}: skipping stack {stack} because all SFOVs are within the ROI, "
                           f"consider using a dilation value smaller than {dilation}")
            continue

        logger.info(f"{func_name}: {len(roi_names)} out of {total_sfov_count} SFOVs in each z layer are within the ROI")

        render_request = RenderRequest(host=render_ws_host_and_port,
                                       owner=render_owner,
                                       project=render_project)

        project_stack_names = set(stack_id["stack"] for stack_id in render_request.get_stack_ids())
        if stack not in project_stack_names:
            logger.warning(f"{func_name}: skipping stack {stack} because it does not exist in the project")
            continue

        trimmed_stack = f"{stack}_d{dilation:02}"
        if trimmed_stack in project_stack_names:
            logger.warning(f"{func_name}: skipping stack {stack} because trimmed stack {trimmed_stack} already exists")
            continue

        stack_version = render_request.get_stack_metadata(stack)["currentVersion"]
        stack_version["versionNotes"] = f"ROI with dilation {dilation} from {stack}"

        render_request.create_stack(stack=trimmed_stack,
                                    stack_version=stack_version)

        z_values = render_request.get_z_values(stack)

        # process 10 z layers at a time to reduce the total number of requests
        # while ensuring we don't exceed the maximum number of tiles per request (currently 100,000)
        for i in range(0, len(z_values), 10):
            min_z = z_values[i]
            max_z = z_values[min(i + 9, len(z_values) - 1)]

            resolved_tiles = render_request.get_all_resolved_tiles_for_stack(stack=stack,
                                                                             min_z=min_z,
                                                                             max_z=max_z)
            tile_id_to_spec_map = resolved_tiles["tileIdToSpecMap"]

            filtered_map: dict[str, Any] = {}
            for tile_id_str in tile_id_to_spec_map.keys():
                tile_id = TileID.from_string(tile_id_str)
                if tile_id.to_roi_name() not in roi_names or get_resin_mask(
                    xlog=xlog, scan=tile_id.scan, slab=tile_id.slab, mfov=tile_id.mfov
                ).sel(sfov=tile_id.sfov):
                    continue
                filtered_map[tile_id_str] = tile_id_to_spec_map[tile_id_str]

            removed_count = len(tile_id_to_spec_map) - len(filtered_map)
            logger.info(f"{func_name}: loaded {len(tile_id_to_spec_map)} tiles, "
                        f"removed {removed_count} outside the ROI, "
                        f"saving {len(filtered_map)} for z {min_z} to {max_z} to stack {trimmed_stack}")

            if len(filtered_map) > 0:
                resolved_tiles["tileIdToSpecMap"] = filtered_map

                render_request.save_resolved_tiles(stack=trimmed_stack,
                                                   resolved_tiles=resolved_tiles)
            else:
                logger.warning(f"{func_name}: skipping z {min_z} to {max_z} because no tiles are within the ROI")

        render_request.set_stack_state_to_complete(stack=trimmed_stack)

def main(arg_list: List[str]):
    parser = argparse.ArgumentParser(
        description="Create stacks by trimming off empty tiles using a region of interest dilation value."
    )
    parser.add_argument(
        "--render_host",
        help="Render web services host (e.g. em-services-1.int.janelia.org)",
        required=True,
    )
    parser.add_argument(
        "--render_port",
        help="Render web services post (e.g. 8080)",
        type=int,
        default=8080,
    )
    parser.add_argument(
        "--render_owner",
        help="Owner for all render stacks",
        required=True,
    )
    parser.add_argument(
        "--render_project",
        help="Project for all render stacks",
        required=True,
    )
    parser.add_argument(
        "--render_stack",
        help="Stack(s) to trim.  Result trimmed stacks will be named '<stack>_d<dilation>' (e.g. w60_s296_r00_d30).",
        nargs='+',
        required=True,
    )
    parser.add_argument(
        "--dilation",
        help="Integral dilation value for the region of interest (e.g. 30)",
        type=int,
        required=True,
    )
    parser.add_argument(
        "--path_xlog",
        help="Path of the wafer xarray (e.g. /groups/hess/hesslab/ibeammsem/system_02/wafers/wafer_60/xlog/xlog_wafer_60.zarr)",
        required=True,
    )
    args = parser.parse_args(args=arg_list)

    create_trimmed_stacks(render_ws_host_and_port=f"{args.render_host}:{args.render_port}",
                          render_owner=args.render_owner,
                          render_project=args.render_project,
                          render_stack_list=args.render_stack,
                          dilation=args.dilation,
                          wafer_xlog_path=Path(args.path_xlog))


if __name__ == '__main__':
    # NOTE: to fix module not found errors, export PYTHONPATH="/.../EM_recon_pipeline/src/python"

    # setup logger since this module is the main program
    init_logger(__file__)

    # noinspection PyBroadException
    try:
        main(sys.argv[1:])
        # main([
        #     "--render_host", "em-services-1.int.janelia.org",
        #     "--render_port", "8080",
        #     "--render_owner", "trautmane",
        #     "--render_project", "w60_serial_290_to_299",
        #     "--render_stack", "w60_s296_r00",
        # #     "w60_s296_r01", "w60_s297_r00", "w60_s297_r01",
        #     "--dilation", "0",
        #     "--path_xlog", "/groups/hess/hesslab/ibeammsem/system_02/wafers/wafer_60/xlog/xlog_wafer_60.zarr",
        # ])
    except Exception as e:
        # ensure exit code is a non-zero value when Exception occurs
        traceback.print_exc()
        sys.exit(1)
