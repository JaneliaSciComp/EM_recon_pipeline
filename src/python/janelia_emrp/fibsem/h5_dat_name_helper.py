import logging
from pathlib import Path
from typing import Optional

import dask.bag as dask_bag
from distributed import LocalCluster

from janelia_emrp.fibsem.dat_path import new_dat_path, new_dat_layer, DatPathsForLayer
from janelia_emrp.fibsem.dat_to_h5_writer import get_dat_file_names_for_h5

logger = logging.getLogger(__name__)


class H5DatNameHelper:
    """
    Helper for retrieving/parsing source dat names from HDF5 attributes.
    Optionally wraps a local dask cluster that can be used to speed up
    reads from slow filesystems by executing the reads in parallel.

    Attributes
    ----------
    num_workers :  Optional[int]
        number of workers for dask parallelization (specify None or 1 to skip Dask usage)
    dask_local_dir : Optional[str]
        parent directory for dask work area
    """
    def __init__(self,
                 num_workers: Optional[int],
                 dask_local_dir: Optional[str]):
        self.num_workers = num_workers
        self.dask_local_dir = dask_local_dir
        self.dask_cluster = None

    def __enter__(self):
        if self.num_workers is not None and self.num_workers > 1:
            self.dask_cluster = LocalCluster(
                n_workers=self.num_workers, threads_per_worker=1, local_directory=self.dask_local_dir
            )
            logger.info(f'observe dask cluster information at {self.dask_cluster.dashboard_link}')

    def __exit__(self, typ, value, traceback):
        if self.dask_cluster is not None:
            self.dask_cluster.__exit__(typ, value, traceback)

    def names_for_day(self,
                      layer_for_day: DatPathsForLayer,
                      h5_root_path: Path,
                      source_type: str) -> list[str]:

        # /groups/.../raw/Merlin-6282/2022/10/17/04/Merlin-6282_22-10-17_040352.raw.h5
        # /nearline/.../raw/Merlin-6282/2022/10/17/04/Merlin-6282_22-10-17_040352.raw-archive.h5
        first_h5_path = layer_for_day.get_h5_path(h5_root_path=h5_root_path,
                                                  append_acquisition_based_subdirectories=True,
                                                  source_type=source_type)
        # /groups/.../raw/Merlin-6282/2022/10/17
        # /nearline/.../raw/Merlin-6282/2022/10/17
        h5_day_dir = first_h5_path.parent.parent

        logger.info(f"names_for_day: checking {h5_day_dir}")

        dat_list = []
        h5_list = h5_day_dir.glob("**/*.h5")
        
        if self.dask_cluster is None:
            for h5_path in h5_list:
                dat_list.extend(get_dat_file_names_for_h5(h5_path))
        else:
            h5_path_bag = dask_bag.from_sequence(h5_list)
            list_of_dat_name_lists_bag = h5_path_bag.map(get_dat_file_names_for_h5, h5_path_bag)
            dat_name_list_bag = list_of_dat_name_lists_bag.flatten()
            dat_list = self.dask_cluster.compute(dat_name_list_bag, sync=True)

        return dat_list

    def raw_names_for_day(self,
                          scope_dat_paths: list[Path],
                          raw_h5_archive_root: Path,
                          raw_h5_cluster_root: Path) -> list[str]:
        h5_dat_names_for_day = []
        if len(scope_dat_paths) > 0:
            first_dat_path = new_dat_path(scope_dat_paths[0])
            first_dat_layer = new_dat_layer(first_dat_path)
            if raw_h5_archive_root is not None:
                h5_dat_names_for_day.extend(self.names_for_day(layer_for_day=first_dat_layer,
                                                               h5_root_path=raw_h5_archive_root,
                                                               source_type="raw"))
            if raw_h5_cluster_root is not None:
                h5_dat_names_for_day.extend(self.names_for_day(layer_for_day=first_dat_layer,
                                                               h5_root_path=raw_h5_cluster_root,
                                                               source_type="raw"))
        return h5_dat_names_for_day
