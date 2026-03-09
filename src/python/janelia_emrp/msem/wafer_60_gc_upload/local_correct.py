"""
Script to background correct and store MSEM images to local storage.
"""
import argparse
import re

from janelia_emrp.root_logger import init_logger
from janelia_emrp.msem.wafer_60_gc_upload.client import Parameters, background_correct_and_store
from janelia_emrp.msem.wafer_60_gc_upload.render_details import AbstractRenderDetails
from janelia_emrp.msem.wafer_60_gc_upload.details.writer import LocalWriterFactory


class RenderDetails(AbstractRenderDetails):
    """Details for the render database for local background correction."""
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

    def output_stack_from(self, stack_name: str) -> str:
        """Get the name of the output stack with corrected local paths."""
        return stack_name + "_bgc"


if __name__ == '__main__':
    init_logger(__file__)

    parser = argparse.ArgumentParser(description="Background correct and store PNGs locally.")

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
        "--output-path",
        help="Base path on local filesystem to store corrected images.",
        type=str,
    )
    parser.add_argument(
        "--trim-padding",
        help="Padding when trimming the full stacks "
            "(refers to an existing trimmed render stack with that padding). "
            "If not given, the full source stack is used.",
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

    args = parser.parse_args()

    param = Parameters(
        host=args.host,
        owner=args.owner,
        wafer=args.wafer,
        num_threads=args.num_threads,
        writer_factory=LocalWriterFactory(base_path=args.output_path),
        shading_storage_path=args.shading_storage_path,
        invert=args.invert,
    )
    render_details = RenderDetails(args.trim_padding)
    background_correct_and_store(args.slabs, render_details, param)
