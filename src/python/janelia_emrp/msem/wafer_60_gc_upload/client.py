"""
Functions to background correct and upload PNGs to Google Cloud Storage.
"""
from dataclasses import dataclass
import logging
import time

from basicpy import BaSiC
from distributed import Future, LocalCluster, as_completed, get_client

from details import (
    load_images_as_stack,
    store_beam_shading,
    MsemCloudWriter,
    AcquisitionConfig,
    BeamConfig,
    Slab,
    MsemClient
)
from janelia_emrp.msem.wafer_60_gc_upload.render_details import AbstractRenderDetails


logger = logging.getLogger(__name__)


@dataclass
class Parameters:
    """Class to hold parameters for the background correction and upload."""
    host: str
    owner: str
    wafer: int
    num_threads: int
    bucket_name: str
    base_path: str
    shading_storage_path: str | None
    invert: bool = False


def background_correct_and_upload(
        slabs: list[int],
        render_details: AbstractRenderDetails,
        param: Parameters
    ) -> None:
    """Loads all images from the given slabs, computes background correction
    using BaSiC, and uploads the corrected images of the trimmed versions of the
    slabs to GCP."""

    logger.info("background_correct_and_upload: Called with %s", param)
    logger.info("background_correct_and_upload: Slabs to process: %s", slabs)

    slabs = [Slab(param.wafer, slab) for slab in slabs]

    # Spin up local dask cluster (this is supposed to run on a single machine)
    cluster = LocalCluster(n_workers=param.num_threads, threads_per_worker=1, processes=True)
    dask_client = cluster.get_client()

    logger.info("Starting Dask cluster; see dashboard at %s", cluster.dashboard_link)

    # Process slabs in order, but process sfovs in parallel
    for slab in slabs:
        logger.info("Processing %s", slab)
        start = time.time()

        project = render_details.project_from_slab(slab.wafer, slab.serial_id)
        msem_client = MsemClient(host=param.host, owner=param.owner, project=project)

        futures, gc_stacks = process_slab(slab, render_details, msem_client, param)
        logger.info("%s has %d tasks", slab, len(futures))

        for gc_stack in gc_stacks:
            logger.info("completing stack %s", gc_stack)
            msem_client.complete_stack(gc_stack)

        for future in as_completed(futures):
            future.result()
            del future  # Free up memory to avoid memory leak

        end = time.time()
        logger.info("Finished processing %s - took %.2fs", slab, end - start)
        dask_client.restart()  # Restart the client to free up memory


def process_slab(
        slab: Slab,
        render_details: AbstractRenderDetails,
        client: MsemClient,
        param: Parameters
    ) -> list[Future]:
    """Divide a slab into layers and sfovs to process them."""
    # Check if all regions of the slab have consistent z ranges
    z_ranges = []
    region_stacks = client.get_stack_ids(slab)
    download_stacks = []
    upload_stacks = []

    for _, stack_ids in region_stacks.items():
        for stack_id in stack_ids:

            # Check if the stack is a download or upload stack
            stack_name = stack_id.stack
            is_download = render_details.is_source_stack(stack_name)
            is_upload = render_details.is_target_stack(stack_name)

            if not is_download and not is_upload:
                continue

            if is_download:
                download_stacks.append(stack_id)
            if is_upload:
                upload_stacks.append(stack_id)

            # Compare the z range of the stack with the others
            current_z_range = client.get_z_range(stack_id)
            z_ranges.append(tuple(current_z_range))

    # There should be only one z range for all regions
    if len(set(z_ranges)) != 1:
        raise ValueError(f"{slab} has inconsistent z ranges: {z_ranges}")

    z_range = z_ranges[0]
    logger.info("%s has %d layers.", slab, len(z_range))

    # Create render stacks with the google cloud paths
    gc_stacks = []
    for upload_stack in upload_stacks:
        stack_with_gc_paths = render_details.gc_stack_from(upload_stack.stack)
        client.setup_new_stack(upload_stack.stack, stack_with_gc_paths)
        gc_stacks.append(stack_with_gc_paths)

    return process_all_layers(
        download_stacks,
        upload_stacks,
        gc_stacks,
        z_range,
        client,
        param
    ), gc_stacks


def process_all_layers(
        download_stacks: list[str],
        upload_stacks: list[str],
        gc_stacks: list[str],
        z_range: list[int],
        render_client: MsemClient,
        param: Parameters
) -> list[Future]:
    """Process all layers of a slab."""
    futures = []
    for z in z_range:
        futures += process_layer(download_stacks, upload_stacks, gc_stacks, render_client, z, param)
    return futures


def process_layer(
        download_stacks: list[str],
        upload_stacks: list[str],
        gc_stacks: list[str],
        render_client: MsemClient,
        z: int,
        param: Parameters
) -> list[Future]:
    """Process a single layer of a slab."""
    # Collect storage locations across all regions
    all_locations = []
    for stack in download_stacks:
        locations, _ = render_client.get_storage_locations(stack_id=stack, z=z)
        all_locations += locations

    upload_locations = []
    gc_writer = MsemCloudWriter.get_cached(param.bucket_name, param.base_path)
    for stack, gc_stack in zip(upload_stacks, gc_stacks):
        locations, tile_specs = render_client.get_storage_locations(stack_id=stack, z=z)
        upload_locations += locations
        render_client.save_tilespecs_with_gc_paths(gc_stack, tile_specs, gc_writer)

    # Group locations by BeamConfig
    beam_to_all = group_by_beam_config(all_locations)
    beam_to_upload = group_by_beam_config(upload_locations)
    if len(beam_to_all) != 91:
        first_beam = next(beam_to_all.keys())
        raise ValueError(f"Slab {first_beam.slab} has only {len(beam_to_all)} sfovs.")

    futures = []
    cluster = get_client()
    for beam_config, locs in beam_to_all.items():
        acquisitions_to_upload = beam_to_upload[beam_config]
        future = cluster.submit(
            process_sfov,
            beam_config,
            locs,
            acquisitions_to_upload,
            param.bucket_name,
            param.base_path,
            param.shading_storage_path,
            param.invert
        )
        futures.append(future)

    return futures


def process_sfov(
        beam_config: BeamConfig,
        all_locs: list[str],
        locs_to_upload: list[str],
        bucket_name: str,
        base_path: str,
        shading_storage_path: str,
        invert: bool
) -> None:
    """Process a single sfov (i.e., a beam configuration)."""
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

    # Invert the images if desired
    if invert:
        corrected_images = 255 - corrected_images

    # Upload images
    upload = time.time()
    writer = MsemCloudWriter.get_cached(bucket_name, base_path)
    all_locs = [AcquisitionConfig.from_storage_location(loc) for loc, k in zip(all_locs, keep) if k]
    succeeded = writer.write_all_images(corrected_images, all_locs)
    if not all(succeeded):
        logger.error('Failed to write all images for %s.', beam_config)
    end = time.time()

    logger.info(
        "%s: loading: %.2fs, correcting: %.2fs, uploading: %.2fs",
        beam_config, correct - start, upload - correct, end - upload
    )

    # Save the shading to disk if desired
    if shading_storage_path is not None:
        store_beam_shading(shading, shading_storage_path, beam_config)


def correct_beam_shading(all_images, indices_to_correct):
    """Correct the background of the images caused by beam shading using BaSiC."""
    # Use all images to compute the flatfield
    basic = BaSiC(get_darkfield=False, max_workers=4)
    basic.fit(all_images)

    # Only a specified subset of images is corrected
    corrected_images = all_images[indices_to_correct]
    corrected_images = basic.transform(corrected_images)

    # Check bounds of the corrected images
    # We want to prevent clipping, so we only shift the images
    # The minimum is resin (less important), shift that first
    corrected_min = corrected_images.min(axis=(1, 2))
    too_small = corrected_min < 0
    if any(too_small):
        corrected_images[too_small] -= corrected_min[too_small, None, None]

    # The content is more important, so we finally make sure that there is no clipping
    corrected_max = corrected_images.max(axis=(1, 2)) - 255
    too_large = corrected_max > 0
    if any(too_large):
        corrected_images[too_large] -= corrected_max[too_large, None, None]

    return corrected_images, basic.flatfield


def group_by_beam_config(locations: str) -> dict[BeamConfig, list[str]]:
    """Group storage locations by BeamConfig."""
    beam_configs = {}
    for location in locations:
        beam_config = BeamConfig.from_storage_location(location)
        if beam_config not in beam_configs:
            beam_configs[beam_config] = []
        beam_configs[beam_config].append(location)
    return beam_configs
