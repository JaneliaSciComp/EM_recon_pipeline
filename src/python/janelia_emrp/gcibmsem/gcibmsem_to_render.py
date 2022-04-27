import argparse
import csv
import logging
import re
import sys
import time
from pathlib import Path
from typing import List, Any

import renderapi
from PIL import Image

from janelia_emrp.fibsem.render_api import RenderApi
from janelia_emrp.fibsem.volume_transfer_info import params_to_render_connect
from janelia_emrp.gcibmsem.scan_fit_parameters import load_scan_fit_parameters, ScanFitParameters
from janelia_emrp.gcibmsem.slab_info import SlabInfo
from janelia_emrp.gcibmsem.wafer_info import load_wafer_info, WaferInfo, slab_stack_name

program_name = "gcibmsem_to_render.py"

# set up logging
logger = logging.getLogger(program_name)
c_handler = logging.StreamHandler(sys.stdout)
c_formatter = logging.Formatter("%(asctime)s [%(threadName)s] [%(name)s] [%(levelname)s] %(message)s")
c_handler.setFormatter(c_formatter)
logger.addHandler(c_handler)
logger.setLevel(logging.INFO)

render_api_logger = logging.getLogger("renderapi")
render_api_logger.setLevel(logging.DEBUG)
render_api_logger.addHandler(c_handler)


#     column:  0   1   2   3   4   5   6   7   8   9  10  11  12  13  14  15  16  17  18  19  20
# row:
#   0                            072 --- 071 --- 070 --- 069 --- 068 --- 067
#   1                        073 --- 046 --- 045 --- 044 --- 043 --- 042 --- 066
#   2                    074 --- 047 --- 026 --- 025 --- 024 --- 023 --- 041 --- 065
#   3                075 --- 048 --- 027 --- 012 --- 011 --- 010 --- 022 --- 040 --- 064
#   4            076 --- 049 --- 028 --- 013 --- 004 --- 003 --- 009 --- 021 --- 039 --- 063
#   5        077 --- 050 --- 029 --- 014 --- 005 --- 001 --- 002 --- 008 --- 020 --- 038 --- 062
#   6            078 --- 051 --- 030 --- 015 --- 006 --- 007 --- 019 --- 037 --- 061 --- 091
#   7                079 --- 052 --- 031 --- 016 --- 017 --- 018 --- 036 --- 060 --- 090
#   8                    080 --- 053 --- 032 --- 033 --- 034 --- 035 --- 059 --- 089
#   9                        081 --- 054 --- 055 --- 056 --- 057 --- 058 --- 088
#  10                            082 --- 083 --- 084 --- 085 --- 086 --- 087
single_field_of_view_index_string_to_row_and_column = {
    "072": (0, 5), "071": (0, 7), "070": (0, 9), "069": (0, 11), "068": (0, 13), "067": (0, 15),
    "073": (1, 4), "046": (1, 6), "045": (1, 8), "044": (1, 10), "043": (1, 12), "042": (1, 14), "066": (1, 16),
    "074": (2, 3), "047": (2, 5), "026": (2, 7), "025": (2, 9),
    "024": (2, 11), "023": (2, 13), "041": (2, 15), "065": (2, 17),
    "075": (3, 2), "048": (3, 4), "027": (3, 6), "012": (3, 8), "011": (3, 10),
    "010": (3, 12), "022": (3, 14), "040": (3, 16), "064": (3, 18),
    "076": (4, 1), "049": (4, 3), "028": (4, 5), "013": (4, 7), "004": (4, 9),
    "003": (4, 11), "009": (4, 13), "021": (4, 15), "039": (4, 17), "063": (4, 19),
    "077": (5, 0), "050": (5, 2), "029": (5, 4), "014": (5, 6), "005": (5, 8), "001": (5, 10),
    "002": (5, 12), "008": (5, 14), "020": (5, 16), "038": (5, 18), "062": (5, 20),
    "078": (6, 1), "051": (6, 3), "030": (6, 5), "015": (6, 7), "006": (6, 9),
    "007": (6, 11), "019": (6, 13), "037": (6, 15), "061": (6, 17), "091": (6, 19),
    "079": (7, 2), "052": (7, 4), "031": (7, 6), "016": (7, 8), "017": (7, 10),
    "018": (7, 12), "036": (7, 14), "060": (7, 16), "090": (7, 18),
    "080": (8, 3), "053": (8, 5), "032": (8, 7), "033": (8, 9),
    "034": (8, 11), "035": (8, 13), "059": (8, 15), "089": (8, 17),
    "081": (9, 4), "054": (9, 6), "055": (9, 8), "056": (9, 10), "057": (9, 12), "058": (9, 14), "088": (9, 16),
    "082": (10, 5), "083": (10, 7), "084": (10, 9), "085": (10, 11), "086": (10, 13), "087": (10, 15)
}


def build_tile_spec(image_path: Path,
                    stage_x: int,
                    stage_y: int,
                    stage_z: int,
                    tile_id: str,
                    tile_width: int,
                    tile_height: int,
                    single_field_of_view_index_string: str,
                    min_x: int,
                    min_y: int,
                    scan_fit_parameters: ScanFitParameters,
                    margin: int) -> dict[str, Any]:

    # TODO: need to get and save working distance

    section_id = f'{stage_z}.0'
    image_row, image_col = single_field_of_view_index_string_to_row_and_column[single_field_of_view_index_string]

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


# unix_relative_image_path: 000003/002_000003_001_2022-04-01T1723012239596.png
unix_relative_image_path_pattern = re.compile(r"^\d+/(\d{3}_\d{6}_(\d{3})_\d{4}-\d{2}-\d{2}T\d{13}).png$")


def build_tile_specs_for_slab_scan(slab_scan_path: Path,
                                   slab_info: SlabInfo) -> list[dict[str, Any]]:

    scan_fit_parameters = load_scan_fit_parameters(slab_scan_path)
    stage_z = slab_info.first_scan_z + scan_fit_parameters.scan_index

    tile_data = []
    tile_width = None
    tile_height = None
    min_x = None
    min_y = None
    full_image_coordinates_path = Path(slab_scan_path, "full_image_coordinates.txt")

    if full_image_coordinates_path.exists():
        with open(full_image_coordinates_path, 'r') as data_file:
            # 000007\020_000007_082_2022-04-03T0154134018404.png	2014641.659	915550.903	0
            for row in csv.reader(data_file, delimiter="\t"):
                unix_relative_image_path = row[0].replace('\\', '/')
                stage_x = int(float(row[1]))
                stage_y = int(float(row[2]))
                image_path = Path(slab_scan_path, unix_relative_image_path)

                unix_relative_image_path_match = unix_relative_image_path_pattern.match(unix_relative_image_path)
                if not unix_relative_image_path_match:
                    raise RuntimeError(f"failed to parse unix_relative_image_path {unix_relative_image_path} "
                                       f"in {full_image_coordinates_path}")

                single_field_of_view_name = unix_relative_image_path_match.group(1)
                single_field_of_view_index_string = unix_relative_image_path_match.group(2)

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
                    (single_field_of_view_name, single_field_of_view_index_string, image_path, stage_x, stage_y))
    else:
        logger.warning(f'{full_image_coordinates_path} not found')

    tile_specs = [
        build_tile_spec(image_path=image_path,
                        stage_x=stage_x,
                        stage_y=stage_y,
                        stage_z=stage_z,
                        tile_id=f"{single_field_of_view_name}.{stage_z}.0",
                        tile_width=tile_width,
                        tile_height=tile_height,
                        single_field_of_view_index_string=single_field_of_view_index_string,
                        min_x=min_x,
                        min_y=min_y,
                        scan_fit_parameters=scan_fit_parameters,
                        margin=400)
        for (single_field_of_view_name, single_field_of_view_index_string, image_path, stage_x, stage_y) in tile_data
    ]

    logger.info(f'loaded {len(tile_specs)} tile specs from {slab_scan_path}')

    return tile_specs


def import_slab_stacks_for_wafer(render_owner: str,
                                 wafer_info: WaferInfo):
    render_connect_params = {
        "host": "tem-services.int.janelia.org",
        "port": 8080,
        "owner": render_owner,
        "project": wafer_info.name,
        "web_only": True,
        "validate_client": False,
        "client_scripts": "/groups/flyTEM/flyTEM/render/bin",
        "memGB": "1G"
    }

    render = renderapi.connect(**render_connect_params)

    render_api = RenderApi(render_owner=render_connect_params["owner"],
                           render_project=render_connect_params["project"],
                           render_connect=params_to_render_connect(render_connect_params))

    for slab_name in wafer_info.sorted_slab_names():
        stack = slab_stack_name(slab_name)

        # explicitly set createTimestamp until render-python bug is fixed
        # see https://github.com/AllenInstitute/render-python/pull/158
        create_timestamp = time.strftime('%Y-%m-%dT%H:%M:%S.00Z')
        renderapi.stack.create_stack(stack,
                                     render=render,
                                     createTimestamp=create_timestamp,
                                     stackResolutionX=wafer_info.resolution[0],
                                     stackResolutionY=wafer_info.resolution[1],
                                     stackResolutionZ=wafer_info.resolution[2])

        for scan_path in wafer_info.scan_paths:
            slab_info = wafer_info.slab_name_to_info[slab_name]
            slab_scan_path = Path(scan_path, slab_name)
            tile_specs = build_tile_specs_for_slab_scan(slab_scan_path, slab_info)
            if len(tile_specs) > 0:
                logger.info(f'import_tile_specs: {tile_specs[0]["tileId"]} to {tile_specs[-1]["tileId"]}')
                render_api.save_tile_specs(stack=stack,
                                           tile_specs=tile_specs,
                                           derive_data=True)

        renderapi.stack.set_stack_state(stack, 'COMPLETE', render=render)

        # TODO: remove break once we're happy with first slab results
        break


def main(arg_list: List[str]):
    parser = argparse.ArgumentParser(
        description="Parse wafer metadata and convert to tile specs that can be saved to render."
    )

    parser.add_argument(
        "--render_owner",
        help="Owner for all created render stacks",
        required=True,
    )

    parser.add_argument(
        "--wafer_base_path",
        help="Base path for wafer data (e.g. /nrs/hess/render/raw/wafer_52)",
        required=True,
    )

    args = parser.parse_args(args=arg_list)

    wafer_info = load_wafer_info(wafer_base_path=Path(args.wafer_base_path))

    import_slab_stacks_for_wafer(args.render_owner, wafer_info)


if __name__ == '__main__':
    main(sys.argv[1:])
