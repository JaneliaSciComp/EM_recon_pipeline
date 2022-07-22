import argparse
import logging
import os
import traceback

import sys
from pathlib import Path
from typing import Dict, Any, Optional, Tuple, Union, Final

import h5py
import numpy as np
from fibsem_tools.io import read
from fibsem_tools.io.fibsem import OFFSET, MAGIC_NUMBER
from h5py import Dataset, Group
from xarray_multiscale import multiscale
from xarray_multiscale.reducers import windowed_mean

from janelia_emrp.fibsem.dat_path import split_into_layers, DatPath
from janelia_emrp.fibsem.dat_to_scheffer_8_bit import compress_compute
from janelia_emrp.root_logger import init_logger

logger = logging.getLogger(__name__)


DAT_FILE_NAME_KEY: Final = "dat_file_name"
ELEMENT_SIZE_UM_KEY: Final = "element_size_um"
FILE_LENGTH_KEY: Final = "FileLength"
RAW_HEADER_KEY: Final = "raw_header"
RECIPE_KEY: Final = "recipe"


class DatToH5Writer:
    """
    Writer to convert FIB-SEM dat file data (and derivatives) into HDF5 format data sets.

    Attributes
    ----------
    chunk_shape : Union[tuple[int], bool, None]
        Chunk shape, or True to enable auto-chunking.

    compression : Union[str, int, None], default="gzip"
        Compression strategy.  Legal values are 'gzip', 'szip', 'lzf'.
        If an integer in range(10), this indicates gzip compression level.
        Otherwise, an integer indicates the number of a dynamically loaded compression filter.

    compression_opts : Optional[Any]
        Compression settings.
        This is an integer for gzip, 2-tuple for szip, etc.
        If specifying a dynamically loaded compression filter number, this must be a tuple of values.

    driver : Optional[str]
        Name of the driver to use.
        Legal values are None (default, recommended), 'core', 'sec2', 'stdio', 'mpio', 'ros3'.
    """
    def __init__(self,
                 chunk_shape: Union[Tuple[int, ...], bool, None],
                 compression: Union[str, int, None] = "gzip",
                 compression_opts: Optional[Any] = None,
                 driver: Optional[str] = None):
        self.chunk_shape = chunk_shape
        self.compression = compression
        self.compression_opts = compression_opts
        self.driver = driver

    def open_h5_file(self,
                     output_path: str,
                     mode: str = "x") -> h5py.File:
        return h5py.File(name=output_path, mode=mode, driver=self.driver)

    def create_and_add_data_set(self,
                                data_set_name: str,
                                pixel_array: np.ndarray,
                                to_h5_file: h5py.File,
                                group_name: Optional[str] = None) -> Dataset:
        """
        Creates a new data set and adds it to the `to_h5_file`.

        Parameters
        ----------
        data_set_name : str
            name for the data set.

        pixel_array : np.ndarray
            pixel array for data set.

        to_h5_file : h5py.File
            HDF5 container for data set.

        group_name : Optional[str]
            name for the group or None to use the file's root group.

        Returns
        -------
        Dataset
            The created data set.
        """
        logger.info(f"create_and_add_data_set: entry, adding {data_set_name} "
                    f"to group {group_name} in {to_h5_file.filename}")

        valid_chunks = build_safe_chunk_shape(self.chunk_shape, pixel_array.shape)

        if group_name is None:
            group = to_h5_file
        else:
            group = to_h5_file.require_group(group_name)

        if data_set_name in group:
            logger.info(f"create_and_add_data_set: removing old {data_set_name} "
                        f"from group {group_name} in {to_h5_file.filename}")
            del group[data_set_name]

        return group.create_dataset(name=data_set_name,
                                    data=pixel_array[:],
                                    chunks=valid_chunks,
                                    compression=self.compression,
                                    compression_opts=self.compression_opts)

    def create_and_add_raw_data_set(self,
                                    dat_path: DatPath,
                                    dat_header: Dict[str, Any],
                                    dat_record: np.ndarray,
                                    to_h5_file: h5py.File):
        data_set = self.create_and_add_data_set(data_set_name=dat_path.tile_key(),
                                                pixel_array=dat_record,
                                                to_h5_file=to_h5_file)
        add_dat_header_attributes(dat_file_path=dat_path.file_path,
                                  dat_header=dat_header,
                                  include_raw_header_and_recipe=True,
                                  to_group_or_dataset=data_set)
        add_element_size_um_attributes(dat_header=dat_header,
                                       z_nm_per_pixel=None,
                                       to_dataset=data_set)
        return data_set

    def create_and_add_mipmap_data_sets(self,
                                        dat_path: DatPath,
                                        dat_header: Dict[str, Any],
                                        dat_record: np.ndarray,
                                        max_mipmap_level: Optional[int],
                                        to_h5_file: h5py.File):
        """
        Compresses the specified `dat_record` into an 8 bit level 0 mipmap and down-samples that for subsequent levels.
        The `align_writer` is used to save each mipmap as a data set within the specified `layer_align_file`.
        Data sets are named as <section>-<row>-<column>.mipmap.<level> (e.g. 0-0-1.mipmap.3).
        """
        func_name = "create_and_add_mipmap_data_sets:"
        layer_and_tile = dat_path.layer_and_tile()
        logger.info(f"{func_name} create level 0 by compressing {dat_path.file_path} for {layer_and_tile}")

        compressed_record = compress_compute(dat_record)

        tile_key = dat_path.tile_key()
        level_zero_data_set = self.create_and_add_data_set(group_name=tile_key,
                                                           data_set_name="mipmap.0",
                                                           pixel_array=compressed_record,
                                                           to_h5_file=to_h5_file)
        group = level_zero_data_set.parent

        add_dat_header_attributes(dat_file_path=dat_path.file_path,
                                  dat_header=dat_header,
                                  include_raw_header_and_recipe=False,
                                  to_group_or_dataset=group)

        # TODO: review maintenance of element_size_um attribute for ImageJ, do we need it?
        scaled_element_size = add_element_size_um_attributes(dat_header=dat_header,
                                                             z_nm_per_pixel=None,
                                                             to_dataset=level_zero_data_set)

        if max_mipmap_level is not None:
            lazy_mipmaps = multiscale(compressed_record, windowed_mean, (1, 2, 2))
            actual_max_mipmap_level = len(lazy_mipmaps) - 1
            derived_max_mipmap_level = min(max_mipmap_level, actual_max_mipmap_level)

            for mipmap_level in range(1, derived_max_mipmap_level + 1):

                logger.info(f"{func_name} create level {mipmap_level} for {layer_and_tile}")

                scaled_bytes = lazy_mipmaps[mipmap_level].to_numpy()
                level_data_set = self.create_and_add_data_set(group_name=tile_key,
                                                              data_set_name=f"mipmap.{mipmap_level}",
                                                              pixel_array=scaled_bytes,
                                                              to_h5_file=to_h5_file)

                scaled_element_size = [
                    scaled_element_size[0], scaled_element_size[1] * 2.0, scaled_element_size[2] * 2.0
                ]
                level_data_set.attrs["element_size_um"] = scaled_element_size

        logger.info(f"{func_name} exit for {layer_and_tile}")


def add_dat_header_attributes(dat_file_path: Path,
                              dat_header: Dict[str, Any],
                              include_raw_header_and_recipe: bool,
                              to_group_or_dataset: [Group, Dataset]) -> None:
    """
    Adds header data to the specified group or dataset.

    Parameters
    ----------
    dat_file_path : Path
        path of source .dat file or None to skip storing RawHeader data as an attribute.

    dat_header : Dict[str, Any]
        parsed header information from .dat file to include as attributes.

    include_raw_header_and_recipe : bool
        indicates whether to store raw header and recipe data as attributes.

    to_group_or_dataset : [Group, Dataset]
        container for the header attributes.
    """
    for key, value in dat_header.__dict__.items():
        try:
            to_group_or_dataset.attrs[key] = value
        except ValueError as valueError:
            logger.warning(f"add_dat_header_attributes: skipping value for key='{key}' in {dat_file_path}",
                           exc_info=valueError)

    to_group_or_dataset.attrs[DAT_FILE_NAME_KEY] = str(dat_file_path.name)

    if include_raw_header_and_recipe:
        source_size = os.path.getsize(dat_file_path)
        with open(dat_file_path, "rb") as raw_file:
            raw_bytes = raw_file.read(OFFSET)

            assert np.frombuffer(raw_bytes, '>u4', count=1)[0] == MAGIC_NUMBER
            to_group_or_dataset.attrs[RAW_HEADER_KEY] = np.frombuffer(raw_bytes, dtype='u1')

            file_length = to_group_or_dataset.attrs[FILE_LENGTH_KEY]
            raw_file.seek(file_length)
            recipe_size = source_size - file_length
            to_group_or_dataset.attrs[RECIPE_KEY] = bytearray(raw_file.read(recipe_size))


def build_safe_chunk_shape(hdf5_writer_chunks: Union[Tuple[int, ...], bool, None],
                           data_shape: Tuple[int, ...]) -> Union[Tuple[int, ...], bool, None]:
    """
    HDF5 chunk shape must not be larger than a volume's shape.
    This function reduces a writer's chunk shape if it is too large in any dimension.

    Returns
    -------
    Union[Tuple[int, ...], bool, None]
        a chunk shape that can be safely used when writing data or None if the writer is not configured to chunk.
    """
    safe_shape = hdf5_writer_chunks

    if hdf5_writer_chunks and not isinstance(hdf5_writer_chunks, bool):
        safe_shape_list = []

        for dimension in range(0, len(data_shape)):
            if dimension < len(hdf5_writer_chunks):
                if hdf5_writer_chunks[dimension] <= data_shape[dimension]:
                    safe_shape_list.append(hdf5_writer_chunks[dimension])
                else:
                    logger.info(f"build_safe_chunk_shape: overriding dimension {dimension} "
                                f"chunk size {hdf5_writer_chunks[dimension]} with {data_shape[dimension]}")
                    safe_shape_list.append(data_shape[dimension])
            else:
                safe_shape_list.append(data_shape[dimension])
                logger.info(f"build_safe_chunk_shape: adding dimension {dimension} chunk size {data_shape[dimension]}")

        safe_shape = tuple(safe_shape_list) if len(safe_shape_list) > 0 else None

    return safe_shape


# TODO: remove or fix element_size_um attribute if/when ImageJ plug-in is updated
def add_element_size_um_attributes(dat_header: Dict[str, Any],
                                   z_nm_per_pixel: Optional[int],
                                   to_dataset: Dataset) -> list[float]:
    """
    Adds element_size_um attribute to supress error messages when loading HDF5 archives in ImageJ.

    From https://lmb.informatik.uni-freiburg.de/resources/opensource/imagej_plugins/hdf5.html
    The (ImageJ) HDF5 plugin saves and loads the pixel/voxel size in
    micrometer of the image in the attribute "element_size_um".
    It has always 3 components in the order z,y,x (accordingly to the c-style indexing).

    Parameters
    ----------
    dat_header : Dict[str, Any]
        header dict.

    z_nm_per_pixel: Optional[int]
        nm per pixel for z dimension or None if unknown.

    to_dataset : Dataset
        data set to modify.

    Returns
    -------
    list[float]
        the element_size_um values.
    """
    nm_per_pixel = int(float(dat_header.__dict__["PixelSize"]) + 0.5)
    um_per_pixel = nm_per_pixel / 1000.0

    # for 2D data, specify z as -1 because Davis agrees that -1 is more impossible than 0
    z_um_per_pixel = z_nm_per_pixel / 1000.0 if z_nm_per_pixel else -1

    element_size_um = [z_um_per_pixel, um_per_pixel, um_per_pixel]
    to_dataset.attrs[ELEMENT_SIZE_UM_KEY] = element_size_um

    return element_size_um


def main(arg_list: list[str]):
    parser = argparse.ArgumentParser(
        description="Converts dat files to HDF5 files."
    )
    parser.add_argument(
        "--dat_path",
        help="Path(s) of source dat file(s)",
        required=True,
        nargs='+'
    )
    parser.add_argument(
        "--h5_parent_path",
        help="Path of parent directory for h5 files",
        required=True,
    )

    args = parser.parse_args(arg_list)

    h5_root_path = Path(args.h5_parent_path)
    archive_writer = DatToH5Writer(chunk_shape=None)

    layers = split_into_layers(path_list=[Path(p) for p in args.dat_path])

    logger.info(f"found {len(layers)} layers")

    for layer in layers:

        archive_path = layer.get_h5_path(h5_root_path=h5_root_path,
                                         append_acquisition_based_subdirectories=False,
                                         source_type="raw")

        with archive_writer.open_h5_file(str(archive_path)) as layer_archive_file:
            for dat_path in layer.dat_paths:
                logger.info(f"reading {dat_path.file_path}")
                dat_record = read(dat_path.file_path)

                archive_writer.create_and_add_raw_data_set(dat_path=dat_path,
                                                           dat_header=dat_record.header,
                                                           dat_record=dat_record,
                                                           to_h5_file=layer_archive_file)


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
