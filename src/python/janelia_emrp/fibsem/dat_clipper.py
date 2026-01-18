import argparse
import logging
import os

import sys
from pathlib import Path

import numpy as np
from fibsem_tools.io.dat import OFFSET

from janelia_emrp.fibsem.dat_to_scheffer_8_bit import compress_and_save
from janelia_emrp.root_logger import init_logger

logger = logging.getLogger(__name__)


def clip_dat(source_path: Path,
             x: int,
             y: int,
             width: int,
             height: int,
             target_path: Path):

    """
    Clips a dat file to create a smaller version useful for testing.
    """

    source_size = os.path.getsize(source_path)

    with open(source_path, "rb") as raw_source_file:
        header = bytearray(raw_source_file.read(OFFSET))
        original_file_length = int.from_bytes(header[1000:1008], "big")  # 'FileLength': 115501024
        raw_source_file.seek(original_file_length)
        recipe_size = source_size - original_file_length
        recipe = bytearray(raw_source_file.read(recipe_size))

    # store locations of header values from fibsem_tools.io.fibsem
    number_of_channels = int.from_bytes(header[32:33], "big")  # 'ChanNum': 2
    eight_bit = int.from_bytes(header[33:34], "big")           # 'EightBit': 0
    original_width = int.from_bytes(header[100:104], "big")    # 'XResolution': 8250
    original_height = int.from_bytes(header[104:108], "big")   # 'YResolution': 3500

    # set numpy data type and recalculate FileLength header value
    file_length = width * height * number_of_channels
    if eight_bit == 1:
        data_type = ">u1"
    else:
        data_type = ">i2"
        file_length = file_length * 2
    file_length = file_length + OFFSET

    # Update XResolution and YResolution with clipped values
    header[100:104] = width.to_bytes(4, "big")
    header[104:108] = height.to_bytes(4, "big")
    header[1000:1008] = file_length.to_bytes(8, "big")

    shape = (
        original_height,
        original_width,
        number_of_channels,
    )

    raw_data = np.memmap(
        str(source_path),
        dtype=data_type,
        mode="r",
        offset=OFFSET,
        shape=shape,
    )

    clipped_data = raw_data[y:y+height, x:x+width, :].tobytes()

    with open(target_path, "wb") as raw_target_file:
        raw_target_file.write(header)
        raw_target_file.write(clipped_data)
        raw_target_file.write(recipe)

    logger.info(f"saved {str(target_path)}")


def main():
    parser = argparse.ArgumentParser(
        description="Clip a dat file to create a smaller version useful for testing."
    )
    parser.add_argument(
        "--dat_path",
        help="Path of source dat file",
        required=True,
    )
    parser.add_argument(
        "--clipped_path",
        help="Path of clipped (output) dat file",
        required=True,
    )
    parser.add_argument(
        "--compressed_path",
        help="Path of compressed 8-bit clipped image file (omit if not needed)"
    )
    parser.add_argument(
        "--x",
        help="X offset for clipped region",
        type=int,
        required=True,
    )
    parser.add_argument(
        "--y",
        help="Y offset for clipped region",
        type=int,
        required=True,
    )
    parser.add_argument(
        "--width",
        help="width of clipped region",
        type=int,
        required=True,
    )
    parser.add_argument(
        "--height",
        help="height of clipped region",
        type=int,
        required=True,
    )

    args = parser.parse_args(sys.argv[1:])
    clip_dat(source_path=Path(args.dat_path),
             x=args.x,
             y=args.y,
             width=args.width,
             height=args.height,
             target_path=Path(args.clipped_path))

    if args.compressed_path is not None:
        compress_and_save(dat_path=Path(args.clipped_path),
                          compressed_path=Path(args.compressed_path))


if __name__ == "__main__":
    # NOTE: to fix module not found errors, export PYTHONPATH="/.../EM_recon_pipeline/src/python"

    init_logger(__file__)

    # --dat_path /Users/trautmane/Desktop/pytest/Merlin-6284_21-07-31_152727_0-0-1.dat
    # --clipped_path /Users/trautmane/Desktop/pytest/small_21-07-31_152727_0-0-1.dat
    # --compressed_path /Users/trautmane/Desktop/pytest/small.png
    # --x 560 --y 2160 --width 100 --height 100
    main()
