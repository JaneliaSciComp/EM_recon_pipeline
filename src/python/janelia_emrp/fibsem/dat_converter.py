import argparse
import logging
import os
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
from janelia_emrp.fibsem.volume_transfer_info import VolumeTransferInfo
from janelia_emrp.root_logger import init_logger

logger = logging.getLogger(__name__)


class DatConverter:
    """
    Converts .dat source data into HDF5 artifacts needed for archival storage and alignment.

    Attributes
    ----------
    archive_writer : Optional[DatToH5Writer], default=None
        writer for archive data, None if archive data should not be produced

    align_writer : Optional[DatToH5Writer], default=None
        writer for align data, None if align data should not be produced

    skip_existing : bool, default=True
        indicates whether existing HDF5 data should be left as is (True) or overwritten (False)
    """
    def __init__(self,
                 volume_transfer_info: VolumeTransferInfo,
                 archive_writer: Optional[DatToH5Writer] = None,
                 align_writer: Optional[DatToH5Writer] = None,
                 skip_existing: bool = True):
        self.volume_transfer_info = volume_transfer_info
        self.archive_writer = archive_writer
        self.align_writer = align_writer
        self.skip_existing = skip_existing

    def __str__(self):
        return f"{self.volume_transfer_info}"

    def convert_layer(self,
                      dat_paths_for_layer: DatPathsForLayer):
        """
        Converts specified `dat_paths_for_layer` sources into HDF5 artifacts.

        Parameters
        ----------
        dat_paths_for_layer : DatPathsForLayer
            paths of .dat source files in a single layer
        """

        logger.info(f"{self} convert_layer: entry, processing {len(dat_paths_for_layer.dat_paths)} dat files "
                    f"for {dat_paths_for_layer.get_layer_id()}")

        archive_conversion_requested = self.volume_transfer_info.archive_storage_root and self.archive_writer
        align_conversion_requested = self.volume_transfer_info.align_storage_root and self.align_writer

        archive_path = None
        if archive_conversion_requested:
            archive_path = dat_paths_for_layer.get_h5_path(self.volume_transfer_info.archive_storage_root,
                                                           source_type="raw")
            archive_path = self.setup_h5_path("archive", archive_path, self.skip_existing)

        align_path = None
        if align_conversion_requested:
            align_path = dat_paths_for_layer.get_h5_path(self.volume_transfer_info.align_storage_root,
                                                         source_type="uint8")
            align_path = self.setup_h5_path("align source", align_path, self.skip_existing)

        with ExitStack() as stack:
            if archive_path:
                layer_archive_file = stack.enter_context(self.archive_writer.open_h5_file(str(archive_path)))
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
                        self.archive_writer.create_and_add_archive_data_set(dat_path=dat_path,
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

        if self.volume_transfer_info.remove_dat_after_archive:
            # TODO: handle dat removal errors - probably want to just log issue and not disrupt other processing
            for dat_path in dat_paths_for_layer.dat_paths:
                logger.info(f"{self} convert: removing {dat_path.file_path}")
                dat_path.file_path.unlink()

        logger.info(f"{self} convert: exit")

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

        for dat_paths_for_layer in dat_layer_list:
            self.convert_layer(dat_paths_for_layer)

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
                   dask_worker_space: Optional[str] = None,
                   min_index: Optional[int] = None,
                   max_index: Optional[int] = None):

    logger.info(f"convert_volume: entry, processing {volume_transfer_info} with {num_workers} worker(s)")
    logger.info(f"convert_volume: loading dat file paths ...")

    layers = split_into_layers(volume_transfer_info.dat_storage_roots)

    logger.info(f"convert_volume: found {len(layers)} layers")

    slice_max = max_index + 1 if max_index else None

    if min_index:
        if slice_max:
            layers = layers[min_index:slice_max]
        else:
            layers = layers[min_index:]
    elif slice_max:
        layers = layers[0:slice_max]

    logger.info(f"convert_volume: {len(layers)} layers remain with index range {min_index}:{slice_max}")

    archive_writer = DatToH5Writer(chunk_shape=(2, 256, 256))
    align_writer = DatToH5Writer(chunk_shape=(1, 256, 256))
    skip_existing = True

    converter = DatConverter(volume_transfer_info=volume_transfer_info,
                             archive_writer=archive_writer,
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


def main():
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

    args = parser.parse_args(sys.argv[1:])

    convert_volume(volume_transfer_info=VolumeTransferInfo.parse_file(args.volume_transfer_info),
                   num_workers=args.num_workers,
                   num_threads_per_worker=args.num_threads_per_worker,
                   dask_worker_space=args.dask_worker_space,
                   min_index=args.min_index,
                   max_index=args.max_index)


if __name__ == "__main__":
    # NOTE: to fix module not found errors, export PYTHONPATH="/.../EM_recon_pipeline/src/python"

    init_logger(__file__)
    main()
