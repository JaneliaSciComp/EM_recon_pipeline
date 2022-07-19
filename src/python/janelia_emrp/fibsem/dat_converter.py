import argparse
import datetime
import logging
import os
import traceback
from contextlib import ExitStack
from pathlib import Path
from typing import Optional, List

import dask.bag as dask_bag
import errno
import sys
from dask_janelia import get_cluster
from fibsem_tools.io import read

from janelia_emrp.fibsem.dat_path import DatPathsForLayer, split_into_layers
from janelia_emrp.fibsem.dat_to_h5_writer import DatToH5Writer
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

        logger.info(f"{self} convert_layer: entry, processing {len(dat_paths_for_layer.dat_paths)} dat files "
                    f"for {dat_paths_for_layer.get_layer_id()}")

        archive_path = None
        if raw_h5_root_path is not None:
            archive_path = dat_paths_for_layer.get_h5_path(raw_h5_root_path, source_type="raw")
            archive_path = self.setup_h5_path("archive", archive_path, self.skip_existing)

        align_path = None
        if align_h5_root_path is not None:
            align_path = dat_paths_for_layer.get_h5_path(align_h5_root_path, source_type="uint8")
            align_path = self.setup_h5_path("align source", align_path, self.skip_existing)

        with ExitStack() as stack:
            if archive_path:
                layer_archive_file = stack.enter_context(self.raw_writer.open_h5_file(str(archive_path)))
            if align_path:
                layer_align_file = stack.enter_context(self.align_writer.open_h5_file(str(align_path)))

            # TODO: clean-up properly if errors occur during conversion

            if archive_path or align_path:
                for dat_path in dat_paths_for_layer.dat_paths:

                    if not dat_path.file_path.exists():
                        raise FileNotFoundError(errno.ENOENT, os.strerror(errno.ENOENT), dat_path.file_path)

                    logger.info(f"{self} convert: reading {dat_path.file_path}")
                    dat_record = read(dat_path.file_path)

                    if archive_path:
                        self.raw_writer.create_and_add_archive_data_set(dat_path=dat_path,
                                                                        dat_header=dat_record.header,
                                                                        dat_record=dat_record,
                                                                        to_h5_file=layer_archive_file)

                    if align_path:
                        self.align_writer.create_and_add_mipmap_data_sets(
                            dat_path=dat_path,
                            dat_header=dat_record.header,
                            dat_record=dat_record,
                            max_mipmap_level=self.volume_transfer_info.max_mipmap_level,
                            to_h5_file=layer_align_file)

        if raw_h5_root_path is not None and \
                self.volume_transfer_info.includes_task(VolumeTransferTask.REMOVE_DAT_AFTER_H5_CONVERSION):
            # TODO: handle dat removal errors - probably want to just log issue and not disrupt other processing
            for dat_path in dat_paths_for_layer.dat_paths:
                logger.info(f"{self} convert: validation and removal of {dat_path.file_path} is TBD")
                # TODO: validate dat and h5 equivalence before removing dat
                # dat_path.file_path.unlink()

        logger.info(f"{self} convert: exit, converted {dat_paths_for_layer.get_layer_id()}")

    def convert_layer_list(self,
                           dat_layer_list: List[DatPathsForLayer]):
        """
        Converts specified `dat_layer_list` into HDF5 artifacts.

        Parameters
        ----------
        dat_layer_list : List[DatPathsForLayer]
            list of layers to convert
        """

        logger.info(f"{self} convert_layer_list: entry, processing {len(dat_layer_list)} layers")

        raw_h5_root = self.volume_transfer_info.get_raw_h5_root_for_conversion() if self.raw_writer else None
        align_h5_root = self.volume_transfer_info.get_align_h5_root_for_conversion() if self.align_writer else None

        for dat_paths_for_layer in dat_layer_list:
            self.convert_layer(dat_paths_for_layer=dat_paths_for_layer,
                               raw_h5_root_path=raw_h5_root,
                               align_h5_root_path=align_h5_root)

        logger.info(f"{self} convert_layer_list: exit")

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


def convert_volume(volume_transfer_info: VolumeTransferInfo,
                   num_workers: int,
                   num_threads_per_worker: int,
                   dask_worker_space: Optional[str],
                   min_index: Optional[int],
                   max_index: Optional[int],
                   skip_existing: bool):

    logger.info(f"convert_volume: entry, processing {volume_transfer_info} with {num_workers} worker(s)")

    dat_root = volume_transfer_info.get_dat_root_for_conversion()

    if dat_root is None:
        raise ValueError(f"dat root path is not defined in volume transfer info")
    if not dat_root.is_dir():
        raise ValueError(f"dat root path {dat_root} is not an accessible directory")

    logger.info(f"convert_volume: loading dat file paths ...")

    layers: list[DatPathsForLayer] = split_into_layers(path_list=[dat_root])

    logger.info(f"convert_volume: found {len(layers)} layers to convert")

    if skip_existing:
        logger.info(f"convert_volume: filtering out existing layers")
        new_layers = []
        raw_h5_root_path = volume_transfer_info.get_raw_h5_root_for_conversion()
        align_h5_root = volume_transfer_info.get_align_h5_root_for_conversion()
        for layer in layers:
            if not layer.h5_exists(h5_root_path=raw_h5_root_path, source_type="raw") and \
                    not layer.h5_exists(h5_root_path=align_h5_root, source_type="uint8"):
                new_layers.append(layer)
        if len(new_layers) < len(layers):
            layers = new_layers
            logger.info(f"convert_volume: after filtering, {len(layers)} remain to be converted")

    # ensure last layer is excluded from conversion
    layer_count_minus_one = len(layers) - 1
    slice_max = layer_count_minus_one if max_index is None else min(layer_count_minus_one, (max_index + 1))

    # unless acquisition has stopped and last dat file of last layer is not recently modified
    if len(layers) > 0 and volume_transfer_info.acquisition_stopped():
        one_hour_ago = datetime.datetime.now() - datetime.timedelta(hours=1)
        exclude_timestamp = datetime.datetime.timestamp(one_hour_ago)
        last_layer: DatPathsForLayer = layers[-1]
        last_dat: Path = last_layer.dat_paths[-1].file_path
        if (last_dat.stat().st_mtime <= exclude_timestamp) and (slice_max >= layer_count_minus_one):
            logger.info("convert_volume: including last layer because "
                        "acquisition stopped and last dat is not recently modified")
            slice_max = None

    if min_index:
        if slice_max:
            layers = layers[min_index:slice_max]
        else:
            layers = layers[min_index:]
    elif slice_max:
        layers = layers[0:slice_max]

    logger.info(f"convert_volume: {len(layers)} layers remain with index range {min_index}:{slice_max}")

    raw_writer = DatToH5Writer(chunk_shape=(2, 256, 256))
    align_writer = DatToH5Writer(chunk_shape=(1, 256, 256))

    converter = DatConverter(volume_transfer_info=volume_transfer_info,
                             raw_writer=raw_writer,
                             align_writer=align_writer,
                             skip_existing=skip_existing)

    if num_workers > 1:
        dask_cluster = get_cluster(threads_per_worker=num_threads_per_worker,
                                   local_kwargs={
                                       "local_directory": dask_worker_space
                                   })

        logger.info(f'convert_volume: observe dask cluster information at {dask_cluster.dashboard_link}')

        dask_cluster.scale(num_workers)
        logger.info(f'convert_volume: scaled dask cluster to {num_workers} workers')

        bag = dask_bag.from_sequence(layers, npartitions=num_workers)
        bag = bag.map_partitions(converter.convert_layer_list)
        bag.compute()

    else:
        converter.convert_layer_list(layers)


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
        "--num_threads_per_worker",
        help="The number of threads for each worker",
        type=int,
        default=1
    )
    parser.add_argument(
        "--dask_worker_space",
        help="Directory for Dask worker data",
    )
    parser.add_argument(
        "--min_index",
        help="Index of first layer to be converted",
        type=int
    )
    parser.add_argument(
        "--max_index",
        help="Index of last layer to be converted",
        type=int
    )
    parser.add_argument(
        "--force",
        help="Convert all dat files even if converted result files already exist",
        action=argparse.BooleanOptionalAction
    )

    args = parser.parse_args(arg_list)

    convert_volume(volume_transfer_info=VolumeTransferInfo.parse_file(args.volume_transfer_info),
                   num_workers=args.num_workers,
                   num_threads_per_worker=args.num_threads_per_worker,
                   dask_worker_space=args.dask_worker_space,
                   min_index=args.min_index,
                   max_index=args.max_index,
                   skip_existing=(not args.force))


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
