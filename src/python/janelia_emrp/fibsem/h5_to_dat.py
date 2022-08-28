import argparse
import logging
import traceback
from pathlib import Path

import h5py
import numpy as np
import sys
from h5py import Group

from janelia_emrp.fibsem.dat_to_h5_writer import DAT_FILE_NAME_KEY, RAW_HEADER_DATASET_NAME, RAW_FOOTER_DATASET_NAME, \
    CHANNEL_DATA_SET_NAMES_KEY
from janelia_emrp.root_logger import init_logger

logger = logging.getLogger(__name__)


def validate_key_exists(h5_path: Path,
                        raw_data_group: Group,
                        key: str):
    if key not in raw_data_group.attrs:
        raise ValueError(f"group {raw_data_group.name} in {str(h5_path)} is missing required attribute '{key}'")


def restore_dat_bytes(h5_path: Path,
                      raw_data_group: Group) -> bytes:

    validate_key_exists(h5_path, raw_data_group, CHANNEL_DATA_SET_NAMES_KEY)

    dat_bytes = bytearray(raw_data_group.get(RAW_HEADER_DATASET_NAME))

    channel_data_set_names = raw_data_group.attrs[CHANNEL_DATA_SET_NAMES_KEY]
    channels = []
    for channel_data_set_name in channel_data_set_names:
        channels.append(np.array(raw_data_group.get(channel_data_set_name)))

    cyx_pixel_data_in_machine_order = np.stack(channels)
    yxc_pixel_data_in_machine_order = np.moveaxis(cyx_pixel_data_in_machine_order, 0, -1)

    # numpy stack and concatenate functions ignore dtype byte order and always use machine order,
    # so need to fix byte order after concatenating channels
    # see https://github.com/numpy/numpy/issues/20767
    eight_bit_key = "EightBit"
    is_eight_bit = eight_bit_key in raw_data_group.attrs and raw_data_group.attrs[eight_bit_key] == 1
    data_type = ">u1" if is_eight_bit else ">i2"  # from https://github.com/janelia-cosem/fibsem-tools/blob/f4bedbfc4ff81ec1b83282908ba6702baf98c734/src/fibsem_tools/io/fibsem.py#L619-L622
    yxc_pixel_data = yxc_pixel_data_in_machine_order.astype(data_type)

    dat_bytes += bytearray(yxc_pixel_data)
    dat_bytes += bytearray(raw_data_group.get(RAW_FOOTER_DATASET_NAME))

    return dat_bytes


def restore_dat_file(h5_path: Path,
                     raw_data_group: Group,
                     to_path: Path) -> None:
    validate_key_exists(h5_path, raw_data_group, DAT_FILE_NAME_KEY)
    dat_file_path = Path(to_path, raw_data_group.attrs[DAT_FILE_NAME_KEY])

    if dat_file_path.exists():
        raise ValueError(f"{dat_file_path} for group {raw_data_group.name} in {str(h5_path)} already exists")

    dat_bytes = restore_dat_bytes(h5_path, raw_data_group)

    with open(dat_file_path, "wb") as dat_file:
        dat_file.write(dat_bytes)

    logger.info(f"restore_dat_file: saved {str(dat_file_path)}")


def restore_dat_files(h5_path_list: list[Path],
                      to_path: Path) -> None:
    for h5_path in h5_path_list:
        with h5py.File(name=str(h5_path), mode="r") as h5_file:
            group_names = sorted(h5_file.keys())
            logger.info(f"restore_dat_files: found {len(group_names)} group(s) in {h5_path}")
            for group_name in group_names:
                group = h5_file.get(group_name)
                restore_dat_file(h5_path, group, to_path)


def validate_bytes_match(original_context: str,
                         original_bytes: bytes,
                         restored_context: str,
                         restored_bytes: bytes) -> None:
    if len(original_bytes) != len(restored_bytes):
        raise ValueError(f"{original_context} has {len(original_bytes)} bytes but "
                         f"{restored_context} has {len(restored_bytes)} bytes")

    for i in range(0, len(original_bytes)):
        if original_bytes[i] != restored_bytes[i]:
            debug_info = ""
            if len(original_bytes) > (i + 4):
                debug_info = f", expected {original_bytes[i:i+4]} but found {bytes(restored_bytes[i:i+4])}"

            raise ValueError(f"byte {i} differs between {original_context} and {restored_context}{debug_info}")


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
            restored_bytes = restore_dat_bytes(h5_path, data_set)
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
