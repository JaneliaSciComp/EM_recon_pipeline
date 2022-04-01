import argparse
import logging
import sys
from datetime import datetime
from pathlib import Path
from typing import Optional

import dask.bag as db
from dask_janelia import get_cluster

from janelia_emrp.fibsem.dat_converter import DatConverter
from janelia_emrp.fibsem.dat_path import split_into_layers
from janelia_emrp.fibsem.dat_to_h5_writer import DatToH5Writer
from janelia_emrp.fibsem.volume_transfer_info import VolumeTransferInfo

root_logger = logging.getLogger()
c_handler = logging.StreamHandler(sys.stdout)
c_formatter = logging.Formatter("%(asctime)s [%(threadName)s] [%(name)s] [%(levelname)s] %(message)s")
c_handler.setFormatter(c_formatter)
root_logger.addHandler(c_handler)
root_logger.setLevel(logging.INFO)


def test_derive_max_mipmap_level():
    volume_transfer_info = VolumeTransferInfo(
        scope="jeiss3.hhmi.org",
        scope_storage_root=Path("/cygdrive/e/Images/Fly Brain"),
        dat_storage_root=Path("/Volumes/flyem2/data/Z0720-07m_BR_Sec18/dat"),
        acquire_start=datetime.strptime("21-05-05_102654", "%y-%m-%d_%H%M%S"),
        acquire_stop=datetime.strptime("21-06-09_131555", "%y-%m-%d_%H%M%S"),
        archive_storage_root=Path("/Users/trautmane/Desktop/fibsem-tests/archive"),
        remove_dat_after_archive=False,
        align_storage_root=Path("/Users/trautmane/Desktop/fibsem-tests/align"),
        max_mipmap_level=7,
        render_owner="Z0720_07m_BR",
        render_project="Sec18"
    )
    converter = DatConverter(volume_transfer_info)
    assert 3 == converter.derive_max_mipmap_level(3), "actual mipmap level should be selected"
    assert 7 == converter.derive_max_mipmap_level(12), "volume max mipmap level should be selected"


def convert_volume(volume_transfer_info: VolumeTransferInfo,
                   num_workers: int,
                   num_threads_per_worker: int,
                   dask_worker_space: Optional[str] = None,
                   min_index: Optional[int] = None,
                   max_index: Optional[int] = None):

    root_logger.info(f"convert_volume: entry, processing {volume_transfer_info} with {num_workers} worker(s)")
    root_logger.info(f"convert_volume: loading dat file paths ...")

    dat_file_paths = [volume_transfer_info.dat_storage_root]
    layers = split_into_layers(dat_file_paths)

    root_logger.info(f"convert_volume: found {len(layers)} layers")

    slice_max = max_index + 1 if max_index else None

    if min_index:
        if slice_max:
            layers = layers[min_index:slice_max]
        else:
            layers = layers[min_index:]
    elif slice_max:
        layers = layers[0:slice_max]

    root_logger.info(f"convert_volume: {len(layers)} layers remain with index range {min_index}:{slice_max}")

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

        root_logger.info(f'observe dask cluster information at {dask_cluster.dashboard_link}')

        dask_cluster.scale(num_workers)
        root_logger.info(f'scaled dask cluster to {num_workers} workers')

        bag = db.from_sequence(layers, npartitions=num_workers)
        bag = bag.map_partitions(converter.convert_layer)
        bag.compute()

    else:
        converter.convert_layer_list(layers)


if __name__ == "__main__":
    # NOTE: to fix module not found errors, export PYTHONPATH="/.../EM_recon_pipeline/src/python"
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
