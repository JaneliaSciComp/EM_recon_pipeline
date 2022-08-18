import argparse
import logging
import traceback
from pathlib import Path

import h5py
import numpy as np
import sys
from h5py import Dataset

from janelia_emrp.fibsem.dat_to_h5_writer import RAW_HEADER_KEY, RAW_FOOTER_KEY, DAT_FILE_NAME_KEY
from janelia_emrp.root_logger import init_logger

logger = logging.getLogger(__name__)


REQUIRED_HEADER_KEYS = [RAW_HEADER_KEY, RAW_FOOTER_KEY]


def validate_required_key_exists(key: str,
                                 data_set: Dataset,
                                 h5_path: Path) -> None:
    if key not in data_set.attrs:
        raise ValueError(f"data set {data_set.name} in {str(h5_path)} is missing required attribute '{key}'")


def restore_dat_bytes(data_set: Dataset,
                      h5_path: Path) -> bytes:

    for key in REQUIRED_HEADER_KEYS:
        validate_required_key_exists(key, data_set, h5_path)

    dat_bytes = bytearray(data_set.attrs[RAW_HEADER_KEY])
    pixel_data = np.array(data_set)
    dat_bytes += bytearray(np.moveaxis(pixel_data, 0, -1).tobytes())
    dat_bytes += bytearray(data_set.attrs[RAW_FOOTER_KEY])

    return dat_bytes


def restore_dat_file_for_data_set(h5_path: Path,
                                  data_set: Dataset,
                                  to_path: Path) -> None:

    validate_required_key_exists(DAT_FILE_NAME_KEY, data_set, h5_path)

    dat_file_path = Path(to_path, data_set.attrs[DAT_FILE_NAME_KEY])

    if dat_file_path.exists():
        raise ValueError(f"{dat_file_path} for data set {data_set.name} in {str(h5_path)} already exists")

    dat_bytes = restore_dat_bytes(data_set, h5_path)

    with open(dat_file_path, "wb") as dat_file:
        dat_file.write(dat_bytes)

    logger.info(f"restore_dat_file_for_data_set: saved {str(dat_file_path)}")


def restore_dat_files(h5_path_list: list[Path],
                      to_path: Path) -> None:
    for h5_path in h5_path_list:
        with h5py.File(name=str(h5_path), mode="r") as h5_file:
            data_set_names = sorted(h5_file.keys())
            logger.info(f"restore_dat_files: found {len(data_set_names)} data sets in {h5_path}")
            for data_set_name in data_set_names:
                data_set = h5_file.get(data_set_name)
                restore_dat_file_for_data_set(h5_path, data_set, to_path)


def validate_bytes_match(original_context: str,
                         original_bytes: bytes,
                         restored_context: str,
                         restored_bytes: bytes) -> None:
    if len(original_bytes) != len(restored_bytes):
        raise ValueError(f"{original_context} has {len(original_bytes)} bytes but "
                         f"{restored_context} has {len(restored_bytes)} bytes")

    for i in range(0, len(original_bytes)):
        if original_bytes[i] != restored_bytes[i]:
            raise ValueError(f"byte {i} differs between {original_context} and {restored_context}")


def validate_original_dat_bytes_match(h5_path: Path,
                                      dat_parent_path: Path) -> list[Path]:
    matched_dat_file_paths = []

    with h5py.File(name=str(h5_path), mode="r") as h5_file:
        data_set_names = sorted(h5_file.keys())
        logger.info(f"validate_original_dat_bytes_match: found {len(data_set_names)} data sets in {h5_path}")

        for data_set_name in data_set_names:
            data_set = h5_file.get(data_set_name)
            original_dat_file_path = Path(dat_parent_path, data_set.attrs[DAT_FILE_NAME_KEY])

            restored_context = f"data set {data_set.name} in {str(h5_path)}"
            if not original_dat_file_path.exists():
                raise ValueError(f"{original_dat_file_path} not found for {restored_context}")

            with open(original_dat_file_path, "rb") as original_file:
                original_bytes = original_file.read()
            restored_bytes = restore_dat_bytes(data_set, h5_path)
            validate_bytes_match(original_context=str(original_dat_file_path),
                                 original_bytes=original_bytes,
                                 restored_context=restored_context,
                                 restored_bytes=restored_bytes)
            matched_dat_file_paths.append(original_dat_file_path)

    return matched_dat_file_paths


def main(arg_list: list[str]):
    parser = argparse.ArgumentParser(
        description="Validate that byte contents of HDF5 and dat files match or restore dat files to disk."
    )
    parser.add_argument(
        "--h5_path",
        help="Path(s) of source HDF5 file(s)",
        required=True,
        nargs='+'
    )
    parser.add_argument(
        "--dat_parent_path",
        help="Path of parent directory for dat files",
        required=True,
    )
    parser.add_argument(
        "--restore_dat_files",
        help="Indicates that restored dat files should be saved within the dat_parent_path",
        action="store_true",
    )

    args = parser.parse_args(arg_list)

    h5_path_list = [Path(p) for p in args.h5_path]
    dat_parent_path = Path(args.dat_parent_path)

    if args.restore_dat_files:
        restore_dat_files(h5_path_list, dat_parent_path)
    else:
        matched_original_path_list = []
        for h5_path in h5_path_list:
            matched_original_path_list.extend(validate_original_dat_bytes_match(h5_path, dat_parent_path))

        logger.info("The following dat paths were validated:")
        for matched_original_path in matched_original_path_list:
            logger.info(f"  {matched_original_path}")


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
