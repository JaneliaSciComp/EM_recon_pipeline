import logging
from pathlib import Path
from typing import Dict, Any, Optional, Tuple, Union

import h5py
import numpy as np
from fibsem_tools.io.fibsem import OFFSET, MAGIC_NUMBER
from h5py import Dataset

logger = logging.getLogger("dat_to_h5_writer")


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
                     mode: str = "w-") -> h5py.File:
        return h5py.File(name=output_path, mode=mode, driver=self.driver)

    def create_and_add_data_set(self,
                                data_set_name: str,
                                dat_header: Optional[Dict[str, Any]],
                                pixel_array: np.ndarray,
                                to_h5_file: h5py.File,
                                dat_file_path_for_raw_header: Optional[Path] = None,
                                z_nm_per_pixel: Optional[int] = None) -> Dataset:
        """
        Creates a new data set and adds it to the `to_h5_file`.

        Parameters
        ----------
        data_set_name : str
            name for the data set.

        dat_header : Optional[Dict[str, Any]]
            parsed header information from .dat file to include as data set attributes or None to skip.

        pixel_array : np.ndarray
            pixel array for data set.

        to_h5_file : h5py.File
            HDF5 container for data set.

        dat_file_path_for_raw_header : Optional[Path]
            path of source .dat file or None to skip storing RawHeader data in data set.

        z_nm_per_pixel : Optional[int]
            nm per pixel for z dimension or None if unknown.

        Returns
        -------
        Dataset
            The created data set.
        """
        logger.info(f"create_and_add_data_set: entry, adding {data_set_name} to {to_h5_file.filename}")

        valid_chunks = build_safe_chunk_shape(self.chunk_shape, pixel_array.shape)

        data_set = to_h5_file.create_dataset(name=data_set_name,
                                             data=pixel_array[:],
                                             chunks=valid_chunks,
                                             compression=self.compression,
                                             compression_opts=self.compression_opts)
        if dat_header:
            for key, value in dat_header.__dict__.items():
                data_set.attrs[key] = value
            add_element_size_um_attributes_to_data_set(dat_header, data_set, z_nm_per_pixel)

        if dat_file_path_for_raw_header:
            add_raw_header_to_data_set(data_set_name, dat_file_path_for_raw_header, data_set)

        logger.info(f"create_and_add_data_set: exit")

        return data_set


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


def add_raw_header_to_data_set(data_set_name: str,
                               dat_file_path: Path,
                               data_set: Dataset):
    """
    Reads the raw header bytes from `dat_file_path` and saves them as a 'RawHeader' attribute in the `data_set`.
    This enables byte-comparable dat files to be reconstructed from HDF5 archives.
    """
    logger.info(f"add_raw_header_to_data_set: entry, data set {data_set_name}")

    with open(dat_file_path, "rb") as raw_file:
        raw_bytes = raw_file.read(OFFSET)

        assert np.frombuffer(raw_bytes, '>u4', count=1)[0] == MAGIC_NUMBER
        data_set.attrs["RawHeader"] = np.frombuffer(raw_bytes, dtype='u1')


# TODO: review maintenance of element_size_um attribute for ImageJ, do we need it?
def add_element_size_um_attributes_to_data_set(dat_header: Dict[str, Any],
                                               data_set: Dataset,
                                               z_nm_per_pixel: Optional[int] = None):
    """
    Adds element_size_um attribute to `data_set` to supress error messages when loading
    HDF5 archives in ImageJ.

    From https://lmb.informatik.uni-freiburg.de/resources/opensource/imagej_plugins/hdf5.html
    The (ImageJ) HDF5 plugin saves and loads the pixel/voxel size in
    micrometer of the image in the attribute "element_size_um".
    It has always 3 components in the order z,y,x (accordingly to the c-style indexing).

    Parameters
    ----------
    dat_header : Dict[str, Any]
        header dict.

    data_set : Dataset
        data set to modify.

    z_nm_per_pixel: Optional[int]
        nm per pixel for z dimension or None if unknown.
    """
    nm_per_pixel = int(float(dat_header.__dict__["PixelSize"]) + 0.5)
    um_per_pixel = nm_per_pixel / 1000.0

    # TODO: does -1 make sense for undefined z element_size_um attribute?
    z_um_per_pixel = z_nm_per_pixel / 1000.0 if z_nm_per_pixel else -1

    data_set.attrs["element_size_um"] = [z_um_per_pixel, um_per_pixel, um_per_pixel]
