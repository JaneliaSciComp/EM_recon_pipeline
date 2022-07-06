import argparse
import logging
import math
import sys
import time
from pathlib import Path
from typing import List, Optional, Dict, Any, Tuple, Final

import dask.bag as db
import h5py
import renderapi
from dask_janelia import get_cluster

from janelia_emrp.fibsem.dat_path import DatPath, new_dat_path
from janelia_emrp.fibsem.dat_to_h5_writer import DAT_FILE_NAME_KEY
from janelia_emrp.fibsem.mask_builder import MaskBuilder
from janelia_emrp.fibsem.render_api import RenderApi
from janelia_emrp.fibsem.volume_transfer_info import VolumeTransferInfo
from janelia_emrp.root_logger import init_logger, console_handler

logger = logging.getLogger(__name__)

COMMON_TILE_HEADER_KEYS: Final = [
    "XResolution", "YResolution", "PixelSize", "EightBit", "ChanNum", "SWdate",
    "StageX", "StageY", "StageZ", "StageR"
]
UNIQUE_TILE_HEADER_KEYS: Final = ["WD", "Restart", "StageMove", "FirstX", "FirstY"]
RETAINED_TILE_HEADER_KEYS: Final = COMMON_TILE_HEADER_KEYS + UNIQUE_TILE_HEADER_KEYS
CHECKED_TILE_HEADER_KEYS: Final = COMMON_TILE_HEADER_KEYS + ["SampleID"]

FIBSEM_CORRECTION_TRANSFORM_ID: Final = "FIBSEM_correct"
FIBSEM_CORRECTION_TRANSFORM: Final = {
    "id": FIBSEM_CORRECTION_TRANSFORM_ID,
    "className": "org.janelia.alignment.transform.SEMDistortionTransformA",
    "dataString": "19.4 64.8 24.4 972.0 0"
}


class LayerInfo:
    def __init__(self, h5_path: Path) -> None:
        self.h5_path = h5_path
        self.dat_paths: List[DatPath] = []
        self.retained_headers: List[Dict[str, Any]] = []
        self.group_id: Optional[str] = None
        self.restart_condition_label: Optional[str] = None

        with h5py.File(name=str(h5_path), mode="r") as h5_file:

            sorted_group_names = sorted(h5_file.keys())
            if len(sorted_group_names) < 1:
                raise RuntimeError(f"possible corrupt file {h5_path}, no group names found")

            for group_name in sorted(sorted_group_names):
                group = h5_file.get(group_name)
                if DAT_FILE_NAME_KEY in group.attrs:
                    self.append_tile(group.attrs)
                else:
                    logger.warning(f"skipping group {group_name} in {h5_path} "
                                   f"because it does not have '{DAT_FILE_NAME_KEY}' attribute")

            if len(self.dat_paths) == 0:
                raise RuntimeError(f"possible corrupt file {h5_path}, "
                                   f"no dat file names found in groups {sorted_group_names}")

    def append_tile(self,
                    full_header: Dict[str, Any]) -> None:

        retained_header = {}

        dat_path = new_dat_path(Path(full_header[DAT_FILE_NAME_KEY]))

        for key in RETAINED_TILE_HEADER_KEYS:
            if key in full_header:
                retained_header[key] = full_header[key]

        if "SampleID" in full_header:
            retained_header["SampleID"] = full_header["SampleID"]
        else:
            # "Z1217-33m_BR_Sec10, BF 316x100um, 24s @11.5nA /8nm @15nA-1, lens2 14110-40V..., bias 0V, deflector +100V"
            notes = full_header["Notes"]
            retained_header["SampleID"] = notes[0:notes.find(",")]

        if full_header["PixelSize"] == 0:
            raise RuntimeError(f"Header PixelSize is zero for {dat_path.file_path}")

        self.dat_paths.append(dat_path)
        self.retained_headers.append(retained_header)

    def tile_count(self):
        return len(self.dat_paths)

    def tile_index_for_column(self, column: int):
        tile_index = None
        for i in range(0, len(self.dat_paths)):
            if self.dat_paths[i].column == column:
                tile_index = i
                break
        return tile_index

    def working_distance_for_column(self, column: int):
        working_distance = None
        tile_index = self.tile_index_for_column(column)
        if tile_index is not None:
            working_distance = self.retained_headers[tile_index]["WD"]
        return working_distance


def build_layers(split_h5_paths: List[Path]) -> List[LayerInfo]:
    logger.info(f"build_layers: entry, processing {len(split_h5_paths)} layers starting with {split_h5_paths[0]}")
    return [LayerInfo(h5_path) for h5_path in split_h5_paths]


def split_list_for_workers(full_list, num_workers):
    items_per_worker = math.ceil(len(full_list) / num_workers)
    return [full_list[i:i + items_per_worker] for i in range(0, len(full_list), items_per_worker)]


def flatten_list_of_lists(list_of_lists):
    return [item for sublist in list_of_lists for item in sublist]


def build_all_layers(align_storage_root: Path,
                     num_workers: int,
                     threads_per_worker: int,
                     dask_worker_space: Optional[str],
                     bill_project: Optional[str],
                     min_index: Optional[int],
                     max_index: Optional[int]) -> List[LayerInfo]:

    if not align_storage_root.is_dir():
        raise ValueError(f"missing align storage root directory {align_storage_root}")

    logger.info(f"build_all_layers: looking for .h5 files in {align_storage_root}")

    layer_h5_paths = sorted(align_storage_root.glob("**/*.h5"))

    logger.info(f"build_all_layers: found {len(layer_h5_paths)} .h5 files in {align_storage_root}")

    slice_max = max_index + 1 if max_index is not None else None
    if min_index is not None:
        if slice_max is not None:
            layer_h5_paths = layer_h5_paths[min_index:slice_max]
        else:
            layer_h5_paths = layer_h5_paths[min_index:]
    elif slice_max is not None:
        layer_h5_paths = layer_h5_paths[0:slice_max]

    if min_index is not None or slice_max is not None:
        logger.info(f"build_all_layers: processing {len(layer_h5_paths)} .h5 files "
                    f"in filtered range [{min_index}, {slice_max}]")

    if num_workers > 1:
        dask_cluster = get_cluster(threads_per_worker=threads_per_worker,
                                   local_kwargs={
                                       "local_directory": dask_worker_space
                                   },
                                   lsf_kwargs={
                                       "local_directory": dask_worker_space,
                                       "project": bill_project
                                   })

        logger.info(f"build_all_layers: observe dask cluster information at {dask_cluster.dashboard_link}")

        dask_cluster.scale(num_workers)
        logger.info(f"build_all_layers: scaled dask cluster to {num_workers} workers")

        split_h5_paths = split_list_for_workers(layer_h5_paths, num_workers)
        bag = db.from_sequence(split_h5_paths, npartitions=num_workers).map(build_layers)
        all_layers = flatten_list_of_lists(bag.compute())

    else:
        all_layers = build_layers(layer_h5_paths)

    return all_layers


def set_layer_restart_condition(layer_info: LayerInfo,
                                prior_layer_info: LayerInfo,
                                restart_seconds_threshold: int):

    prior_dat_path = prior_layer_info.dat_paths[-1]
    prior_header = prior_layer_info.retained_headers[-1]

    for tile_index in range(0, layer_info.tile_count()):
        dat_path = layer_info.dat_paths[tile_index]
        header = layer_info.retained_headers[tile_index]

        restart_condition = None

        if tile_index == 0:
            time_delta = dat_path.acquire_time - prior_dat_path.acquire_time

            if time_delta.seconds > restart_seconds_threshold:
                restart_condition = f"acquisition_delay: tile {dat_path.file_path} acquired {time_delta.seconds} " \
                                    f"seconds after tile {prior_dat_path.file_path}"

            if prior_layer_info.tile_count() != layer_info.tile_count():
                restart_condition = f"change_tile_count: layer {dat_path.layer_id} has {layer_info.tile_count()} " \
                                    f"instead of {prior_layer_info.tile_count()} tiles"

        if not restart_condition:
            for k in COMMON_TILE_HEADER_KEYS:
                if header[k] != prior_header[k]:

                    # From Shan:
                    #   Small PixelSize deltas are "due to the step change of the microscope magnification as
                    #   the working distance (WD) increases (material being milled away). Different tiles change at
                    #   different frames because they have different WD values. The magnification might have a small
                    #   step jump when this happens which I think will be taken care of by SIFT."
                    if k == "PixelSize":
                        delta = abs(float(header[k]) - float(prior_header[k]))
                        if delta < 0.5:
                            continue

                    restart_condition = f"change_header_{k.lower()}: " \
                                        f"{k} value of {prior_header[k]} for {prior_dat_path.file_path} " \
                                        f"changed to {header[k]} for {dat_path.file_path}"
                    break

        if restart_condition:
            logger.info(f'set_layer_restart_condition: found condition: {restart_condition}')
            layer_info.group_id = "restart"
            layer_info.restart_condition_label = restart_condition[0:restart_condition.index(":")]
            break

        prior_dat_path = dat_path
        prior_header = header


def build_tile_spec(h5_path: Path,
                    dat_path: DatPath,
                    z: int,
                    tile_overlap_in_microns: int,
                    tile_attributes: Dict[str, Any],
                    prior_layer: Optional[LayerInfo],
                    mask_path: Optional[Path],
                    pre_stage_transform_spec_list: list[Dict[str, str]]):

    acquire_time_string = dat_path.acquire_time.strftime("%y-%m-%d_%H%M%S")
    tile_key = dat_path.tile_key()
    section_id = str(z) + ".0"

    # 20-12-01_224100_0-0-0.1066.0
    tile_id = f"{acquire_time_string}_{tile_key}.{section_id}"

    tile_width = int(tile_attributes["XResolution"])   # convert h5 int64 to int for json encoder
    tile_height = int(tile_attributes["YResolution"])  # convert h5 int64 to int for json encoder
    working_distance = tile_attributes["WD"]

    # stage x and y is not provided for FIB-SEM versions < 9
    stage_x = tile_attributes.get("FirstX")
    stage_y = tile_attributes.get("FirstY")

    if stage_x is None or stage_y is None:
        nm_per_pixel = tile_attributes["PixelSize"]
        overlap_nm = tile_overlap_in_microns * 1000
        overlap_pixels = overlap_nm / nm_per_pixel
        margin = 400  # offset everything a little to help viewers that have trouble with negative space
        if stage_x is None:
            stage_x = margin + round(dat_path.column * (tile_width - overlap_pixels))
        if stage_y is None:
            stage_y = margin + round(dat_path.row * (tile_height - overlap_pixels))
    else:
        stage_x = int(stage_x)  # convert h5 int64 to int for json encoder
        stage_y = int(stage_y)  # convert h5 int64 to int for json encoder

    mipmap_level_zero = {
        "imageUrl": f"file://{str(h5_path)}?dataSet=/{tile_key}/mipmap.0&z=0",
        "imageLoaderType": "H5_SLICE"
    }
    if mask_path is not None:
        mipmap_level_zero["maskUrl"] = f'file:{str(mask_path)}'

    transform_spec_list = []
    transform_spec_list.extend(pre_stage_transform_spec_list)
    transform_spec_list.append({"type": "leaf",
                                "className": "mpicbg.trakem2.transform.AffineModel2D",
                                "dataString": f'1 0 0 1 {stage_x} {stage_y}'})
    tile_spec = {
        "tileId": tile_id, "z": z,
        "minX": stage_x, "minY": stage_y, "maxX": stage_x + tile_width, "maxY": stage_y + tile_height,
        "layout": {
            "sectionId": section_id,
            "imageRow": dat_path.row, "imageCol": dat_path.column,
            "stageX": stage_x, "stageY": stage_y, "workingDistance": working_distance
        },
        "width": tile_width, "height": tile_height, "minIntensity": 0, "maxIntensity": 255,
        "mipmapLevels": {
            "0": mipmap_level_zero
        },
        "transforms": {
            "type": "list",
            "specList": transform_spec_list
        }
    }

    if prior_layer is not None:
        prior_working_distance = prior_layer.working_distance_for_column(dat_path.column)
        if prior_working_distance is not None:
            distance_z = (working_distance - prior_working_distance) * 1000000
            tile_spec["layout"]["distanceZ"] = distance_z

    # TODO: from code review: look at render-python class (or consider attrs.py model)
    # return renderapi.tilespec.TileSpec(json=tile_spec)
    return tile_spec


def build_tile_specs_for_layer(layer_info: LayerInfo,
                               z: int,
                               prior_layer_info: Optional[LayerInfo],
                               mask_builder: Optional[MaskBuilder],
                               tile_overlap_in_microns: int,
                               pre_stage_transform_spec_list: list[Dict[str, str]]):

    mask_path = None
    if mask_builder is not None:
        first_tile_attributes = layer_info.retained_headers[0]
        mask_path = mask_builder.create_mask_if_missing(image_width=first_tile_attributes["XResolution"],
                                                        image_height=first_tile_attributes["YResolution"])

    tile_specs = []
    for tile_index in range(0, layer_info.tile_count()):

        tile_spec = build_tile_spec(h5_path=layer_info.h5_path,
                                    dat_path=layer_info.dat_paths[tile_index],
                                    z=z,
                                    tile_overlap_in_microns=tile_overlap_in_microns,
                                    tile_attributes=layer_info.retained_headers[tile_index],
                                    prior_layer=prior_layer_info,
                                    mask_path=mask_path,
                                    pre_stage_transform_spec_list=pre_stage_transform_spec_list)

        if layer_info.group_id is not None:
            tile_spec["groupId"] = layer_info.group_id

        if layer_info.restart_condition_label is not None:
            tile_spec["labels"] = ["restart", layer_info.restart_condition_label]

        tile_specs.append(tile_spec)

    return tile_specs


def build_all_tile_specs(all_layers: List[LayerInfo],
                         restart_context_layer_count: int,
                         mask_builder: Optional[MaskBuilder],
                         tile_overlap_in_microns: int,
                         pre_stage_transform_ids: list[str]) -> Tuple[list[Any], list[Any]]:
    layer_count = len(all_layers)

    logger.info(f"build_all_tile_specs: entry, processing {layer_count} layers")

    if layer_count == 0:
        raise ValueError("no layers specified")

    pre_stage_transform_spec_list = []
    for transform_id in pre_stage_transform_ids:
        pre_stage_transform_spec_list.append({"type": "ref", "refId": transform_id})

    all_tile_specs = []
    all_restart_tile_specs = []

    all_tile_specs.extend(
        build_tile_specs_for_layer(layer_info=all_layers[0],
                                   z=1,
                                   prior_layer_info=None,
                                   mask_builder=mask_builder,
                                   tile_overlap_in_microns=tile_overlap_in_microns,
                                   pre_stage_transform_spec_list=pre_stage_transform_spec_list))

    # flag restart if more than 15 minutes elapses between layer acquisitions
    restart_seconds_threshold = 15 * 60
    restart_z_values = []

    prior_layer_info = all_layers[0]
    for z in range(2, layer_count + 1):
        layer_info = all_layers[z-1]

        set_layer_restart_condition(layer_info,
                                    prior_layer_info,
                                    restart_seconds_threshold)

        if layer_info.restart_condition_label is not None:

            # set groupId for layer prior to restart, but exclude labels
            if prior_layer_info.restart_condition_label is None:
                prior_layer_info.group_id = "restart"
                restart_z_values.append(z-1)

            restart_z_values.append(z)

        prior_layer_info = layer_info

    logger.info(f"build_all_tile_specs: restart layer z values are {restart_z_values}")

    # build tile specs
    prior_layer_info = all_layers[0]
    for z in range(2, layer_count + 1):
        layer_info = all_layers[z-1]

        layer_tile_specs = build_tile_specs_for_layer(layer_info=layer_info,
                                                      z=z,
                                                      prior_layer_info=prior_layer_info,
                                                      mask_builder=mask_builder,
                                                      tile_overlap_in_microns=tile_overlap_in_microns,
                                                      pre_stage_transform_spec_list=pre_stage_transform_spec_list)

        all_tile_specs.extend(layer_tile_specs)

        for restart_z in restart_z_values:
            context_min_z = restart_z - restart_context_layer_count
            context_max_z = restart_z + restart_context_layer_count
            if context_min_z <= z <= context_max_z:
                all_restart_tile_specs.extend(layer_tile_specs)
                break

        prior_layer_info = layer_info

    logger.info(f"build_all_tile_specs: exit, returning {len(all_tile_specs)} tile specs "
                f"and {len(all_restart_tile_specs)} restart tile specs")

    return all_tile_specs, all_restart_tile_specs


# def import_tile_specs(tile_specs, stack, render):
#     if len(tile_specs) > 0:
#         logger.info(f"import_tile_specs: {tile_specs[0].tileId} to {tile_specs[-1].tileId}")
#         renderapi.client.import_tilespecs(stack, tile_specs, render=render, use_rest=True)
def import_tile_specs(tile_specs: list[Dict[str, Any]],
                      transform_specs: list[Dict[str, str]],
                      stack: str,
                      render_api: RenderApi):
    if len(tile_specs) > 0:
        logger.info(f'import_tile_specs: {tile_specs[0]["tileId"]} to {tile_specs[-1]["tileId"]}')

        transform_id_to_spec_map = {}
        for transform_spec in transform_specs:
            transform_id_to_spec_map[transform_spec["id"]] = transform_spec

        tile_id_to_spec_map = {}
        for tile_spec in tile_specs:
            tile_id_to_spec_map[tile_spec["tileId"]] = tile_spec

        resolved_tiles = {
            "transformIdToSpecMap": transform_id_to_spec_map,
            "tileIdToSpecMap": tile_id_to_spec_map
        }

        # Derive bounding box server-side when "lens correction" transforms are used
        # (not necessary when tile specs only contain stage transforms).
        derive_data = len(transform_specs) > 0

        render_api.save_resolved_tiles(stack=stack,
                                       resolved_tiles=resolved_tiles,
                                       derive_data=derive_data)


def save_stack(stack_name: str,
               volume_transfer_info: VolumeTransferInfo,
               tile_specs: list[Dict],
               transform_specs: list[Dict]):

    render_connect_params = volume_transfer_info.get_render_connect_params()

    render = renderapi.connect(**render_connect_params)

    # explicitly set createTimestamp until render-python bug is fixed
    # see https://github.com/AllenInstitute/render-python/pull/158
    create_timestamp = time.strftime('%Y-%m-%dT%H:%M:%S.00Z')

    renderapi.stack.create_stack(stack=stack_name,
                                 render=render,
                                 createTimestamp=create_timestamp,
                                 stackResolutionX=volume_transfer_info.dat_x_and_y_nm_per_pixel,
                                 stackResolutionY=volume_transfer_info.dat_x_and_y_nm_per_pixel,
                                 stackResolutionZ=volume_transfer_info.dat_z_nm_per_pixel)

    # api_tile_specs = [renderapi.tilespec.TileSpec(json=tile_spec) for tile_spec in tile_specs]
    #
    # tile_count = len(api_tile_specs)
    # tiles_per_batch = 5000
    # for index in range(0, tile_count, tiles_per_batch):
    #     stop_index = min(index + tiles_per_batch, tile_count)
    #     import_tile_specs(tile_specs=api_tile_specs[index:stop_index],
    #                       stack=stack_name,
    #                       render=render)

    render_api = RenderApi(render_owner=volume_transfer_info.render_owner,
                           render_project=volume_transfer_info.render_project,
                           render_connect=volume_transfer_info.render_connect)
    tile_count = len(tile_specs)
    tiles_per_batch = 5000
    for index in range(0, tile_count, tiles_per_batch):
        stop_index = min(index + tiles_per_batch, tile_count)
        import_tile_specs(tile_specs=tile_specs[index:stop_index],
                          transform_specs=transform_specs,
                          stack=stack_name,
                          render_api=render_api)

    mipmap_path_builder = {
        "rootPath": str(volume_transfer_info.align_mask_mipmap_root),
        "numberOfLevels": volume_transfer_info.max_mipmap_level,
        "extension": "tif",
        "imageMipmapPatternString": "(.*dataSet=.*mipmap\\.)\\d+(.*)"
    }
    render_api.save_mipmap_path_builder(stack=stack_name,
                                        mipmap_path_builder=mipmap_path_builder)
    
    renderapi.stack.set_stack_state(stack_name, 'COMPLETE', render=render)


def main(arg_list):

    init_logger(__file__)

    render_api_logger = logging.getLogger("renderapi")
    render_api_logger.setLevel(logging.DEBUG)
    render_api_logger.addHandler(console_handler)

    start_time = time.time()

    parser = argparse.ArgumentParser(
        description="Parse h5 (dat) metadata and convert to tile specs that can be saved to render."
    )

    parser.add_argument(
        "--volume_transfer_info",
        help="Path of volume_transfer_info.json file",
        required=True,
    )
    parser.add_argument(
        "--min_layer_index",
        help="Reduce layers processed by specifying index of first (sorted) layer to process",
        type=int,
        default=0
    )
    parser.add_argument(
        "--max_layer_index",
        help="Reduce layers processed by specifying index of last (sorted) layer to process",
        type=int
    )
    parser.add_argument(
        "--dask_worker_space",
        help="Directory for Dask worker data (omit when not using multiple workers)",
    )
    parser.add_argument(
        "--num_workers",
        help="The number of Dask workers to use for distributed processing",
        type=int,
        default=1
    )
    parser.add_argument(
        "--num_threads_per_worker",
        help="The number of threads for each worker",
        type=int,
        default=1
    )

    args = parser.parse_args(args=arg_list)

    volume_transfer_info: VolumeTransferInfo = VolumeTransferInfo.parse_file(args.volume_transfer_info)

    all_layers = build_all_layers(align_storage_root=volume_transfer_info.align_storage_root,
                                  num_workers=args.num_workers,
                                  threads_per_worker=args.num_threads_per_worker,
                                  dask_worker_space=args.dask_worker_space,
                                  bill_project=volume_transfer_info.bill_project,
                                  min_index=args.min_layer_index,
                                  max_index=args.max_layer_index)

    logger.info(f"main: generating tile specs and masks for {len(all_layers)} layers")

    mask_builder: Optional[MaskBuilder] = None

    # only build masks if they are needed, and we are writing data to render
    if volume_transfer_info.mask_storage_root is not None and \
            volume_transfer_info.render_connect is not None:
        mask_builder = MaskBuilder(base_dir=volume_transfer_info.mask_storage_root,
                                   mask_width=volume_transfer_info.mask_width)

    pre_stage_transform_ids = []
    transform_specs = []
    if volume_transfer_info.include_fibsem_correction_transform:
        pre_stage_transform_ids.append(FIBSEM_CORRECTION_TRANSFORM["id"])
        transform_specs.append(FIBSEM_CORRECTION_TRANSFORM)

    all_tile_specs, all_restart_tile_specs = \
        build_all_tile_specs(all_layers=all_layers,
                             restart_context_layer_count=volume_transfer_info.render_restart_context_layer_count,
                             mask_builder=mask_builder,
                             tile_overlap_in_microns=volume_transfer_info.dat_tile_overlap_microns,
                             pre_stage_transform_ids=pre_stage_transform_ids)

    if volume_transfer_info.render_connect is not None:
        if len(all_restart_tile_specs) > 0:
            save_stack(stack_name=f"{volume_transfer_info.render_stack}_restart",
                       volume_transfer_info=volume_transfer_info,
                       tile_specs=all_restart_tile_specs,
                       transform_specs=transform_specs)

        save_stack(stack_name=volume_transfer_info.render_stack,
                   volume_transfer_info=volume_transfer_info,
                   tile_specs=all_tile_specs,
                   transform_specs=transform_specs)

        if mask_builder is not None and len(mask_builder.mask_errors) > 0:
            logger.error(f"mask errors are: {mask_builder.mask_errors}")

    elapsed_time = time.time() - start_time
    logger.info(f"main: processing completed in {elapsed_time} s")

    return 0


if __name__ == "__main__":

    # test_argv = [
    #     "--volume_transfer_info", "/Users/trautmane/Desktop/volume_transfer_info.json",
    #     "--min_layer_index", "0",
    #     "--max_layer_index", "10",
    #     "--num_workers", "1",
    #     "--dask_worker_space", "/Users/trautmane/Desktop/dask-worker-space",
    # ]
    # main(test_argv)

    main(sys.argv[1:])
