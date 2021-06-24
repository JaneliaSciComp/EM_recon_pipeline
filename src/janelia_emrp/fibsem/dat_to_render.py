import argparse
import copy
import dask.bag as db
import datetime
import json
import logging
import math
import os
import re
import renderapi
import subprocess
import sys
import time
import traceback

from dask_janelia import get_cluster
from glob import glob
from fibsem_tools.io import read

program_name = "dat_to_render.py"

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

# Merlin-6049_15-06-16_000059_0-0-0-InLens.png
base_name_pattern = re.compile(r".*((\d\d-\d\d-\d\d_\d{6})_\d-(\d)-(\d)).*")
common_tile_header_keys = [
    "XResolution", "YResolution", "PixelSize", "EightBit", "ChanNum", "SWdate",
    "StageX", "StageY", "StageZ", "StageR"
]
unique_tile_header_keys = ["WD", "Restart", "StageMove", "FirstX", "FirstY"]
retained_tile_header_keys = common_tile_header_keys + unique_tile_header_keys
checked_tile_header_keys = common_tile_header_keys + ["SampleID"]


def read_next_header_batch(dat_file_names, current_index, split_layer_groups):

    last_header_index = len(dat_file_names)

    if split_layer_groups:
        headers = []
        header_index = 0
        for layer_group in split_layer_groups:
            for layer in layer_group["layers"]:
                for dat in layer.keys():
                    if header_index >= current_index:
                        header = copy.deepcopy(layer_group["firstTileHeader"])
                        for key in unique_tile_header_keys:
                            if key in layer[dat]:
                                header[key] = layer[dat][key]
                        headers.append(header)
                    header_index += 1

    else:
        max_records_to_read = 100
        if last_header_index - current_index > max_records_to_read:
            last_header_index = current_index + max_records_to_read

        logger.info(f'read_next_header_batch: loading tiles {current_index + 1} to {last_header_index} '
                    f'of {len(dat_file_names)}')
        
        # records = read(dat_file_names[current_index:last_header_index], lazy=False)
        records = read(dat_file_names[current_index:last_header_index])
        headers = []
        for i in range(0, len(records)):
            record = records[i]
            header = {}
            for key in retained_tile_header_keys:
                if key in record.header.__dict__:
                    header[key] = record.header.__dict__[key]

            # "Z1217-33m_BR_Sec10, BF 316x100um, 24s @11.5nA /8nm @15nA-1, lens2 14110-40V..., bias 0V, deflector +100V"
            if "SampleID" in record.header.__dict__:
                header["SampleID"] = record.header.__dict__["SampleID"]
            else:
                notes = record.header.__dict__["Notes"]
                header["SampleID"] = notes[0:notes.find(",")]

            if header["PixelSize"] == 0:
                raise RuntimeError(
                    f"Header PixelSize is zero for {dat_file_names[current_index + i]}"
                )

            headers.append(header)

    return current_index, last_header_index, headers


def get_base_id_and_time(path):

    m = base_name_pattern.match(path)
    if not m:
        raise ValueError(f"Invalid .dat file name: {path}")

    return m.group(1), datetime.datetime.strptime(m.group(2), "%y-%m-%d_%H%M%S")


def validate_header_consistency(group_header, previous_base_id, header, base_id):

    for k in common_tile_header_keys:
        if header[k] != group_header[k]:

            # From Shan:
            #   Small PixelSize deltas are "due to the step change of the microscope magnification as
            #   the working distance (WD) increases (material being milled away). Different tiles change at
            #   different frames because they have different WD values. The magnification might have a small
            #   step jump when this happens which I think will be taken care of by SIFT."
            if k == "PixelSize":
                delta = abs(float(header[k]) - float(group_header[k]))
                if delta < 0.5:
                    continue

            return f'change_header_{k.lower()}: ' \
                   f'{k} value of {group_header[k]} for {previous_base_id} ' \
                   f'changed to {header[k]} for {base_id}'
    return None


def get_layer_group(dat_file_names, dat_start_index, split_layer_groups):

    # flag restart if more than 15 minutes elapses between layer acquisitions
    restart_seconds_threshold = 15 * 60 

    total_tile_count = len(dat_file_names)
    first_header_index, last_header_index, headers = read_next_header_batch(dat_file_names,
                                                                            dat_start_index,
                                                                            split_layer_groups)

    first_tile_header = headers[0]
    dat_file_name = dat_file_names[dat_start_index]
    base_id, acquire_time = get_base_id_and_time(dat_file_name)
    first_base_id = base_id
    unique_header_data_for_tile = {
        "WD": first_tile_header["WD"],
        "FirstX": first_tile_header.get("FirstX", None),
        "FirstY": first_tile_header.get("FirstY", None)
    }
    layer = {dat_file_name: unique_header_data_for_tile}
    layers = []

    restart_condition = None
    tiles_per_layer = None
    previous_base_id = base_id
    previous_acquire_time = acquire_time

    tile_number = dat_start_index + 1
    logger.info(f'get_layer_group: starting with tile {previous_base_id} ({tile_number} of {total_tile_count})')

    for i in range(dat_start_index + 1, total_tile_count):

        if i >= last_header_index:
            first_header_index, last_header_index, headers = read_next_header_batch(dat_file_names,
                                                                                    i,
                                                                                    split_layer_groups)

        header = headers[i - first_header_index]
        dat_file_name = dat_file_names[i]
        base_id, acquire_time = get_base_id_and_time(dat_file_name)
        unique_header_data_for_tile = {
            "WD": header["WD"],
            "FirstX": header.get("FirstX", None),
            "FirstY": header.get("FirstY", None)
        }

        time_delta = acquire_time - previous_acquire_time

        if time_delta.seconds > restart_seconds_threshold:
            restart_condition = \
                f'acquisition_delay: tile {base_id} acquired {time_delta.seconds} seconds after tile {previous_base_id}'
        else:
            restart_condition = validate_header_consistency(first_tile_header, previous_base_id, header, base_id)

        add_layer_to_group = False

        if restart_condition:
            add_layer_to_group = (not tiles_per_layer) or (tiles_per_layer == len(layer.keys()))
            if not add_layer_to_group:
                restart_condition = \
                    f'{restart_condition}, not adding {len(layer.keys())} tile layer with ' \
                    f'tile {previous_base_id} to {tiles_per_layer} tile layer group'
        else:
            if time_delta.seconds == 0:
                # logger.info(f'add {base_id} to layer')
                layer[dat_file_name] = unique_header_data_for_tile

                is_last_record = i == (total_tile_count - 1)
                if is_last_record:
                    add_layer_to_group = True
            else:
                add_layer_to_group = True  # new time stamp == new layer

        if add_layer_to_group:
            
            inconsistent_tile_count = tiles_per_layer and tiles_per_layer != len(layer.keys())
            if inconsistent_tile_count:
                restart_condition = "change_tile_count: " \
                    f'layer with tile {base_id} has {len(layer.keys())} instead of {tiles_per_layer} tiles'
            else:
                tiles_per_layer = len(layer.keys())
                layers.append(layer)
                # logger.info(f'add {tiles_per_layer} tile layer to group')
                layer = {dat_file_name: unique_header_data_for_tile}

        if restart_condition:
            logger.info(f'found restart condition: {restart_condition}')
            break

        previous_base_id = base_id
        previous_acquire_time = acquire_time

    # ensure tiles_per_layer is defined
    if len(layers) == 0:
        layers.append(layer)
        tiles_per_layer = len(layer)

    tiles_in_group = len(layers) * tiles_per_layer
    last_dat_in_group = sorted(layers[-1].keys())[-1]
    last_base_id, last_acquire_time = get_base_id_and_time(last_dat_in_group)
    logger.info(f'get_layer_group: returning group with {tiles_in_group} tiles '
                f'across {len(layers)} layers from {first_base_id} to {last_base_id}')

    # TODO: from code review: consider use of data class (3.7)
    return {
        "firstTileHeader": first_tile_header,
        "firstTilePath": dat_file_names[dat_start_index],
        "restartCondition": restart_condition,
        "tilesPerLayer": tiles_per_layer,
        "tilesInGroup": tiles_in_group,
        "layers": layers
    }


def build_layer_groups(dat_file_names, split_layer_groups=None):
    
    logger.info(f"build_layer_groups: entry, processing {len(dat_file_names)} tiles starting with {dat_file_names[0]}")

    layer_groups = []
    dat_start_index = 0
    while dat_start_index < len(dat_file_names):
        layer_group = get_layer_group(dat_file_names, dat_start_index, split_layer_groups)
        layer_groups.append(layer_group)
        dat_start_index += layer_group["tilesInGroup"]

    return layer_groups


def save_layer_groups(layer_groups, to_dir):

    for layer_group in layer_groups:
        dat_core_name = os.path.basename(layer_group["firstTilePath"])[:-4]
        layer_group_file_name = f'{to_dir}/{dat_core_name}.layer_group.json'
        with open(layer_group_file_name, 'w') as json_file:
            json.dump(layer_group, json_file, default=str, indent=2)
            logger.info(f'save_layer_groups: wrote {layer_group_file_name}')


def load_dat_file_names(path_list, start_index, stop_index):

    logger.info(f"load_dat_file_names: loading file names from {path_list} ...")

    dat_file_names = []
    for path in path_list:

        if os.path.isdir(path):
            glob_path_suffix = "*.dat" if path.endswith("/") else "/*.dat"
            dat_file_names.extend(glob(path + glob_path_suffix))
        else:
            dat_file_names.extend(glob(path))

    if len(dat_file_names) == 0:
        raise ValueError(f"No .dat files found in {path_list}")
    else:
        dat_file_names = sorted(dat_file_names)
        total_number_of_file_names = len(dat_file_names)
        defined_stop_index = stop_index if stop_index else total_number_of_file_names
        if start_index > 0 or defined_stop_index < total_number_of_file_names:
            dat_file_names = dat_file_names[start_index:defined_stop_index]
            count_msg = f"{len(dat_file_names)} out of {total_number_of_file_names}"
        else:
            count_msg = f"{total_number_of_file_names}"

    logger.info(f"load_dat_file_names: loaded {count_msg} file names")

    return dat_file_names


def load_split_layer_group_data(path):

    json_file_names = []
    if os.path.isdir(path):
        json_file_names = sorted(glob(path + '*.layer_group.json'))

    if len(json_file_names) == 0:
        raise ValueError(f"No .layer_group.json files found in {path}")

    dat_file_names = []
    layer_groups = []
    for json_file_name in json_file_names:
        with open(json_file_name, 'r') as json_file:
            layer_group = json.load(json_file)
            for layer in layer_group["layers"]:
                dat_file_names.extend(layer.keys())
            layer_groups.append(layer_group)

    return dat_file_names, layer_groups


def create_mask_if_missing(image_width, image_height, mask_width, mask_dir, mask_errors):

    mask_path = f'{mask_dir}/mask_{image_width}x{image_height}_left_{mask_width}.tif'

    if mask_path not in mask_errors.keys() and not os.path.exists(mask_path):
        # noinspection PyBroadException
        try:
            argv = [
                '/groups/flyem/data/render/bin/create_mask.sh',
                str(image_width),
                str(image_height),
                str(mask_width),
                mask_dir
            ]
            create_output = subprocess.check_output(argv, stderr=subprocess.STDOUT)
            logger.info(create_output)

        except Exception:
            exc_type, exc_value, exc_traceback = sys.exc_info()
            mask_errors[mask_path] = traceback.format_exception(exc_type, exc_value, exc_traceback)

    return mask_path


def build_tile_spec(dat_file_name, z, tile_width, tile_height, overlap_pixels, tile_attributes, image_dir, mask_path):

    m = base_name_pattern.match(dat_file_name)
    base_id = m.group(1)
    image_row = int(m.group(3))
    image_col = int(m.group(4))

    section_id = str(z) + ".0"
    tile_id = f'{base_id}.{section_id}'

    margin = 400  # offset everything a little to help viewers that have trouble with negative space
    default_stage_x = margin + round(image_col * (tile_width - overlap_pixels))
    default_stage_y = margin + round(image_row * (tile_height - overlap_pixels))

    working_distance = tile_attributes["WD"]
    stage_x = tile_attributes.get("FirstX") or default_stage_x
    stage_y = tile_attributes.get("FirstY") or default_stage_y

    image_path = f'{image_dir}/{os.path.basename(dat_file_name)[:-4]}-InLens.png'
    mipmap_level_zero = {"imageUrl": f'file:{image_path}'}
    if mask_path:
        mipmap_level_zero["maskUrl"] = f'file:{mask_path}'

    transform_data_string = f'1 0 0 1 {stage_x} {stage_y}'

    # TODO: handle 16-bit data (override min and max intensity values)
    # TODO: from code review: parameterize intensity
    tile_spec = {
        "tileId": tile_id, "z": z,
        "minX": stage_x, "minY": stage_y, "maxX": stage_x + tile_width, "maxY": stage_y + tile_height,
        "layout": {
            "sectionId": section_id,
            "imageRow": image_row, "imageCol": image_col,
            "stageX": stage_x, "stageY": stage_y, "workingDistance": working_distance
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

    # TODO: from code review: look at render-python class (or consider attrs.py model)
    # return renderapi.tilespec.TileSpec(json=tile_spec)
    return tile_spec


def set_distance_z(all_tile_specs):
    z_resolution = None
    if len(all_tile_specs) > 1:

        distance_z_sum = 0

        # TODO: determine if more robust prior layer comparisons are needed (e.g. after restarts)
        previous_column_to_working_distance = {}
        for i in range(0, len(all_tile_specs)):
            tile_spec_layout = all_tile_specs[i]["layout"]
            image_col = tile_spec_layout["imageCol"]
            working_distance = tile_spec_layout["workingDistance"]
            if image_col in previous_column_to_working_distance:
                distance_z = (working_distance - previous_column_to_working_distance[image_col]) * 1000000
                tile_spec_layout["distanceZ"] = distance_z
                distance_z_sum += distance_z

            previous_column_to_working_distance[image_col] = working_distance

        z_resolution = math.floor((distance_z_sum / len(all_tile_specs)) + 0.5)

    return z_resolution


def build_tile_specs_for_group(layer_group, group_start_z, image_dir, mask_path, tile_overlap_in_microns):

    tile_specs = []
    z = group_start_z
    for layer in layer_group["layers"]:

        header = layer_group["firstTileHeader"]
        tile_width = header["XResolution"]
        tile_height = header["YResolution"]
        nm_per_pixel = header["PixelSize"]

        overlap_nm = tile_overlap_in_microns * 1000
        overlap_pixels = overlap_nm / nm_per_pixel

        for dat_file_name in sorted(layer.keys()):
            tile_attributes = layer[dat_file_name]
            tile_specs.append(
                build_tile_spec(dat_file_name, z, tile_width, tile_height, overlap_pixels, tile_attributes,
                                image_dir, mask_path))

        z += 1

    return tile_specs


def split_list_for_workers(full_list, num_workers):
    items_per_worker = math.ceil(len(full_list) / num_workers)
    return [full_list[i:i + items_per_worker] for i in range(0, len(full_list), items_per_worker)]


def flatten_list_of_lists(list_of_lists):
    return [item for sublist in list_of_lists for item in sublist]


def import_tile_specs(tile_specs, stack, render):
    if len(tile_specs) > 0:
        logger.info(f'import_tile_specs: {tile_specs[0].tileId} to {tile_specs[-1].tileId}')
        renderapi.client.import_tilespecs(stack, tile_specs, render=render, use_rest=True)


def patch_layer(previous_layer_specs, spec_from_layer_being_patched):
    patch_section_id = spec_from_layer_being_patched["layout"]["sectionId"]

    patched_tile_specs = []
    for tile_spec in previous_layer_specs:
        patched_tile_spec = copy.deepcopy(tile_spec)
        patched_tile_spec["z"] = spec_from_layer_being_patched["z"]
        previous_tile_id = tile_spec["tileId"]
        base_tile_id = previous_tile_id[0:previous_tile_id.find('.')]  # tileId: 19-07-20_112626_0-0-2.9359.0
        patched_tile_spec["tileId"] = f'{base_tile_id}.patch.{patch_section_id}'
        patched_tile_spec["layout"]["sectionId"] = patch_section_id
        patched_tile_spec["labels"] = spec_from_layer_being_patched["labels"]
        patched_tile_specs.append(patched_tile_spec)

    return patched_tile_specs


def save_stack(stack_name, render, resolution_xy, resolution_z, tile_specs, num_workers):
    renderapi.stack.create_stack(stack_name,
                                 render=render,
                                 stackResolutionX=resolution_xy,
                                 stackResolutionY=resolution_xy,
                                 stackResolutionZ=resolution_z)

    api_tile_specs = [renderapi.tilespec.TileSpec(json=tile_spec) for tile_spec in tile_specs]

    if num_workers > 1:
        split_tile_specs = split_list_for_workers(api_tile_specs, num_workers)
        bag = db.from_sequence(split_tile_specs, npartitions=num_workers).map(import_tile_specs, stack_name, render)
        bag.compute()
    else:
        import_tile_specs(api_tile_specs, stack_name, render)

    renderapi.stack.set_stack_state(stack_name, 'COMPLETE', render=render)


def main(arg_list):

    start_time = time.time()
    parser = argparse.ArgumentParser(
        description="Parse dat metadata and convert to tile specs that can be saved to render."
    )
    parser.add_argument(
        "--source",
        help="Files to process.  Must be either a single directory (e.g., `/data` or a wild-card expansion of "
             "within a single directory (e.g., `/data/Merlin*_[2-3]*.dat`).  Files will be sorted by filename.",
        required=True,
        nargs="+"
    )
    parser.add_argument(
        "--source_start_index",
        help="Specify start index for first (sorted) dat file to process",
        type=int,
        default=0
    )
    parser.add_argument(
        "--source_stop_index",
        help="Specify stop index for first (sorted) dat file to exclude from processing "
             "(omit to include all dat files after the start index)",
        type=int
    )
    parser.add_argument(
        "--stack_name",
        help="Name for generated render stack",
        default="v1_acquire"
    )
    parser.add_argument(
        "--debug_parent_dir",
        help="Parent directory for run specific directory where intermediate debug data "
             "(like tile specs) should be stored (if omitted, intermediate data is not saved)",
    )
    parser.add_argument(
        "--dask_worker_space",
        help="Directory for Dask worker data",
    )
    parser.add_argument(
        "--num_workers",
        help="The number of workers to use for distributed processing",
        type=int,
        default=1
    )
    parser.add_argument(
        "--bill_project",
        help="The project to bill cluster time to (uses your default project if not specified)"
    )
    parser.add_argument(
        "--image_dir",
        help="Directory containing source png image files (converted from dat)",
        required=True
    )
    parser.add_argument(
        "--mask_dir",
        help="Directory containing mask files (omit if masks are not desired)"
    )
    parser.add_argument(
        "--mask_width",
        help="Left pixel width of masked area",
        type=int,
        default=100
    )
    parser.add_argument(
        "--tile_overlap_in_microns",
        help="Overlap (in microns) between tiles in same layer (not currently recorded in dat header)",
        type=int,
        default=2
    )
    parser.add_argument(
        "--render_connect_json",
        help="JSON file containing render web service connection parameters",
        required=True
    )
    parser.add_argument(
        "--restart_context_layers",
        help="Number of layers to include in the restart stack before and after each restart",
        type=int,
        default=1
    )

    args = parser.parse_args(args=arg_list)

    if os.path.isfile(args.render_connect_json):
        with open(args.render_connect_json, 'r') as json_file:
            render_connect_params = json.load(json_file)
    else:
        raise ValueError(f"invalid render_connect_json file {args.render_connect_json}")

    # render_connect_params = {
    #     "host": "tem-services.int.janelia.org",
    #     "port": 8080,
    #     "owner": "trautmane",
    #     "project": "test_dat",
    #     "web_only": True,
    #     "validate_client": False,
    #     "client_scripts": "/groups/flyTEM/flyTEM/render/bin",
    #     "memGB": "1G"
    # }

    render = renderapi.connect(**render_connect_params)

    formatted_run_time = datetime.datetime.now().strftime("%y%m%d_%H%M%S")

    debug_dir = None
    if args.debug_parent_dir:
        debug_dir = f'{args.debug_parent_dir}/run_{formatted_run_time}'
        os.mkdir(debug_dir)

    # dat_file_names, split_layer_groups = load_split_layer_group_data(args.source)

    dat_file_names = load_dat_file_names(args.source, args.source_start_index, args.source_stop_index)

    if args.num_workers > 1:
        dask_cluster = get_cluster(threads_per_worker=1,
                                   local_kwargs={
                                       "local_directory": args.dask_worker_space                                       
                                   },
                                   lsf_kwargs={
                                       "local_directory": args.dask_worker_space,
                                       "project": args.bill_project
                                   })

        logger.info(f'observe dask cluster information at {dask_cluster.dashboard_link}')

        dask_cluster.scale(args.num_workers)
        logger.info(f'scaled dask cluster to {args.num_workers} workers')

        split_dat_file_names = split_list_for_workers(dat_file_names, args.num_workers)
        bag = db.from_sequence(split_dat_file_names, npartitions=args.num_workers).map(build_layer_groups)
        split_layer_groups = flatten_list_of_lists(bag.compute())

        first_tab_id = None
        for group in split_layer_groups:
            first_tile_header = group["firstTileHeader"]
            tab_id = first_tile_header["SampleID"]
            if first_tab_id:
                assert (tab_id == first_tab_id), \
                    f'{group["firstTilePath"]} tab ID is {tab_id} but should be {first_tab_id}'
            else:
                first_tab_id = tab_id

        logger.info(f'merging {len(split_layer_groups)} split layer groups from workers for tab {first_tab_id}')
        layer_groups = build_layer_groups(dat_file_names, split_layer_groups)

    else:
        layer_groups = build_layer_groups(dat_file_names)

    if debug_dir:
        save_layer_groups(layer_groups, debug_dir)

    logger.info(f'generating tile specs and masks for {len(layer_groups)} (merged) layer groups')

    mask_errors = {}
    group_start_z = 1
    prior_group_restart_condition = None
    prior_last_layer_specs = None
    pre_restart_specs = None
    all_tile_specs = []
    all_restart_tile_specs = []
    resolution_xy = None

    for layer_group in layer_groups:

        header = layer_group["firstTileHeader"]
        resolution_xy = round(header["PixelSize"])

        mask_path = None
        if args.mask_dir:
            mask_path = create_mask_if_missing(header["XResolution"],
                                               header["YResolution"],
                                               args.mask_width,
                                               args.mask_dir,
                                               mask_errors)

        tile_specs_for_group = build_tile_specs_for_group(layer_group,
                                                          group_start_z,
                                                          args.image_dir,
                                                          mask_path,
                                                          args.tile_overlap_in_microns)
        tiles_per_layer = layer_group["tilesPerLayer"]
        first_layer_specs = tile_specs_for_group[0:tiles_per_layer]
        last_layer_specs = tile_specs_for_group[-tiles_per_layer:]

        if prior_group_restart_condition:
            details_label = prior_group_restart_condition[0:prior_group_restart_condition.index(":")]

            # if a group has only one layer, "patch" it with the previous layer's tile images
            layer_to_be_patched = len(layer_group["layers"]) == 1

            for tile_spec in prior_last_layer_specs:
                tile_spec["groupId"] = "restart"
            for tile_spec in first_layer_specs:
                tile_spec["labels"] = ["restart", details_label]
                if layer_to_be_patched:
                    tile_spec["labels"].append("patch")
                tile_spec["groupId"] = "restart"

            restart_index = min((args.restart_context_layers * tiles_per_layer), len(tile_specs_for_group))
            all_restart_tile_specs.extend(pre_restart_specs)
            all_restart_tile_specs.extend(tile_specs_for_group[0:restart_index])

            if layer_to_be_patched:
                patched_tile_specs = patch_layer(prior_last_layer_specs, first_layer_specs[0])
                all_tile_specs.extend(patched_tile_specs)
            else:
                all_tile_specs.extend(tile_specs_for_group)

        else:
            all_tile_specs.extend(tile_specs_for_group)

        group_start_z += len(layer_group["layers"])
        prior_group_restart_condition = layer_group["restartCondition"]
        prior_last_layer_specs = last_layer_specs
        restart_index = max(len(tile_specs_for_group) - (args.restart_context_layers * tiles_per_layer), 0)
        pre_restart_specs = tile_specs_for_group[restart_index:]

    resolution_z = set_distance_z(all_tile_specs)

    if len(all_restart_tile_specs) > 0:
        stack_name = f'{args.stack_name}_restart'
        save_stack(stack_name, render, resolution_xy, resolution_z, all_restart_tile_specs, 1)

    save_stack(args.stack_name, render, resolution_xy, resolution_z, all_tile_specs, args.num_workers)

    logger.info(f"mask errors are: {mask_errors}")

    elapsed_time = time.time() - start_time
    logger.info(f"Save completed in {elapsed_time} s")
    return 0


if __name__ == "__main__":

    # test_argv = [
    #     "--source", "/Volumes/flyem/data/Z1217-33m_BR_Sec10/dat",
    #     "--source_start_index", "70951",
    #     "--source_stop_index", "70970",
    #     "--num_workers", "1",
    #     "--dask_worker_space", "/Users/trautmane/Desktop/dask-worker-space",
    #     "--image_dir", "/groups/flyem/data/Z1217-33m_BR_Sec10/InLens",
    #     "--mask_dir", "/groups/flyem/data/render/pre_iso/masks",
    #     "--render_connect_json", "/Users/trautmane/Desktop/dat_to_render/render_connect.json"
    # ]
    # main(test_argv)

    main(sys.argv[1:])
