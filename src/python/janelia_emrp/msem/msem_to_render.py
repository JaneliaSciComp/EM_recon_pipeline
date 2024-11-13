import argparse
import logging
import re
import sys
import time
import traceback
from pathlib import Path
from typing import List, Any, Optional

import renderapi
import xarray
from PIL import Image
from renderapi import Render
from renderapi.errors import RenderError

from janelia_emrp.fibsem.render_api import RenderApi
from janelia_emrp.fibsem.volume_transfer_info import params_to_render_connect
from janelia_emrp.msem.field_of_view_layout import FieldOfViewLayout, build_mfov_column_group, \
    NINETY_ONE_SFOV_ADJACENT_MFOV_DELTA_Y, NINETY_ONE_SFOV_NAME_TO_ROW_COL
from janelia_emrp.msem.ingestion_ibeammsem.assembly import get_xys_sfov_and_paths, get_max_scans
from janelia_emrp.msem.ingestion_ibeammsem.metrics import get_timestamp
from janelia_emrp.msem.scan_fit_parameters import ScanFitParameters, \
    build_fit_parameters_path, WAFER_60_61_SCAN_FIT_PARAMETERS
from janelia_emrp.msem.slab_info import load_slab_info, ContiguousOrderedSlabGroup
from janelia_emrp.root_logger import init_logger

program_name = "msem_to_render.py"

logger = logging.getLogger(__name__)


def build_tile_spec(image_path: Path,
                    stage_x: int,
                    stage_y: int,
                    stage_z: int,
                    tile_id: str,
                    tile_width: int,
                    tile_height: int,
                    layout: FieldOfViewLayout,
                    mfov_number: int,
                    sfov_index_name: str,
                    min_x: int,
                    min_y: int,
                    scan_fit_parameters: ScanFitParameters,
                    margin: int) -> dict[str, Any]:

    section_id = f'{stage_z}.0'
    image_row, image_col = layout.row_and_col(mfov_number, sfov_index_name)

    mipmap_level_zero = {"imageUrl": f'file:{image_path}'}

    transform_data_string = f'1 0 0 1 {stage_x - min_x + margin} {stage_y - min_y + margin}'

    tile_spec = {
        "tileId": tile_id, "z": stage_z,
        "layout": {
            "sectionId": section_id,
            "imageRow": image_row, "imageCol": image_col,
            "stageX": stage_x, "stageY": stage_y
        },
        "width": tile_width, "height": tile_height, "minIntensity": 0, "maxIntensity": 255,
        "mipmapLevels": {
            "0": mipmap_level_zero
        },
        "transforms": {
            "type": "list",
            "specList": [
                scan_fit_parameters.to_transform_spec(),
                {"className": "mpicbg.trakem2.transform.AffineModel2D", "dataString": transform_data_string}
            ]
        }
    }

    return tile_spec


# /nrs/hess/ibeammsem/system_02/wafers/wafer_60/acquisition/scans/scan_010/slabs/slab_0399/mfovs/mfov_0022/sfov_001.png
SFOV_PATTERN = re.compile(r".*/scan_(\d{3})/slabs/slab_(\d{4})/mfovs/mfov_(\d{4})/sfov_(\d{3}).png$")


def build_tile_specs_for_slab_scan(slab_scan_path: Path,
                                   sfov_path_list: list[Path],
                                   sfov_xy_list: list[tuple[int, int]],
                                   stage_z: int,
                                   layout: FieldOfViewLayout,
                                   wafer_short_prefix: str) -> list[dict[str, Any]]:

    scan_fit_parameters = WAFER_60_61_SCAN_FIT_PARAMETERS  # load_scan_fit_parameters(slab_scan_path)

    tile_data = []
    tile_width = None
    tile_height = None
    min_x = None
    min_y = None

    for i in range(0, len(sfov_path_list)):
        image_path = sfov_path_list[i]  # /nrs/.../scans/scan_010/slabs/slab_0399/mfovs/mfov_0022/sfov_001.png
        stage_x, stage_y = tuple(int(v) for v in sfov_xy_list[i])  # truncate float x and y values to int

        sfov_pattern_match = SFOV_PATTERN.match(image_path.as_posix())
        if not sfov_pattern_match:
            raise RuntimeError(f"failed to parse image_path {image_path}")

        p_scan_number = sfov_pattern_match.group(1)
        p_slab_number = sfov_pattern_match.group(2)
        p_mfov_number = sfov_pattern_match.group(3)
        p_sfov_number = sfov_pattern_match.group(4)

        # w060_magc0002_scan001_m0003_s004
        tile_id = f"{wafer_short_prefix}magc{p_slab_number}_scan{p_scan_number}_m{p_mfov_number}_s{p_sfov_number}"

        mfov_number = int(p_mfov_number)   # 0022 => 22

        if not tile_width:
            image = Image.open(image_path)
            tile_width = image.width
            tile_height = image.height
            min_x = stage_x
            min_y = stage_y
        else:
            min_x = min(min_x, stage_x)
            min_y = min(min_y, stage_y)

        tile_data.append(
            (tile_id, mfov_number, p_sfov_number, image_path, stage_x, stage_y))

    tile_specs = [
        build_tile_spec(image_path=image_path,
                        stage_x=stage_x,
                        stage_y=stage_y,
                        stage_z=stage_z,
                        tile_id=tile_id,
                        tile_width=tile_width,
                        tile_height=tile_height,
                        layout=layout,
                        mfov_number=mfov_number,
                        sfov_index_name=sfov_index_name,
                        min_x=min_x,
                        min_y=min_y,
                        scan_fit_parameters=scan_fit_parameters,
                        margin=400)
        for (tile_id, mfov_number, sfov_index_name, image_path, stage_x, stage_y) in sorted(tile_data)
    ]

    logger.info(f'build_tile_specs_for_slab_scan: loaded {len(tile_specs)} tile specs from {slab_scan_path}')

    return tile_specs


def get_stack_metadata_or_none(render: Render,
                               stack_name: str) -> Optional[dict[str, Any]]:
    stack_metadata = None
    try:
        stack_metadata = renderapi.stack.get_stack_metadata(render=render, stack=stack_name)
    except RenderError:
        print(f"failed to retrieve metadata for stack {stack_name}")
    return stack_metadata


def import_slab_stacks_for_wafer(render_ws_host: str,
                                 render_owner: str,
                                 wafer_xlog_path: Path,
                                 import_magc_slab_list: list[int],
                                 include_scan_list: list[int],
                                 exclude_scan_list: list[int],
                                 wafer_short_prefix: str,
                                 number_of_slabs_per_render_project: int):

    func_name = "import_slab_stacks_for_wafer"

    logger.info(f"{func_name}: opening {wafer_xlog_path}")

    if wafer_xlog_path.exists():
        xlog = xarray.open_zarr(wafer_xlog_path)
    else:
        raise RuntimeError(f"cannot find wafer xlog: {wafer_xlog_path}")

    logger.info(f"{func_name}: loading slab info, wafer_short_prefix='{wafer_short_prefix}', number_of_slabs_per_group={number_of_slabs_per_render_project}")
    
    n_scans_max = get_max_scans(xlog=xlog)
    logger.info(f"the maximum number of scans is {n_scans_max}")

    slab_group_list = load_slab_info(xlog=xlog,
                                     wafer_short_prefix=wafer_short_prefix,
                                     number_of_slabs_per_group=number_of_slabs_per_render_project)

    logger.info(f"{func_name}: loaded {len(slab_group_list)} slab groups")

    if len(import_magc_slab_list) > 0:
        logger.info(f"{func_name}: looking for magc slabs {import_magc_slab_list}")

        filtered_slab_group_list: list[ContiguousOrderedSlabGroup] = []
        for slab_group in slab_group_list:
            filtered_slab_group = ContiguousOrderedSlabGroup(ordered_slabs=[])
            for slab_info in slab_group.ordered_slabs:
                if slab_info.magc_id in import_magc_slab_list:
                    filtered_slab_group.ordered_slabs.append(slab_info)
            if len(filtered_slab_group.ordered_slabs) > 0:
                filtered_slab_group_list.append(filtered_slab_group)

        if len(filtered_slab_group_list) > 0:
            slab_group_list = filtered_slab_group_list
            logger.info(f"{func_name}: filtered down to {len(slab_group_list)} slab groups")
        else:
            raise RuntimeError(f"no slabs found with magc ids {import_magc_slab_list}")

    for slab_group in slab_group_list:
        project_name = slab_group.to_render_project_name(number_of_slabs_per_render_project)

        render_connect_params = {
            "host": render_ws_host,
            "port": 8080,
            "owner": render_owner,
            "project": project_name,
            "web_only": True,
            "validate_client": False,
            "client_scripts": "/groups/hess/hesslab/render/client_scripts",
            "memGB": "1G"
        }

        render = renderapi.connect(**render_connect_params)

        render_api = RenderApi(render_owner=render_connect_params["owner"],
                               render_project=render_connect_params["project"],
                               render_connect=params_to_render_connect(render_connect_params))

        for slab_info in slab_group.ordered_slabs:
            stack = slab_info.stack_name
            stack_is_in_loading_state = False
            z = 1
            scan_list = []

            logger.info(f'{func_name}: building layout for stack {stack}')

            mfov_position_list = slab_info.build_mfov_position_list(xlog=xlog)
            mfov_column_group = build_mfov_column_group(mfov_position_list,
                                                        NINETY_ONE_SFOV_ADJACENT_MFOV_DELTA_Y)
            stack_layout = FieldOfViewLayout(mfov_column_group, NINETY_ONE_SFOV_NAME_TO_ROW_COL)

            if len(include_scan_list) > 0:
                # build scan list by looking for first mfov timestamps for explicitly included scans
                for scan in include_scan_list:
                    first_mfov_scan_timestamp = get_timestamp(xlog=xlog, scan=scan, slab=slab_info.magc_id, mfov=slab_info.first_mfov)
                    if first_mfov_scan_timestamp is not None:
                        scan_list.append(scan)
                    else:
                        logger.warning(f'{func_name}: scan {scan} not found for stack {stack}')
            else:
                # build scan list by looking for first mfov timestamps for all scans and ignoring excluded scans
                for scan in range(0, n_scans_max):
                    first_mfov_scan_timestamp = get_timestamp(xlog=xlog, scan=scan, slab=slab_info.magc_id, mfov=slab_info.first_mfov)
                    if first_mfov_scan_timestamp is not None:
                        if scan not in exclude_scan_list:
                            scan_list.append(scan)
                    else:
                        break

            if len(scan_list) == 0:
                logger.warning(f'{func_name}: found no scans to import for stack {stack}')
                continue

            logger.info(f'{func_name}: found {len(scan_list)} scans to import for stack {stack}')

            for scan in scan_list:
                slab_scan_sfov_path_list: list[Path] = []
                slab_scan_sfov_xy_list: list[tuple[int, int]] = []
                for mfov in range(slab_info.first_mfov, slab_info.last_mfov + 1):
                    mfov_path_list, mfov_xys = get_xys_sfov_and_paths(xlog=xlog,
                                                                      scan=scan,
                                                                      slab=slab_info.magc_id,
                                                                      mfov=mfov)

                    # change //nearline-msem.int.janelia.org/hess/ibeammsem/system_02/wafers/wafer_60/acquisition/scans/scan_004/slabs/slab_0399
                    # to     /nrs/hess/ibeammsem/system_02/wafers/wafer_60/acquisition/scans/scan_004/slabs/slab_0399
                    slab_scan_sfov_path_list.extend(
                        [Path(str(mp).replace("//nearline-msem.int.janelia.org", "/nrs")) for mp in mfov_path_list]
                    )

                    slab_scan_sfov_xy_list.extend(mfov_xys)

                logger.info(f"{func_name}: loaded {len(slab_scan_sfov_path_list)} paths and xys for "
                            f"{stack} scan {scan}, mfovs {slab_info.first_mfov} to {slab_info.last_mfov}, "
                            f"first path is {slab_scan_sfov_path_list[0]}, first xy is {slab_scan_sfov_xy_list[0]}")

                first_sfov_path = slab_scan_sfov_path_list[0]
                if not first_sfov_path.exists():
                    logger.warning(f"{func_name}: skipping import of scan {scan} because {first_sfov_path} is missing")
                    continue

                # scan_sfov_path: /nrs/hess/ibeammsem/system_02/wafers/wafer_60/acquisition/scans/scan_010/slabs/slab_0399/mfovs/mfov_0022/sfov_001.png
                # slab_scan_path: /nrs/hess/ibeammsem/system_02/wafers/wafer_60/acquisition/scans/scan_010
                slab_scan_path = slab_scan_sfov_path_list[0].parent.parent.parent.parent.parent

                fit_parameters_path = build_fit_parameters_path(slab_scan_path)
                if not fit_parameters_path.exists():
                    logger.warning(f"{func_name}: skipping import of scan {scan} because {fit_parameters_path} is missing")
                    continue

                tile_specs = build_tile_specs_for_slab_scan(slab_scan_path=slab_scan_path,
                                                            sfov_path_list=slab_scan_sfov_path_list,
                                                            sfov_xy_list=slab_scan_sfov_xy_list,
                                                            stage_z=z,
                                                            layout=stack_layout,
                                                            wafer_short_prefix=wafer_short_prefix)

                if len(tile_specs) > 0:

                    if not stack_is_in_loading_state:
                        # TODO: parse resolution from wafer xlog
                        ensure_stack_is_in_loading_state(render=render,
                                                         stack=stack,
                                                         resolution_x=8.0,
                                                         resolution_y=8.0,
                                                         resolution_z=8.0)
                        stack_is_in_loading_state = True

                    tile_id_range = f'{tile_specs[0]["tileId"]} to {tile_specs[-1]["tileId"]}'
                    logger.info(f"{func_name}: saving tiles {tile_id_range} in stack {stack}")
                    render_api.save_tile_specs(stack=stack,
                                               tile_specs=tile_specs,
                                               derive_data=True)
                    z += 1
                else:
                    logger.debug(f'{func_name}: no tile specs in {slab_scan_path.name} for stack {stack}')

            if stack_is_in_loading_state:
                renderapi.stack.set_stack_state(stack, 'COMPLETE', render=render)


def ensure_stack_is_in_loading_state(render: Render,
                                     stack: str,
                                     resolution_x: float,
                                     resolution_y: float,
                                     resolution_z: float) -> None:

    stack_metadata = get_stack_metadata_or_none(render=render, stack_name=stack)
    if stack_metadata is None:
        # TODO: remove render-python hack
        # explicitly set createTimestamp until render-python bug is fixed
        # see https://github.com/AllenInstitute/render-python/pull/158
        create_timestamp = time.strftime('%Y-%m-%dT%H:%M:%S.00Z')
        renderapi.stack.create_stack(stack,
                                     render=render,
                                     createTimestamp=create_timestamp,
                                     stackResolutionX=resolution_x,
                                     stackResolutionY=resolution_y,
                                     stackResolutionZ=resolution_z)
    else:
        renderapi.stack.set_stack_state(stack, 'LOADING', render=render)


def main(arg_list: List[str]):
    parser = argparse.ArgumentParser(
        description="Parse wafer metadata and convert to tile specs that can be saved to render."
    )
    parser.add_argument(
        "--render_host",
        help="Render web services host (e.g. em-services-1.int.janelia.org)",
        required=True,
    )
    parser.add_argument(
        "--render_owner",
        help="Owner for all created render stacks",
        required=True,
    )
    parser.add_argument(
        "--path_xlog",
        help="Path of the wafer xarray (e.g. /groups/hess/hesslab/ibeammsem/system_02/wafers/wafer_60/xlog/xlog_wafer_60.zarr)",
        required=True,
    )
    parser.add_argument(
        "--import_magc_slab",
        help="If specified, only import tile specs for slabs with these magc ids (e.g. 399)",
        type=int,
        nargs='+',
        default=[]
    )
    parser.add_argument(
        "--include_scan",
        help="Only include these scans from the render stacks (e.g. 5 6 for testing).  When specified, exclude_scan is ignored.",
        type=int,
        nargs='+',
        default=[]
    )
    # NOTE: to exclude entire slabs, we decided to simply delete the stack after import
    parser.add_argument(
        "--exclude_scan",
        help="Exclude these scans from the render stacks (e.g. 0 1 2 3 7 18)",
        type=int,
        nargs='+',
        default=[]
    )
    parser.add_argument(
        "--wafer_short_prefix",
        help="Short prefix for wafer that gets prepended to all project and stack names (e.g. 'w60_')",
        type=str,
        default=""
    )
    parser.add_argument(
        "--number_of_slabs_per_render_project",
        help="Number of slabs to group together into one render project",
        type=int,
        default=10
    )
    args = parser.parse_args(args=arg_list)

    import_slab_stacks_for_wafer(render_ws_host=args.render_host,
                                 render_owner=args.render_owner,
                                 wafer_xlog_path=Path(args.path_xlog),
                                 import_magc_slab_list=args.import_magc_slab,
                                 include_scan_list=args.include_scan,
                                 exclude_scan_list=args.exclude_scan,
                                 wafer_short_prefix=args.wafer_short_prefix,
                                 number_of_slabs_per_render_project=args.number_of_slabs_per_render_project)


if __name__ == '__main__':
    # NOTE: to fix module not found errors, export PYTHONPATH="/.../EM_recon_pipeline/src/python"

    # setup logger since this module is the main program (and set render python logging level to DEBUG)
    init_logger(__file__)
    logging.getLogger("renderapi").setLevel(logging.DEBUG)

    # to see more log data, set root level to debug
    # logging.getLogger().setLevel(logging.DEBUG)

    # noinspection PyBroadException
    try:
        main(sys.argv[1:])
        # main([
        #     "--render_host", "10.40.3.113",
        #     "--render_owner", "trautmane",
        #     "--wafer_short_prefix", "w60_",
        #     "--path_xlog", "/groups/hess/hesslab/ibeammsem/system_02/wafers/wafer_60/xlog/xlog_wafer_60.zarr",
        #     "--import_magc_slab",
        #     "399", # s296
        #     "174", # s297
        #
        #     # "--include_scan", "6",
        #     "--exclude_scan", "0", "1", "2", "3", "7", "18"
        # ])
    except Exception as e:
        # ensure exit code is a non-zero value when Exception occurs
        traceback.print_exc()
        sys.exit(1)
