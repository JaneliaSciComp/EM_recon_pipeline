"""
Short script that shows a proof of concept for the background correction of
multi-sem images using BaSiC.
"""
import argparse
import gc
import logging
from pathlib import Path
import re
import time
from typing import Dict, List

from distributed import Future, WorkerPlugin, get_client
from distributed.worker import logger
from basicpy import BaSiC
from dask.distributed import LocalCluster, as_completed

from wafer_60_tools.client import MsemClient
from wafer_60_tools.config import AcquisitionConfig, BeamConfig, Slab
from wafer_60_tools.data import load_images_as_stack, store_beam_shading, MsemCloudWriter
from janelia_emrp.root_logger import init_logger


logger = logging.getLogger(__name__)


class CleanupPlugin(WorkerPlugin):
    """Run garbage collection after each task to avoid memory leaks."""
    def transition(self, key, start, finish, *args, **kwargs):
        if finish == 'released':
            gc.collect()


def process_slab(slab: Slab, trim_padding: int = 0, **kwargs) -> List[Future]:
    """Divide a slab into layers and sfovs to process them."""
    client = MsemClient()

    download_pattern = re.compile('_r(\\d+)$')            # no trimming
    upload_pattern = re.compile(f'_d{trim_padding:02}$')  # trimmed with given padding

    # Check if all regions of the slab have consistent z ranges
    z_ranges = set()
    region_stacks = client.get_stack_ids(slab)
    download_stacks = []
    upload_stacks = []

    for _, stack_ids in region_stacks.items():
        for stack_id in stack_ids:

            # Check if the stack is a download or upload stack
            stack_name = stack_id.stack
            is_download = download_pattern.search(stack_name) is not None
            is_upload = upload_pattern.search(stack_name) is not None

            if not is_download and not is_upload:
                continue

            if is_download:
                download_stacks.append(stack_id)
            if is_upload:
                upload_stacks.append(stack_id)

            # Compare the z range of the stack with the others
            current_z_range = client.get_z_range(stack_id)
            z_ranges.add(tuple(current_z_range))

    # There should be only one z range for all regions
    if len(z_ranges) != 1:
        raise ValueError(f"{slab} has inconsistent z ranges.")

    z_range = z_ranges.pop()
    logger.info("%s has %d layers.", slab, len(z_range))

    return process_all_layers(download_stacks, upload_stacks, z_range, **kwargs)


def process_all_layers(
        download_stacks: List[str],
        upload_stacks: List[str],
        z_range: List[int],
        **kwargs
) -> List[Future]:
    """Process all layers of a slab."""
    futures = []
    for z in z_range:
        futures += process_layer(download_stacks, upload_stacks, z, **kwargs)
    return futures


def process_layer(
        download_stacks: List[str],
        upload_stacks: List[str],
        z: int,
        **kwargs
) -> List[Future]:
    """Process a single layer of a slab."""
    client = MsemClient()
    cluster = get_client()

    # Collect storage locations across all regions
    all_locations = []
    for stack in download_stacks:
        all_locations += client.get_storage_locations(stack_id=stack, z=z)

    upload_locations = []
    for stack in upload_stacks:
        upload_locations += client.get_storage_locations(stack_id=stack, z=z)

    # Group locations by BeamConfig
    beam_to_all = group_by_beam_config(all_locations)
    beam_to_upload = group_by_beam_config(upload_locations)
    if len(beam_to_all) != 91:
        first_beam = next(beam_to_all.keys())
        raise ValueError(f"Slab {first_beam.slab} has only {len(beam_to_all)} sfovs.")

    futures = []
    for beam_config, locs in beam_to_all.items():
        acquisitions_to_upload = beam_to_upload[beam_config]
        future = cluster.submit(
            process_sfov,
            beam_config,
            locs,
            acquisitions_to_upload,
            kwargs.get('shading_storage_path', None),
        )
        futures.append(future)

    return futures


def process_sfov(
        beam_config: BeamConfig,
        all_locs: List[str],
        locs_to_upload: List[str],
        shading_storage_path: Path | None
) -> None:
    """Process a single sfov (i.e., a beam configuration)."""
    writer = MsemCloudWriter('janelia-spark-test', base_path='test_upload_mi')

    # Find out which images to upload
    logger.info("%s: Found %d images to process and %d to upload.",
                beam_config, len(all_locs), len(locs_to_upload))
    locs_to_upload = set(locs_to_upload)
    keep = [loc in locs_to_upload for loc in all_locs]

    # Do background correction
    start = time.time()
    images = load_images_as_stack(all_locs)

    correct = time.time()
    corrected_images, shading = correct_beam_shading(images, keep)

    # Upload images
    upload = time.time()
    all_locs = [AcquisitionConfig.from_storage_location(loc) for loc, k in zip(all_locs, keep) if k]
    succeeded = writer.write_all_images(corrected_images, all_locs)
    if not all(succeeded):
        logger.error('Failed to write all images for %s.', beam_config)
    end = time.time()

    logger.info(
        "%s: loading: %.2fs, correcting: %.2fs, uploading: %.2fs",
        beam_config, correct - start, upload - correct, end - upload
    )

    if shading_storage_path is not None:
        store_beam_shading(shading, shading_storage_path, beam_config)


def correct_beam_shading(all_images, indices_to_correct):
    """Correct the background of the images caused by beam shading using BaSiC."""
    # Use all images to compute the flatfield
    basic = BaSiC(get_darkfield=False)
    basic.fit(all_images)

    # Only a specified subset of images is corrected
    corrected_images = all_images[indices_to_correct]
    corrected_images = basic.transform(corrected_images)

    return corrected_images, basic.flatfield


def group_by_beam_config(locations: str) -> Dict[BeamConfig, List[str]]:
    """Group storage locations by BeamConfig."""
    beam_configs = {}
    for location in locations:
        beam_config = BeamConfig.from_storage_location(location)
        if beam_config not in beam_configs:
            beam_configs[beam_config] = []
        beam_configs[beam_config].append(location)
    return beam_configs


def background_correct_and_upload(args: argparse.Namespace) -> None:
    """Loads all images from the given slabs, computes background correction
    using BaSiC, and uploads the corrected images of the trimmed versions of the
    slabs to GCP."""

    slabs = [Slab(args.wafer, slab) for slab in args.slabs]

    # cluster = LocalCluster(n_workers=1, threads_per_worker=1, processes=False)
    cluster = LocalCluster(n_workers=1, threads_per_worker=8, processes=True)
    dask_client = cluster.get_client()
    plugin = CleanupPlugin()
    dask_client.register_worker_plugin(plugin)

    logger.info("Starting Dask cluster; see dashboard at %s", cluster.dashboard_link)
    logger.info("Processing %d slabs", len(slabs))

    futures = []
    for slab in slabs:
        logger.info("Processing %s", slab)
        futures += process_slab(slab, trim_padding=0, **vars(args))

    for future in as_completed(futures):
        future.result()
        future.release()


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

    # Test setup
    cli_args = parser.parse_args("--w 60 -s 296".split())
    # cli_args = parser.parse_args("--w 60 -s 296 --shading-storage-path /nrs/hess/ibeammsem/system_02/wafers/wafer_60/acquisition".split())

    # Production setup
    # args = parser.parse_args()
    logger.info("Called with %s", cli_args)

    background_correct_and_upload(cli_args)
