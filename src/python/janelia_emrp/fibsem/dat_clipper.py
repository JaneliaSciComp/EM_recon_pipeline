import argparse
import logging

import sys
from pathlib import Path

import numpy as np
from fibsem_tools.io.fibsem import OFFSET

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

    with open(source_path, "rb") as raw_source_file:
        header = bytearray(raw_source_file.read(OFFSET))

    # stole locations of header values from fibsem_tools.io.fibsem
    number_of_channels = int.from_bytes(header[32:33], "big")  # 'ChanNum': 2
    eight_bit = int.from_bytes(header[33:34], "big")           # 'EightBit': 0
    original_width = int.from_bytes(header[100:104], "big")    # 'XResolution': 8250
    original_height = int.from_bytes(header[104:108], "big")   # 'YResolution': 3500

    # The FileLength header does not seem to be used and did not have a value that made sense to me,
    # so I chose to leave it alone even though clipping reduces file length.
    # file_length = int.from_bytes(data[1000:1008], "big")     # 'FileLength': 115501024

    # Update XResolution and YResolution with clipped values
    header[100:104] = width.to_bytes(4, "big")
    header[104:108] = height.to_bytes(4, "big")

    shape = (
        original_height,
        original_width,
        number_of_channels,
    )

    data_type = ">u1" if eight_bit == 1 else ">i2"

    raw_data = np.memmap(
        str(source_path),
        dtype=data_type,
        mode="r",
        offset=OFFSET,
        shape=shape,
    )

    clipped_data = raw_data[y:y+height, x:x+width, :]
    clipped_data = clipped_data.copy(order='C')

    with open(target_path, "wb") as raw_target_file:
        raw_target_file.write(header)
        raw_target_file.write(clipped_data)

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
