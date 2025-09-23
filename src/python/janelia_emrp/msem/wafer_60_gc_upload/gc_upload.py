"""
Script to upload a first wafer 60 test stack to Google Cloud Storage.
"""
import argparse
import re

from janelia_emrp.root_logger import init_logger
from janelia_emrp.msem.wafer_60_gc_upload.client import Parameters, background_correct_and_upload
from janelia_emrp.msem.wafer_60_gc_upload.render_details import AbstractRenderDetails


class RenderDetails(AbstractRenderDetails):
    """Details for the render database for a first test stack of wafer 60."""
    def __init__(self, trim_padding: int):
        super().__init__()

        # No trimming for the source stack (e.g., w60_s296_r00)
        self.source_pattern = re.compile('_r(\\d+)$')

        # Trimming for the target stack (e.g., w60_s296_r00_d30)
        if trim_padding is None or trim_padding < 0:
            self.destination_pattern = self.source_pattern
        else:
            self.destination_pattern = re.compile(f'_d{trim_padding:02}$')


    def project_from_slab(self, wafer: int, serial_id: int) -> str:
        """Get the project name from the wafer / serial ID combination."""
        lower_bound = serial_id // 10 * 10
        upper_bound = lower_bound + 9
        return f"w{wafer}_serial_{lower_bound:03}_to_{upper_bound:03}"

    def is_source_stack(self, stack_name: str) -> bool:
        """Check if the stack is to be used as a source for background correction."""
        return self.source_pattern.search(stack_name) is not None

    def is_target_stack(self, stack_name: str) -> bool:
        """Check if the stack is to be used as a target for background correction."""
        return self.destination_pattern.search(stack_name) is not None

    def gc_stack_from(self, stack_name: str) -> str:
        """Get the name of the stack with Google Cloud Storage paths from the original
        stack name.
        """
        return stack_name + "_gc"


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
            "(refers to an existing trimmed render stack with that padding). " \
            "If not given, the full source stack is uploaded.",
        type=int,
        default=None
    )
    parser.add_argument(
        "--invert",
        help="Invert the images after background correction.",
        action="store_true",
        default=False,
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
    # CLI_ARGS = (
    #     "--host http://em-services-1.int.janelia.org:8080/render-ws/v1 "
    #     "--owner hess_wafers_60_61 "
    #     "-w 60 "
    #     "-s 360 "
    #     "--num-threads  16 "
    #     "--base-path hess_wafer_60_data "
    #     "--invert "
    # )

    # args = parser.parse_args(CLI_ARGS.split())
    # Production setup
    args = parser.parse_args()

    param = Parameters(
        host=args.host,
        owner=args.owner,
        wafer=args.wafer,
        num_threads=args.num_threads,
        bucket_name=args.bucket_name,
        base_path=args.base_path,
        shading_storage_path=args.shading_storage_path,
        invert=args.invert,
    )
    render_details = RenderDetails(args.trim_padding)
    background_correct_and_upload(args.slabs, render_details, param)
