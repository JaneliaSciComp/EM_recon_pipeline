import csv
import glob
import logging
import os.path
import re
import sys
import time

import renderapi
from PIL import Image

# Plate_13_20210525_21-38-12\008_s_4\000007\008_000007_055_2021-05-25T2146499297643.bmp
# <plateId>_<scanTime>\<scanIndex>_s_<zNumber>\<mFOV>\<sectionAcquisitionIndex>_<mFOV>_<sFOV>_<sFOVTimestamp>.bmp
image_path_pattern = \
    re.compile(r".*Plate_(\d+_\d{8}_\d{2}-\d{2}-\d{2})[/\\]\d+_s_(\d+)[/\\]\d+[/\\]\d{3}_(\d{6})_(\d{3})_.*")

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


def build_tile_spec(image_path, stage_x, stage_y, tile_width, tile_height, min_x, min_y, margin):

    # TODO: need to get and save working distance (metadata.txt has same Stage pos. Z target for all sections)

    m = image_path_pattern.match(image_path)
    plate_id = m.group(1).replace('-', '')
    z = int(m.group(2))
    section_id = f'{z}.0'
    m_fov = m.group(3)
    s_fov = m.group(4)

    image_row = int(m_fov)
    image_col = int(s_fov)

    tile_id = f's{z}.m{m_fov}.t{s_fov}.p{plate_id}'

    mipmap_level_zero = {"imageUrl": f'file:{image_path}.png'}

    transform_data_string = f'1 0 0 1 {stage_x - min_x + margin} {stage_y - min_y + margin}'

    tile_spec = {
        "tileId": tile_id, "z": z,
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
            "specList": [{"type": "leaf",
                          "className": "mpicbg.trakem2.transform.AffineModel2D",
                          "dataString": transform_data_string}]
        }
    }

    return renderapi.tilespec.TileSpec(json=tile_spec)


def build_section_tile_specs(section_path):

    tile_data = []
    tile_width = None
    tile_height = None
    min_x = None
    min_y = None
    full_image_coordinates_path = f'{section_path}/full_image_coordinates.txt'
    with open(full_image_coordinates_path, 'r') as data_file:
        # 000007\008_000007_055_2021-05-25T2146499297643.bmp      -372876.505     -123997.579     0
        for row in csv.reader(data_file, delimiter="\t"):
            unix_relative_path = row[0].replace('\\','/')
            stage_x = int(float(row[1]))
            stage_y = int(float(row[2]))
            image_path = f'{section_path}/{unix_relative_path}'
            if not tile_width:
                image = Image.open(image_path)
                tile_width = image.width
                tile_height = image.height
                min_x = stage_x
                min_y = stage_y
            else:
                min_x = min(min_x, stage_x)
                min_y = min(min_y, stage_y)
            tile_data.append((image_path, stage_x, stage_y))

    tile_specs = [
        build_tile_spec(image_path, stage_x, stage_y, tile_width, tile_height, min_x, min_y, 400)
        for (image_path, stage_x, stage_y) in tile_data
    ]

    logger.info(f'loaded {len(tile_specs)} tile specs from {section_path}')

    return tile_specs


def import_stack(owner, project, stack, stack_path):

    render_connect_params = {
        "host": "tem-services.int.janelia.org",
        "port": 8080,
        "owner": owner,
        "project": project,
        "web_only": True,
        "validate_client": False,
        "client_scripts": "/groups/flyTEM/flyTEM/render/bin",
        "memGB": "1G"
    }

    render = renderapi.connect(**render_connect_params)

    # TODO: get resolution data for stack (section metadata.txt has Pixelsize)
    resolution_xy = 8
    resolution_z = 8

    # explicitly set createTimestamp until render-python bug is fixed
    # see https://github.com/AllenInstitute/render-python/pull/158
    create_timestamp = time.strftime('%Y-%m-%dT%H:%M:%S.00Z')
    renderapi.stack.create_stack(stack,
                                 render=render,
                                 createTimestamp=create_timestamp,
                                 stackResolutionX=resolution_xy,
                                 stackResolutionY=resolution_xy,
                                 stackResolutionZ=resolution_z)

    for section_path in glob.glob(f'{stack_path}/???_s_*'):
        if os.path.isdir(section_path):
            tile_specs = build_section_tile_specs(section_path)
            if len(tile_specs) > 0:
                logger.info(f'import_tile_specs: {tile_specs[0].tileId} to {tile_specs[-1].tileId}')
            renderapi.client.import_tilespecs(stack, tile_specs, render=render, use_rest=True)

    renderapi.stack.set_stack_state(stack, 'COMPLETE', render=render)


if __name__ == '__main__':
    import_stack(owner='hess',
                 project='plate_13_20210525_213812',
                 stack='v1_acquire',
                 stack_path='/groups/hess/hesslab/render/GCIBMSEM/data/Plate_13_20210525_21-38-12')