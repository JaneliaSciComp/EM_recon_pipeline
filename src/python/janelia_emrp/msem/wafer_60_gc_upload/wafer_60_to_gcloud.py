"""
Script to upload a first wafer 60 test stack to Google Cloud Storage.
"""
import argparse

from janelia_emrp.root_logger import init_logger
from janelia_emrp.msem.wafer_60_gc_upload.client import Parameters, background_correct_and_upload


if __name__ == '__main__':
    init_logger(__file__)

    parser = argparse.ArgumentParser(description="Background correct and upload PNGs.")

    parser.add_argument(
        "--host",
        help="Host of the render web service.",
        type=str
    )
    parser.add_argument(
        "--owner",
        help="Owner of the render project.",
        type=str
    )
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
        "--base-path",
        help="Base path in the GC bucket to upload to.",
        type=str,
    )
    parser.add_argument(
        "--trim-padding",
        help="Padding when trimming the full stacks " \
            "(refers to an existing trimmed render stack with that padding).",
        type=int,
        default=0
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

    # Test setup
    CLI_ARGS = (
        "--host http://em-services-1.int.janelia.org:8080/render-ws/v1 "
        "--owner trautmane "
        "-w 60 "
        "-s  296 "
        "--base-path test_upload_mi "
        # "--shading-storage-path /nrs/hess/ibeammsem/system_02/wafers/wafer_60/acquisition"
    )

    args = parser.parse_args(CLI_ARGS.split())
    # Production setup
    # args = parser.parse_args()

    param = Parameters(
        host=args.host,
        owner=args.owner,
        wafer=args.wafer,
        num_threads=args.num_threads,
        bucket_name=args.bucket_name,
        base_path=args.base_path,
        trim_padding=args.trim_padding,
        shading_storage_path=args.shading_storage_path,
    )
    background_correct_and_upload(args.slabs, param)
