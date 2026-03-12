"""
Script to background correct and store MSEM images to local storage.
"""
import argparse
import re

from janelia_emrp.root_logger import init_logger
from janelia_emrp.msem.background_correction.client import Parameters, background_correct_and_store
from janelia_emrp.msem.background_correction.render_details import AbstractRenderDetails
from janelia_emrp.msem.background_correction.details.writer import LocalWriterFactory


class RenderDetails(AbstractRenderDetails):
    """Details for the render database for wafer 68 local background correction."""
    def __init__(self, suffix: str | None):
        super().__init__()

        if suffix is None:
            # Match bare region stacks (e.g., w68_s000_r00)
            self.source_pattern = re.compile('_r(\\d+)$')
        else:
            # Match stacks with the given suffix (e.g., w68_s000_r00_pa_mat_render_align)
            self.source_pattern = re.compile(f'{re.escape(suffix)}$')


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
        return self.source_pattern.search(stack_name) is not None

    def output_stack_from(self, stack_name: str) -> str:
        """Get the name of the output stack with corrected local paths."""
        return stack_name + "_bgc"


if __name__ == '__main__':
    init_logger(__file__)

    parser = argparse.ArgumentParser(description="Background correct and store PNGs locally.")

    parser.add_argument(
        "--base-data-url",
        help="Base data URL for the render web service (e.g. http://10.40.3.113:8080/render-ws/v1 ).",
        type=str
    )
    parser.add_argument(
        "--owner",
        help="Owner of the render project.",
        type=str
    )
    parser.add_argument(
        "--output-path",
        help="Base path on local filesystem to store corrected images.",
        type=str,
    )
    parser.add_argument(
        "--suffix",
        help="Stack name suffix to match (e.g. '_pa_mat_render_align'). "
            "If not given, matches bare region stacks like w68_s000_r00.",
        type=str,
        default=None,
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
        "--min-z",
        help="Minimum z value to process (inclusive).",
        type=int,
        default=None,
    )
    parser.add_argument(
        "--max-z",
        help="Maximum z value to process (inclusive).",
        type=int,
        default=None,
    )
    parser.add_argument(
        "--skip-stack-completion",
        help="Skip corrected stack completion because you are running concurrent jobs on the same stack(s).",
        action="store_true",
        default=False,
    )

    args = parser.parse_args()

    if args.min_z is not None and args.max_z is not None and args.min_z > args.max_z:
        parser.error("--min-z cannot be greater than --max-z")

    param = Parameters(
        base_data_url=args.base_data_url,
        owner=args.owner,
        wafer=68,
        num_threads=args.num_threads,
        writer_factory=LocalWriterFactory(base_path=args.output_path),
        shading_storage_path=args.shading_storage_path,
        min_z=args.min_z,
        max_z=args.max_z,
        invert=args.invert,
        complete_stacks=(not args.skip_stack_completion),
    )
    render_details = RenderDetails(args.suffix)
    background_correct_and_store([0], render_details, param)
