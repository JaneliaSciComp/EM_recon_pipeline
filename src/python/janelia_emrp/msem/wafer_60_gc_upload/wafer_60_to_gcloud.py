"""
Short script that shows a proof of concept for the background correction of
multi-sem images using BaSiC.
"""
import argparse

from janelia_emrp.root_logger import init_logger
from janelia_emrp.msem.wafer_60_gc_upload.client import background_correct_and_upload


if __name__ == '__main__':
    init_logger(__file__)

    parser = argparse.ArgumentParser(description="Background correct and upload PNGs.")

    parser.add_argument(
        "-w", "--wafer",
        help="Wafer to process images from (60 or 61).",
        type=int,
    )
    parser.add_argument(
        "-s", "--slabs",
        help="(List of) slabs to process images from.",
        type=int,
        nargs='+',
    )
    parser.add_argument(
        "--shading-storage-path",
        help="Storage path for shading (shading is not stored if path is not given).",
        type=str,
        default=None,
    )
    parser.add_argument(
        "--num-threads",
        help="Number of threads to use for processing.",
        type=int,
        default=8,
    )
    parser.add_argument(
        "--bucket-name",
        help="Google Cloud Storage bucket to upload to.",
        type=str,
        default="janelia-spark-test",
    )
    parser.add_argument(
        "--base-path",
        help="Base path in the GC bucket to upload to.",
        type=str,
    )

    # Test setup
    cli_args = parser.parse_args("--w 60 -s 296 --base-path test_upload_mi".split())
    # cli_args = parser.parse_args("--w 60 -s 296 --shading-storage-path /nrs/hess/ibeammsem/system_02/wafers/wafer_60/acquisition".split())

    # Production setup
    # args = parser.parse_args()

    background_correct_and_upload(cli_args)
