import errno
import logging
from contextlib import ExitStack
from pathlib import Path
from typing import Optional, List, Dict, Any

import numpy as np
import os
from fibsem_tools.io import read
from h5py import File
from xarray_multiscale import multiscale
from xarray_multiscale.reducers import windowed_mean

from janelia_emrp.fibsem.dat_path import DatPathsForLayer, DatPath
from janelia_emrp.fibsem.dat_to_h5_writer import DatToH5Writer
from janelia_emrp.fibsem.dat_to_scheffer_8_bit import compress_compute
from janelia_emrp.fibsem.volume_transfer_info import VolumeTransferInfo

logger = logging.getLogger("dat_converter")


class DatConverter:
    """
    Converts .dat source data into HDF5 artifacts needed for archival storage and alignment.
    """
    def __init__(self, volume_transfer_info: VolumeTransferInfo):
        self.volume_transfer_info = volume_transfer_info

    def __str__(self):
        return f"{self.volume_transfer_info}"

    def convert(self,
                dat_layers: List[DatPathsForLayer],
                archive_writer: Optional[DatToH5Writer],
                align_writer: Optional[DatToH5Writer],
                skip_existing: bool = True):
        """
        Converts specified `dat_layers` into HDF5 artifacts.

        Parameters
        ----------
        dat_layers : List[DatPathsForLayer]
            list of layers to convert

        archive_writer : Optional[DatToH5Writer]
            writer for archive data, None if archive data should not be produced

        align_writer : Optional[DatToH5Writer]
            writer for align data, None if align data should not be produced

        skip_existing : bool, default=True
            indicates whether existing HDF5 data should be left as is (True) or overwritten (False)
        """

        logger.info(f"{self} convert: entry, processing {len(dat_layers)} layers")

        archive_conversion_requested = self.volume_transfer_info.archive_storage_root and archive_writer
        align_conversion_requested = self.volume_transfer_info.align_storage_root and align_writer

        for dat_paths_for_layer in dat_layers:

            archive_path = None
            if archive_conversion_requested:
                archive_path = dat_paths_for_layer.get_h5_path(self.volume_transfer_info.archive_storage_root,
                                                               source_type="raw")
                archive_path = self.setup_h5_path("archive", archive_path, skip_existing)

            align_path = None
            if align_conversion_requested:
                align_path = dat_paths_for_layer.get_h5_path(self.volume_transfer_info.align_storage_root,
                                                             source_type="uint8")
                align_path = self.setup_h5_path("align source", align_path, skip_existing)

            with ExitStack() as stack:
                if archive_path:
                    layer_archive_file = stack.enter_context(archive_writer.open_h5_file(str(archive_path)))
                if align_path:
                    layer_align_file = stack.enter_context(align_writer.open_h5_file(str(align_path)))

                # TODO: clean-up properly if errors occur during conversion

                if archive_path or align_path:
                    for dat_path in dat_paths_for_layer.dat_paths:

                        if not dat_path.file_path.exists():
                            raise FileNotFoundError(errno.ENOENT, os.strerror(errno.ENOENT), dat_path.file_path)

                        logger.info(f"{self} convert: reading {dat_path.file_path}")
                        dat_record = read(dat_path.file_path)

                        if archive_path:
                            archive_writer.create_and_add_data_set(data_set_name=dat_path.tile_key(),
                                                                   dat_header=dat_record.header,
                                                                   pixel_array=dat_record,
                                                                   to_h5_file=layer_archive_file,
                                                                   dat_file_path_for_raw_header=dat_path.file_path)

                        if align_path:
                            self.create_and_add_mipmap_data_sets(dat_path=dat_path,
                                                                 dat_header=dat_record.header,
                                                                 dat_record=dat_record,
                                                                 align_writer=align_writer,
                                                                 layer_align_file=layer_align_file)

            if self.volume_transfer_info.remove_dat_after_archive:
                # TODO: handle dat removal errors - probably want to just log issue and not disrupt other processing
                for dat_path in dat_paths_for_layer.dat_paths:
                    logger.info(f"{self} convert: removing {dat_path.file_path}")
                    dat_path.file_path.unlink()

        logger.info(f"{self} convert: exit")

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

    def derive_max_mipmap_level(self,
                                actual_max_mipmap_level: int) -> int:
        """
        Returns
        -------
        int
            The actual mipmap level or a reduced value as needed
        """
        if self.volume_transfer_info.max_mipmap_level:
            derived_max = min(self.volume_transfer_info.max_mipmap_level, actual_max_mipmap_level)
        else:
            derived_max = actual_max_mipmap_level
        return derived_max

    def create_and_add_mipmap_data_sets(self,
                                        dat_path: DatPath,
                                        dat_header: Dict[str, Any],
                                        dat_record: np.ndarray,
                                        align_writer: DatToH5Writer,
                                        layer_align_file: File):
        """
        Compresses the specified `dat_record` into an 8 bit level 0 mipmap and down-samples that for subsequent levels.
        The `align_writer` is used to save each mipmap as a data set within the specified `layer_align_file`.
        Data sets are named as <section>-<row>-<column>.mipmap.<level> (e.g. 0-0-1.mipmap.3).
        """

        logger.info(f"{self} create_and_add_mipmap_data_sets: compressing {dat_path.file_path}")

        compressed_record = compress_compute(dat_record)

        tile_key = dat_path.tile_key()
        level_zero_data_set = align_writer.create_and_add_data_set(data_set_name=f"{tile_key}.mipmap.0",
                                                                   dat_header=dat_header,
                                                                   pixel_array=compressed_record,
                                                                   to_h5_file=layer_align_file)

        # TODO: review maintenance of element_size_um attribute for ImageJ, do we need it?
        scaled_element_size = level_zero_data_set.attrs["element_size_um"]

        lazy_mipmaps = multiscale(compressed_record, windowed_mean, (1, 2, 2))

        max_level = self.derive_max_mipmap_level(actual_max_mipmap_level=len(lazy_mipmaps))

        for mipmap_level in range(1, max_level + 1):

            logger.info(f"{self} create_and_add_mipmap_data_sets: create level {mipmap_level}")

            scaled_bytes = lazy_mipmaps[mipmap_level].to_numpy()
            level_data_set = align_writer.create_and_add_data_set(
                data_set_name=f"{tile_key}.mipmap.{mipmap_level}",
                dat_header=None,
                pixel_array=scaled_bytes,
                to_h5_file=layer_align_file)

            scaled_element_size = [
                scaled_element_size[0], scaled_element_size[1] * 2.0, scaled_element_size[2] * 2.0
            ]
            level_data_set.attrs["element_size_um"] = scaled_element_size

        logger.info(f"{self} create_and_add_mipmap_data_sets: exit")
