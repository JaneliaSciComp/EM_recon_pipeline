import argparse
import datetime
import logging
import os
import re
import traceback
from contextlib import ExitStack
from pathlib import Path
from typing import Optional, List

import dask.bag as dask_bag
import errno
import math
import sys
import time
from dask_janelia import get_cluster
from distributed import Client

from janelia_emrp.fibsem.cyx_dat import CYXDat, new_cyx_dat
from janelia_emrp.fibsem.dat_path import DatPathsForLayer, split_into_layers, new_dat_path, DatPath
from janelia_emrp.fibsem.dat_to_h5_writer import DatToH5Writer
from janelia_emrp.fibsem.h5_to_dat import validate_original_dat_bytes_match
from janelia_emrp.fibsem.volume_transfer_info import VolumeTransferInfo, VolumeTransferTask
from janelia_emrp.root_logger import init_logger

logger = logging.getLogger(__name__)


class DatConverter:
    """
    Converts .dat source data into HDF5 artifacts needed for archival storage and alignment.

    Attributes
    ----------
    raw_writer : Optional[DatToH5Writer], default=None
        writer for archive data, None if archive data should not be produced

    align_writer : Optional[DatToH5Writer], default=None
        writer for align data, None if align data should not be produced

    skip_existing : bool, default=True
        indicates whether existing HDF5 data should be left as is (True) or overwritten (False)
    """
    def __init__(self,
                 volume_transfer_info: VolumeTransferInfo,
                 raw_writer: Optional[DatToH5Writer] = None,
                 align_writer: Optional[DatToH5Writer] = None,
                 skip_existing: bool = True):
        self.volume_transfer_info = volume_transfer_info
        self.raw_writer = raw_writer
        self.align_writer = align_writer
        self.skip_existing = skip_existing

    def __str__(self):
        return f"{self.volume_transfer_info}"

    def convert_layer(self,
                      dat_paths_for_layer: DatPathsForLayer,
                      raw_h5_root_path: Optional[Path],
                      align_h5_root_path: Optional[Path]):
        """
        Converts specified `dat_paths_for_layer` sources into HDF5 artifacts.

        Parameters
        ----------
        dat_paths_for_layer:
            paths of .dat source files in a single layer
        raw_h5_root_path:
            root path for raw h5 output or None if raw conversion is not desired
        align_h5_root_path:
            root path for align h5 output or None if align conversion is not desired
        """
        start_time = time.time()

        logger.info(f"{self} convert_layer: entry, processing {len(dat_paths_for_layer.dat_paths)} dat files "
                    f"for layer {dat_paths_for_layer.get_layer_id()}")

        h5_write_mode = "x" if self.skip_existing else "a"
        raw_path = None
        if raw_h5_root_path is not None:
            raw_path = dat_paths_for_layer.get_h5_path(raw_h5_root_path, source_type="raw")
            raw_path = self.setup_h5_path("archive", raw_path, self.skip_existing)

        align_path = None
        if align_h5_root_path is not None:
            align_path = dat_paths_for_layer.get_h5_path(align_h5_root_path, source_type="uint8")
            align_path = self.setup_h5_path("align source", align_path, self.skip_existing)

        with ExitStack() as stack:
            if raw_path:
                layer_raw_file = stack.enter_context(self.raw_writer.open_h5_file(output_path=str(raw_path),
                                                                                  mode=h5_write_mode))
            if align_path:
                layer_align_file = stack.enter_context(self.align_writer.open_h5_file(output_path=str(align_path),
                                                                                      mode=h5_write_mode))

            # TODO: clean-up properly if errors occur during conversion

            if raw_path or align_path:
                align_cyx_dat_record_list: list[CYXDat] = []
                for dat_path in dat_paths_for_layer.dat_paths:

                    if not dat_path.file_path.exists():
                        raise FileNotFoundError(errno.ENOENT, os.strerror(errno.ENOENT), dat_path.file_path)

                    cyx_dat: CYXDat = new_cyx_dat(dat_path)

                    if raw_path:
                        self.raw_writer.create_and_add_raw_data_group(cyx_dat=cyx_dat,
                                                                      to_h5_file=layer_raw_file)
                    if align_path:
                        align_cyx_dat_record_list.append(cyx_dat)

                if len(align_cyx_dat_record_list) > 0:
                        self.align_writer.create_and_add_mipmap_data_sets(
                            cyx_dat_list=align_cyx_dat_record_list,
                            max_mipmap_level=self.volume_transfer_info.max_mipmap_level,
                            to_h5_file=layer_align_file,
                            fill_info=self.volume_transfer_info.fill_info)

        if raw_path is not None:
            if self.volume_transfer_info.includes_task(VolumeTransferTask.REMOVE_DAT_AFTER_H5_CONVERSION):
                dat_parent_path = dat_paths_for_layer.dat_paths[0].file_path.parent

                try:
                    matched_dat_file_paths = validate_original_dat_bytes_match(h5_path=raw_path,
                                                                               dat_parent_path=dat_parent_path)
                    for dat_path in matched_dat_file_paths:
                        logger.info(f"{self} convert_layer: removing {dat_path}")
                        dat_path.unlink()

                except ValueError:
                    traceback.print_exc()
                    logger.error(f"{self} convert_layer: skipped dat removal because h5 validation failed for {raw_path}")

            # now that raw h5 write is complete, rename it so that archival process knows it is safe to handle
            ready_for_archival_name = re.sub(r"\.raw\.h5$", ".raw-archive.h5", str(raw_path.name))
            ready_for_archival_path = raw_path.parent / ready_for_archival_name
            os.rename(raw_path, ready_for_archival_path)
            logger.info(f"{self} convert_layer: renamed {raw_path.name} to {ready_for_archival_name}")

        elapsed_seconds = int(time.time() - start_time)

        logger.info(f"{self} convert_layer: exit, layer {dat_paths_for_layer.get_layer_id()} conversion "
                    f"took {elapsed_seconds} seconds")

    def convert_layer_list(self,
                           dat_layer_list: List[DatPathsForLayer]):
        """
        Converts specified `dat_layer_list` into HDF5 artifacts.

        Parameters
        ----------
        dat_layer_list : List[DatPathsForLayer]
            list of layers to convert
        """

        number_of_layers = len(dat_layer_list)
        logger.info(f"{self} convert_layer_list: entry, processing {number_of_layers} layers")

        raw_h5_root = self.volume_transfer_info.get_raw_h5_root_for_conversion() if self.raw_writer else None
        align_h5_root = self.volume_transfer_info.get_align_h5_root_for_conversion() if self.align_writer else None

        number_of_failed_layers = 0
        for dat_paths_for_layer in dat_layer_list:
            # noinspection PyBroadException
            try:
                self.convert_layer(dat_paths_for_layer=dat_paths_for_layer,
                                   raw_h5_root_path=raw_h5_root,
                                   align_h5_root_path=align_h5_root)
            except Exception:
                traceback.print_exc()
                logger.error(f"{self} convert_layer_list: failed to convert layer {dat_paths_for_layer.get_layer_id()}")
                number_of_failed_layers += 1

        if number_of_failed_layers == 0:
            logger.info(f"{self} convert_layer_list: exit, converted all {number_of_layers} layers")
        else:
            logger.info(f"{self} convert_layer_list: exit, failed to convert {number_of_failed_layers} layers")


    def setup_h5_path(self,
                      context: str,
                      h5_path: Path,
                      skip_existing: bool) -> Optional[Path]:
        """
        Helper function to create missing subdirectories for a new HDF5 file.

        Returns
        -------
        Path
            The specified path if the file should be created or None if the file already exists and should be skipped.
        """
        valid_path = None
        if h5_path.exists():
            if skip_existing:
                logger.info(f"{self} setup_h5_path: skipping existing {context} {h5_path}")
            else:
                valid_path = h5_path
        else:
            h5_path.parent.mkdir(parents=True, exist_ok=True)
            valid_path = h5_path

        return valid_path


def get_layer_index_for_dat(layers: list[DatPathsForLayer],
                            start_index: Optional[int],
                            dat_path: DatPath) -> Optional[int]:
    layer_index = None
    if dat_path is not None:
        start = 0 if start_index is None else start_index
        for i in range(start, len(layers)):
            if layers[i].get_layer_id() >= dat_path.layer_id:
                layer_index = i
                break
    return layer_index


def get_layers_for_run(dat_root: Path,
                       first_dat: Optional[str],
                       last_dat: Optional[str],
                       skip_existing: bool,
                       volume_transfer_info: VolumeTransferInfo) -> list[DatPathsForLayer]:

    logger.info(f"get_layers_for_run: entry, dat_root={dat_root}, first_dat={first_dat}, "
                f"last_dat={last_dat}, skip_existing={skip_existing}")

    layers: list[DatPathsForLayer] = split_into_layers(path_list=[dat_root])

    logger.info(f"get_layers_for_run: found {len(layers)} layers to convert")

    if len(layers) > 0:

        if skip_existing:
            logger.info(f"get_layers_for_run: filtering out existing layers")
            new_layers = []
            raw_h5_root_path = volume_transfer_info.get_raw_h5_root_for_conversion()
            align_h5_root = volume_transfer_info.get_align_h5_root_for_conversion()

            for layer in layers:
                if not layer.h5_exists(h5_root_path=raw_h5_root_path, source_type="raw") or \
                        not layer.h5_exists(h5_root_path=align_h5_root, source_type="uint8"):
                    new_layers.append(layer)

            if len(new_layers) < len(layers):
                layers = new_layers
                logger.info(f"get_layers_for_run: after filtering, {len(layers)} remain to be converted")

        first_dat_path = None if first_dat is None else new_dat_path(Path(first_dat))
        last_dat_path = None if last_dat is None else new_dat_path(Path(last_dat))

        if first_dat_path is not None and last_dat_path is not None:
            if first_dat_path.layer_id > last_dat_path.layer_id:
                raise ValueError(f"first dat layer {first_dat_path.layer_id} "
                                 f"is after last dat layer {last_dat_path.layer_id}")
            if first_dat_path.layer_id > layers[-1].get_layer_id():
                raise ValueError(f"first dat layer {first_dat_path.layer_id} "
                                 f"is after last found layer {layers[-1].get_layer_id()}")
            if last_dat_path.layer_id < layers[0].get_layer_id():
                raise ValueError(f"last dat layer {last_dat_path.layer_id} "
                                 f"is before first found layer {layers[0].get_layer_id()}")

        min_index = get_layer_index_for_dat(layers=layers,
                                            start_index=0,
                                            dat_path=first_dat_path)

        max_index = get_layer_index_for_dat(layers=layers,
                                            start_index=min_index,
                                            dat_path=last_dat_path)

        # ensure last layer is excluded from conversion
        # unless last dat file of last layer is not recently modified and
        # acquisition has stopped or last dat path was explicitly specified
        layer_count_minus_one = len(layers) - 1
        slice_max = layer_count_minus_one if max_index is None else min(len(layers), (max_index + 1))
        if len(layers) > 0 and (volume_transfer_info.acquisition_stopped() or last_dat_path is not None):
            one_hour_ago = datetime.datetime.now() - datetime.timedelta(hours=1)
            exclude_timestamp = datetime.datetime.timestamp(one_hour_ago)
            last_layer: DatPathsForLayer = layers[-1]
            last_dat: Path = last_layer.dat_paths[-1].file_path
            if (last_dat.stat().st_mtime <= exclude_timestamp) and (slice_max >= layer_count_minus_one):
                logger.info("get_layers_for_run: including last layer because "
                            "acquisition stopped and last dat is not recently modified")
                slice_max = None
        slice_min = None if min_index is None else max(min_index, 0)
        if slice_min is not None:
            layers = layers[slice_min:] if slice_max is None else layers[slice_min:slice_max]
        elif slice_max is not None:
            layers = layers[0:slice_max]

        logger.info(f"get_layers_for_run: {len(layers)} layers remain with index range {slice_min}, {slice_max}")

    return layers


def convert_volume(volume_transfer_info: VolumeTransferInfo,
                   num_workers: int,
                   parent_work_dir: Optional[str],
                   first_dat: Optional[str],
                   last_dat: Optional[str],
                   skip_existing: bool,
                   min_layers_per_worker: int,
                   lsf_runtime_limit: Optional[str]):

    logger.info(f"convert_volume: entry, processing {volume_transfer_info} with {num_workers} worker(s)")

    dat_root = volume_transfer_info.get_dat_root_for_conversion()

    if dat_root is None:
        raise ValueError(f"dat root path is not defined in volume transfer info")
    if not dat_root.is_dir():
        raise ValueError(f"dat root path {dat_root} is not an accessible directory")

    layers = get_layers_for_run(dat_root, first_dat, last_dat, skip_existing, volume_transfer_info)

    if len(layers) > 0:
        raw_writer = DatToH5Writer(chunk_shape=(512, 512))
        align_writer = DatToH5Writer(chunk_shape=(1, 512, 512))

        converter = DatConverter(volume_transfer_info=volume_transfer_info,
                                 raw_writer=raw_writer,
                                 align_writer=align_writer,
                                 skip_existing=skip_existing)

        if num_workers > 1:
            local_kwargs = {}
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

                adjusted_num_workers = min(math.ceil(len(layers) / min_layers_per_worker), num_workers)
                dask_client.cluster.scale(n=adjusted_num_workers)
                number_of_partitions = adjusted_num_workers

                logger.info(f"convert_volume: requested {adjusted_num_workers} worker dask cluster, " 
                            f"scaled count is {len(dask_cluster.worker_spec)}, "
                            f"number_of_partitions is {number_of_partitions}")

                bag = dask_bag.from_sequence(layers, npartitions=number_of_partitions)
                bag = bag.map_partitions(converter.convert_layer_list)
                dask_client.compute(bag, sync=True)

        else:
            converter.convert_layer_list(layers)

    else:
        logger.info(f"convert_volume: no layers remain to process")


def main(arg_list: list[str]):
    parser = argparse.ArgumentParser(
        description="Convert volume .dat files to HDF5 artifacts."
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
        "--first_dat",
        help="File name of dat in first layer to be converted (omit to convert all layers)",
    )
    parser.add_argument(
        "--last_dat",
        help="File name of dat in last layer to be converted (omit to convert all layers)",
    )
    parser.add_argument(
        "--force",
        help="Convert all dat files even if converted result files already exist",
        action=argparse.BooleanOptionalAction
    )

    args = parser.parse_args(arg_list)

    convert_volume(volume_transfer_info=VolumeTransferInfo.parse_file(args.volume_transfer_info),
                   num_workers=args.num_workers,
                   parent_work_dir=args.parent_work_dir,
                   first_dat=args.first_dat,
                   last_dat=args.last_dat,
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
