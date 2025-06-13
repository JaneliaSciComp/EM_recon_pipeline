import argparse
import logging
import os
import time
import traceback
from pathlib import Path
from typing import Any, Optional, Tuple, Union, Final

import h5py
import numpy as np
import sys
from fibsem_tools.io.fibsem import OFFSET, MAGIC_NUMBER
from h5py import Dataset, Group
from xarray_multiscale import multiscale
from xarray_multiscale.reducers import windowed_mean

from janelia_emrp.fibsem.cyx_dat import CYXDat, new_cyx_dat
from janelia_emrp.fibsem.dat_path import split_into_layers
from janelia_emrp.fibsem.dat_to_scheffer_8_bit_layer import compress_compute_layer, FillInfo
from janelia_emrp.root_logger import init_logger

logger = logging.getLogger(__name__)


CHANNEL_DATA_SET_NAMES_KEY: Final = "channel_data_set_names"
DAT_FILE_NAME_KEY: Final = "dat_file_name"
ELEMENT_SIZE_UM_KEY: Final = "element_size_um"
RAW_HEADER_DATASET_NAME: Final = "header"
RAW_FOOTER_DATASET_NAME: Final = "footer"


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
        logger.info(f"create_and_add_data_set: entry, adding {data_set_name} data set with shape {pixel_array.shape} "
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

    def create_and_add_raw_data_group(self,
                                      cyx_dat: CYXDat,
                                      to_h5_file: h5py.File):
        raw_data_group_name = cyx_dat.dat_path.tile_key()
        group_context = f"group {raw_data_group_name} in {to_h5_file.filename}"

        logger.info(f"create_and_add_raw_data_group: entry, creating {group_context}")
        raw_data_group = to_h5_file.require_group(raw_data_group_name)

        add_dat_header_attributes(cyx_dat=cyx_dat,
                                  to_group_or_dataset=raw_data_group)

        channel_data_set_names = []
        number_of_channels = cyx_dat.pixels.shape[0]
        for channel_index in range(number_of_channels):
            channel_data_set_name = f"c{channel_index}"
            channel_data_set_names.append(channel_data_set_name)
            channel_pixels_data_set = self.create_and_add_data_set(
                group_name=raw_data_group_name,
                data_set_name=channel_data_set_name,
                pixel_array=cyx_dat.pixels[channel_index, :, :],
                to_h5_file=to_h5_file)

            add_element_size_um_attributes(dat_header_dict=cyx_dat.header,
                                           z_nm_per_pixel=None,
                                           to_dataset=channel_pixels_data_set)

        raw_data_group.attrs[CHANNEL_DATA_SET_NAMES_KEY] = channel_data_set_names

        data_set_names = f"{RAW_HEADER_DATASET_NAME} and {RAW_FOOTER_DATASET_NAME}"
        logger.info(f"create_and_add_raw_data_group: adding {data_set_names} to {group_context}")

        source_size = os.path.getsize(cyx_dat.dat_path.file_path)
        with open(cyx_dat.dat_path.file_path, "rb") as raw_file:
            raw_header_bytes = raw_file.read(OFFSET)

            assert np.frombuffer(raw_header_bytes, '>u4', count=1)[0] == MAGIC_NUMBER

            raw_data_group.create_dataset(name=RAW_HEADER_DATASET_NAME,
                                          data=np.frombuffer(raw_header_bytes, dtype='u1'),
                                          chunks=None,
                                          compression=self.compression,
                                          compression_opts=self.compression_opts)

            footer_start = OFFSET + cyx_dat.pixels.nbytes
            raw_file.seek(footer_start)
            footer_size = source_size - footer_start
            raw_data_group.create_dataset(name=RAW_FOOTER_DATASET_NAME,
                                          data=bytearray(raw_file.read(footer_size)),
                                          chunks=None,
                                          compression=self.compression,
                                          compression_opts=self.compression_opts)

    def create_and_add_mipmap_data_sets(self,
                                        cyx_dat_list: list[CYXDat],
                                        max_mipmap_level: Optional[int],
                                        to_h5_file: h5py.File,
                                        fill_info: Optional[FillInfo]):
        """
        Compresses the specified dat into an 8 bit level 0 mipmap and down-samples that for subsequent levels.
        The `align_writer` is used to save each mipmap as a data set within the specified `layer_align_file`.
        Data sets are named as <section>-<row>-<column>.mipmap.<level> (e.g. 0-0-1.mipmap.3).
        """
        func_name = "create_and_add_mipmap_data_sets:"

        if len(cyx_dat_list) == 0:
            raise ValueError("empty cyx_dat_list provided")

        cyx_dat_pixels_list: list[np.ndarray] = []
        for cyx_dat in cyx_dat_list:
            layer_and_tile = cyx_dat.dat_path.layer_and_tile()
            logger.info(f"{func_name} add pixels from {cyx_dat} for {layer_and_tile}")
            cyx_dat_pixels_list.append(cyx_dat.pixels)

        logger.info(f"{func_name} create level 0")
        compressed_record_list = compress_compute_layer(cyx_dat_pixels_list,
                                                        channel_num=0,
                                                        fill_info=fill_info)

        for index, cyx_dat in enumerate(cyx_dat_list):
            compressed_record = compressed_record_list[index]

            tile_key = cyx_dat.dat_path.tile_key()
            level_zero_data_set = self.create_and_add_data_set(group_name=tile_key,
                                                               data_set_name="mipmap.0",
                                                               pixel_array=compressed_record,
                                                               to_h5_file=to_h5_file)
            group = level_zero_data_set.parent

            add_dat_header_attributes(cyx_dat=cyx_dat,
                                      to_group_or_dataset=group)

            scaled_element_size = add_element_size_um_attributes(dat_header_dict=cyx_dat.header,
                                                                 z_nm_per_pixel=None,
                                                                 to_dataset=level_zero_data_set)

            if max_mipmap_level is not None:
                layer_and_tile = cyx_dat.dat_path.layer_and_tile()
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

        logger.info(f"{func_name} exit for layer {cyx_dat_list[0].dat_path.layer_id}")


def add_dat_header_attributes(cyx_dat: CYXDat,
                              to_group_or_dataset: [Group, Dataset]) -> None:
    """
    Adds header data to the specified group or dataset.

    Parameters
    ----------
    cyx_dat : CYXDat
        parsed dat file information.

    to_group_or_dataset : [Group, Dataset]
        container for the header attributes.
    """
    for key, value in cyx_dat.header.items():
        try:
            to_group_or_dataset.attrs[key] = value
        except ValueError as valueError:
            logger.warning(f"add_dat_header_attributes: skipping value for key='{key}' in {cyx_dat}",
                           exc_info=valueError)

    to_group_or_dataset.attrs[DAT_FILE_NAME_KEY] = cyx_dat.dat_path.file_path.name


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

        for dimension, shape in enumerate(data_shape):
            if dimension < len(hdf5_writer_chunks):
                if hdf5_writer_chunks[dimension] <= shape:
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
def add_element_size_um_attributes(dat_header_dict: dict[str, Any],
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
    dat_header_dict : dict[str, Any]
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
    nm_per_pixel = int(float(dat_header_dict["PixelSize"]) + 0.5)
    um_per_pixel = nm_per_pixel / 1000.0

    # for 2D data, specify z as -1 because Davis agrees that -1 is more impossible than 0
    z_um_per_pixel = z_nm_per_pixel / 1000.0 if z_nm_per_pixel else -1

    element_size_um = [z_um_per_pixel, um_per_pixel, um_per_pixel]
    to_dataset.attrs[ELEMENT_SIZE_UM_KEY] = element_size_um

    return element_size_um


def get_dat_file_names_for_h5(h5_path: Path) -> list[str]:
    dat_file_name_list: list[str] = []
    if h5_path.exists():
        # try to ensure h5 is not currently being written by another process
        ten_minutes_before_now = time.time() - 600
        last_modified_time = os.path.getmtime(h5_path)
        if last_modified_time < ten_minutes_before_now:
            try:
                with h5py.File(name=str(h5_path), mode="r") as h5_file:
                        data_set_names = sorted(h5_file.keys())
                        for data_set_name in data_set_names:
                            data_set = h5_file.get(data_set_name)
                            dat_name = data_set.attrs[DAT_FILE_NAME_KEY]
                            dat_file_name_list.append(dat_name)
            except Exception as exc:
                raise RuntimeError(f"failed to read {h5_path}") from exc

        else:
            logger.info(f"get_dat_file_names_for_h5: skipping read of recently modified file {h5_path}, "
                        f"last_modified_time={last_modified_time}, ten_minutes_before_now={ten_minutes_before_now}")
    return dat_file_name_list


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
                cyx_dat: CYXDat = new_cyx_dat(dat_path)
                archive_writer.create_and_add_raw_data_group(cyx_dat=cyx_dat,
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
