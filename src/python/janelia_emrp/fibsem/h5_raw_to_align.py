import argparse
import logging
import re
import traceback
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import dask.bag as dask_bag
import h5py
import math
import numpy as np
import sys
import time
from dask_janelia import get_cluster
from distributed import Client

from janelia_emrp.fibsem.cyx_dat import CYXDat
from janelia_emrp.fibsem.dat_path import new_dat_path
from janelia_emrp.fibsem.dat_to_h5_writer import DatToH5Writer, DAT_FILE_NAME_KEY, CHANNEL_DATA_SET_NAMES_KEY
from janelia_emrp.fibsem.volume_transfer_info import VolumeTransferInfo
from janelia_emrp.root_logger import init_logger

logger = logging.getLogger(__name__)


@dataclass
class H5PathsForLayer:
    raw_path: Path
    align_path: Path


class H5RawToAlign:
    """
    Converts HDF5 raw data into HDF5 alignment data.

    Attributes
    ----------
    align_writer : DatToH5Writer
        writer for align data

    skip_existing : bool, default=True
        indicates whether existing HDF5 data should be left as is (True) or overwritten (False)
    """
    def __init__(self,
                 volume_transfer_info: VolumeTransferInfo,
                 align_writer: DatToH5Writer,
                 channel_index: int,
                 skip_existing: bool = True):
        self.volume_transfer_info = volume_transfer_info
        self.align_writer = align_writer
        self.channel_index = channel_index
        self.skip_existing = skip_existing

    def __str__(self):
        return f"{self.volume_transfer_info}"

    def convert_layer(self,
                      h5_paths_for_layer: H5PathsForLayer):
        """
        Converts raw data to align data for one z-layer.

        Parameters
        ----------
        h5_paths_for_layer:
            paths of raw and align h5 files
        """
        start_time = time.time()

        logger.info(f"convert_layer: entry, reading {h5_paths_for_layer.raw_path}")

        h5_write_mode = "x" if self.skip_existing else "a"

        cyx_dat_list: list[CYXDat] = []
        with h5py.File(name=str(h5_paths_for_layer.raw_path), mode="r") as h5_raw_file:
            sorted_group_names = sorted(h5_raw_file.keys())
            for group_name in sorted_group_names:
                raw_data_group = h5_raw_file.get(group_name)
                dat_path = new_dat_path(Path(raw_data_group.attrs[DAT_FILE_NAME_KEY]))
                channel_data_set_names = raw_data_group.attrs[CHANNEL_DATA_SET_NAMES_KEY]
                channel_pixels = np.array(raw_data_group.get(channel_data_set_names[self.channel_index]))
                cyx_channel_pixels = np.expand_dims(channel_pixels, axis=0)
                cyx_dat_list.append(CYXDat(dat_path=dat_path,
                                           header=dict(raw_data_group.attrs.items()),
                                           pixels=cyx_channel_pixels))

        logger.info(f"convert_layer: writing {len(cyx_dat_list)} groups to {h5_paths_for_layer.align_path}")

        h5_paths_for_layer.align_path.parent.mkdir(parents=True, exist_ok=True)

        with self.align_writer.open_h5_file(output_path=str(h5_paths_for_layer.align_path),
                                            mode=h5_write_mode) as layer_align_file:
            self.align_writer.create_and_add_mipmap_data_sets(
                cyx_dat_list=cyx_dat_list,
                max_mipmap_level=self.volume_transfer_info.max_mipmap_level,
                to_h5_file=layer_align_file,
                fill_info=self.volume_transfer_info.fill_info)

        elapsed_seconds = int(time.time() - start_time)

        logger.info(f"{self} convert_layer: exit, {h5_paths_for_layer.raw_path.name} conversion "
                    f"took {elapsed_seconds} seconds")

    def convert_layer_list(self,
                           h5_layer_list: list[H5PathsForLayer]):
        """
        Converts raw HDF5 files specified in `h5_layer_list` to HDF5 align files.

        Parameters
        ----------
        h5_layer_list : list[H5PathsForLayer]
            list of layers to convert
        """

        number_of_layers = len(h5_layer_list)
        logger.info(f"{self} convert_layer_list: entry, processing {number_of_layers} layers")

        number_of_failed_layers = 0
        for h5_paths_for_layer in h5_layer_list:
            # noinspection PyBroadException
            try:
                self.convert_layer(h5_paths_for_layer)
            except Exception:
                traceback.print_exc()
                logger.error(f"{self} convert_layer_list: failed to convert {h5_paths_for_layer.raw_path}")
                number_of_failed_layers += 1

        if number_of_failed_layers == 0:
            logger.info(f"{self} convert_layer_list: exit, converted all {number_of_layers} layers")
        else:
            logger.info(f"{self} convert_layer_list: exit, failed to convert {number_of_failed_layers} layers")


def get_layers_for_run(h5_raw_root: Path,
                       first_h5_path: Optional[Path],
                       last_h5_path: Optional[Path],
                       skip_existing: bool,
                       volume_transfer_info: VolumeTransferInfo) -> list[H5PathsForLayer]:

    logger.info(f"get_layers_for_run: entry, h5_raw_root={h5_raw_root}, first_h5={first_h5_path}, "
                f"last_h5={last_h5_path}, skip_existing={skip_existing}")

    raw_paths: list[Path] = sorted([p for p in h5_raw_root.glob("**/*.raw*.h5")])

    logger.info(f"get_layers_for_run: found {len(raw_paths)} raw h5 files to convert")

    layers_to_convert: list[H5PathsForLayer] = []

    if len(raw_paths) > 0:

        align_h5_root = volume_transfer_info.get_align_h5_root_for_conversion()
        match = re.compile(r"\.raw[^.]*\.")

        for raw_path in raw_paths:

            if first_h5_path is not None and raw_path.name < first_h5_path.name:
                continue
            if last_h5_path is not None and raw_path.name > last_h5_path.name:
                break

            relative_parent_dir = raw_path.parent.relative_to(h5_raw_root)
            align_file_name = match.sub(".uint8.", raw_path.name)
            align_path = align_h5_root / relative_parent_dir / align_file_name
            if not skip_existing or not align_path.exists():
                layers_to_convert.append(H5PathsForLayer(raw_path, align_path))

        logger.info(f"get_layers_for_run: after filtering, {len(layers_to_convert)} remain to be converted")

    return layers_to_convert


def convert_volume(volume_transfer_info: VolumeTransferInfo,
                   num_workers: int,
                   parent_work_dir: Optional[str],
                   first_h5: Optional[str],
                   last_h5: Optional[str],
                   channel_index: int,
                   skip_existing: bool,
                   min_layers_per_worker: int,
                   lsf_runtime_limit: Optional[str]):

    logger.info(f"convert_volume: entry, processing {volume_transfer_info} with {num_workers} worker(s)")

    h5_raw_root = volume_transfer_info.get_raw_h5_root_for_conversion()

    if h5_raw_root is None:
        raise ValueError(f"h5 raw root path is not defined in volume transfer info")
    if not h5_raw_root.is_dir():
        raise ValueError(f"h5 raw root path {h5_raw_root} is not an accessible directory")

    first_h5_path = None if first_h5 is None else Path(first_h5)
    last_h5_path = None if last_h5 is None else Path(last_h5)

    h5_layer_list: list[H5PathsForLayer] = get_layers_for_run(h5_raw_root=h5_raw_root,
                                                              first_h5_path=first_h5_path,
                                                              last_h5_path=last_h5_path,
                                                              skip_existing=skip_existing,
                                                              volume_transfer_info=volume_transfer_info)

    if len(h5_layer_list) > 0:
        converter = H5RawToAlign(volume_transfer_info=volume_transfer_info,
                                 align_writer=DatToH5Writer(chunk_shape=(1, 512, 512)),
                                 channel_index=channel_index,
                                 skip_existing=skip_existing)

        if num_workers > 1:
            local_kwargs = {
                "memory_limit": "10GB"
            }
            lsf_kwargs = {
                "project": volume_transfer_info.cluster_job_project_for_billing,
                "memory": "14GB"
            }

            if parent_work_dir is not None:
                local_kwargs["local_directory"] = parent_work_dir
                lsf_kwargs["local_directory"] = parent_work_dir
                lsf_kwargs["log_directory"] = parent_work_dir

            if lsf_runtime_limit is not None:
                lsf_kwargs["walltime"] = lsf_runtime_limit

            with get_cluster(threads_per_worker=1,
                             local_kwargs=local_kwargs,
                             lsf_kwargs=lsf_kwargs) as dask_cluster, Client(dask_cluster) as dask_client:

                logger.info(f'convert_volume: observe dask cluster information at {dask_cluster.dashboard_link}')

                adjusted_num_workers = min(math.ceil(len(h5_layer_list) / min_layers_per_worker), num_workers)
                dask_client.cluster.scale(n=adjusted_num_workers)
                number_of_partitions = adjusted_num_workers

                logger.info(f"convert_volume: requested {adjusted_num_workers} worker dask cluster, " 
                            f"scaled count is {len(dask_cluster.worker_spec)}, "
                            f"number_of_partitions is {number_of_partitions}")

                bag = dask_bag.from_sequence(h5_layer_list, npartitions=number_of_partitions)
                bag = bag.map_partitions(converter.convert_layer_list)
                dask_client.compute(bag, sync=True)

        else:
            converter.convert_layer_list(h5_layer_list)

    else:
        logger.info(f"convert_volume: no layers remain to process")


def main(arg_list: list[str]):
    parser = argparse.ArgumentParser(
        description="Convert volume HDF5 raw data to HDF5 align data."
    )
    parser.add_argument(
        "--volume_transfer_info",
        help="Path of volume_transfer_info.json file",
        required=True,
    )
    parser.add_argument(
        "--num_workers",
        help="The number of workers to use for distributed processing",
        type=int,
        default=1
    )
    parser.add_argument(
        "--min_layers_per_worker",
        help="If necessary, reduce the number of workers so that each worker processes at least this many layers",
        type=int,
        default=1
    )
    parser.add_argument(
        "--parent_work_dir",
        help="Parent directory for Dask logs and worker data",
    )
    parser.add_argument(
        "--lsf_runtime_limit",
        help="Runtime limit in minutes when using LSF (e.g. [hour:]minute)",
        default="3:59"
    )
    parser.add_argument(
        "--first_h5",
        help="File name of raw h5 for first layer to be converted (omit to convert all layers)",
    )
    parser.add_argument(
        "--last_h5",
        help="File name of raw h5 for last layer to be converted (omit to convert all layers)",
    )
    parser.add_argument(
        "--force",
        help="Convert all raw h5 files even if converted result files already exist",
        default=False,
        action="store_true"
    )
    parser.add_argument(
        "--channel_index",
        help="Index of channel to convert",
        type=int,
        default=0
    )

    args = parser.parse_args(arg_list)

    convert_volume(volume_transfer_info=VolumeTransferInfo.parse_file(args.volume_transfer_info),
                   num_workers=args.num_workers,
                   parent_work_dir=args.parent_work_dir,
                   first_h5=args.first_h5,
                   last_h5=args.last_h5,
                   channel_index=args.channel_index,
                   skip_existing=(not args.force),
                   min_layers_per_worker=args.min_layers_per_worker,
                   lsf_runtime_limit=args.lsf_runtime_limit)


if __name__ == "__main__":
    # NOTE: to fix module not found errors, export PYTHONPATH="/.../EM_recon_pipeline/src/python"

    # setup logger since this module is the main program
    init_logger(__file__)

    # noinspection PyBroadException
    try:
        main(sys.argv[1:])
    except Exception as e:
        # ensure exit code is a non-zero value when Exception occurs
        traceback.print_exc()
        sys.exit(1)
