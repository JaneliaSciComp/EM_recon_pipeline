import logging
from pathlib import Path

import numpy as np
from PIL import Image
from fibsem_tools.io import read

from janelia_emrp.root_logger import init_logger

logger = logging.getLogger(__name__)


def find_intensity_range(cyx_dat_record_list: list[np.ndarray],
                         channel_num: int = 0) -> tuple[float, float]:
    """
    Parameters
    ----------
    cyx_dat_record_list: list[np.ndarray]
        list of two-channel numpy arrays in cyx order from 16-bit .dat files.

    channel_num: int, default=0
        index of channel to compress.

    Returns
    -------
    tuple[float, float]
        min and max intensities across all tiles in a layer.
    """
    low_for_all_tiles = None
    high_for_all_tiles = None

    saturated = 3  # how close to the boundary do you need to be considered 'saturated'
    low_bound = -32768.0
    high_bound = 32767.0

    min_intensity = low_bound + saturated
    max_intensity = high_bound - saturated

    for index in range(len(cyx_dat_record_list)):
        cyx_dat_record = cyx_dat_record_list[index]

        logger.info(f"find_intensity_range: processing channel {channel_num} from dat with shape {cyx_dat_record.shape}")

        pixel_array = cyx_dat_record[channel_num, :, :]

        # First, find the mean and standard deviation of the 'real' non-saturated pixels.
        # Ignore any that are too close to saturated light or dark.
        unsaturated_pixel_array = pixel_array[np.logical_and(pixel_array >= min_intensity, pixel_array < max_intensity)]

        unsaturated_count = unsaturated_pixel_array.size
        unsaturated_pct = (unsaturated_count * 100.0) / pixel_array.size
        logger.info(f"find_intensity_range: {unsaturated_count} real pixels, {unsaturated_pct} percent")

        mean = np.mean(unsaturated_pixel_array).item()
        std_dev = np.std(unsaturated_pixel_array).item()
        logger.info(f"find_intensity_range: Of the above image points, mean= {mean} and std dev = {std_dev}")

        # Convert mean-4*sigma -> 0, mean +4 sigma to 255.
        low = mean - (4 * std_dev)
        high = mean + (4 * std_dev)

        if low < low_bound:
            logger.info("find_intensity_range: minus 4 sigma < -32768.  Changing to 0")
            low = low_bound

        if high > high_bound:
            logger.info("find_intensity_range: plus 4 sigma > 32767.  Changing to 65535")
            high = high_bound

        temp = low
        low = high
        high = temp  # swap low and high

        logger.info(f"find_intensity_range: low {low:.2f}  -> 0, high {high:.2f} -> 255")

        low_for_all_tiles = low if low_for_all_tiles is None else min(low, low_for_all_tiles)
        high_for_all_tiles = high if high_for_all_tiles is None else max(high, high_for_all_tiles)

    return (low_for_all_tiles, high_for_all_tiles)


def compress_compute_layer(cyx_dat_record_list: list[np.ndarray],
                           channel_num: int = 0) -> list[np.ndarray]:
    """
    Adaptation of Lou Scheffer's 16-bit to 8-bit "compression" algorithm from
    /groups/flyem/home/flyem/bin/compress_dats/build2/Compress.cpp
    that normalizes min and max intensities across all tiles in a layer instead of just a single tile.

    Parameters
    ----------
    cyx_dat_record_list: list[np.ndarray]
        list of two-channel numpy arrays in cyx order from 16-bit .dat files.

    channel_num: int, default=0
        index of channel to compress.

    Returns
    -------
    np.ndarray
        list of 8-bit numpy arrays produced by "compression".
    """
    compressed_data_list: list[np.ndarray] = []
    pixel_array_list = []
    for cyx_dat_record in cyx_dat_record_list:
        logger.info(f"compress_compute_layer: processing channel {channel_num} from dat with shape {cyx_dat_record.shape}")
        pixel_array_list.append(cyx_dat_record[channel_num, :, :])

    stacked_pixel_array = np.stack(pixel_array_list, axis=0)

    # First, find the mean and standard deviation of the 'real' non-saturated pixels.
    # Ignore any that are too close to saturated light or dark.
    saturated = 3  # how close to the boundary do you need to be considered 'saturated'
    low_bound = -32768.0
    high_bound = 32767.0

    min_intensity = low_bound + saturated
    max_intensity = high_bound - saturated

    unsaturated_pixel_array = stacked_pixel_array[np.logical_and(stacked_pixel_array >= min_intensity, stacked_pixel_array < max_intensity)]

    unsaturated_count = unsaturated_pixel_array.size
    unsaturated_pct = (unsaturated_count * 100.0) / stacked_pixel_array.size
    logger.info(f"compress_compute: {unsaturated_count} real pixels, {unsaturated_pct} percent")

    mean = np.mean(unsaturated_pixel_array).item()

    # TODO: see if dat header QuantLow and QuantHigh values could be used instead since they seem to be
    #       the same as the swapped low and high values here (would allow us to skip stdDev calculation)
    std_dev = np.std(unsaturated_pixel_array).item()

    logger.info(f"compress_compute: Of the above image points, mean= {mean} and std dev = {std_dev}")

    # Convert mean-4*sigma -> 0, mean +4 sigma to 255.
    low = mean - (4 * std_dev)
    high = mean + (4 * std_dev)

    if low < low_bound:
        logger.info("minus 4 sigma < -32768.  Changing to 0")
        low = low_bound

    if high > high_bound:
        logger.info(" plus 4 sigma > 32767.  Changing to 65535")
        high = high_bound

    temp = low
    low = high
    high = temp  # swap low and high

    span = high - low
    logger.info(f"compress_compute: low {low:.2f}  -> 0, high {high:.2f} -> 255")

    for pixel_array in pixel_array_list:

        # create a float array of round-able converted values using the derived low-to-high 8-bit range
        compressed_data = 255.0 * ((pixel_array - low) / span) + 0.5

        # Lou's code converted values between -1.0 and 0.0 to 0 with an int(...) conversion.
        # This is covered by the compressed_data.astype(dtype=np.uint8 ... call,
        # so we only count values <= -1.0 as "too low".
        too_low_bool_array = compressed_data <= -1.0
        too_low_count = too_low_bool_array.sum()  # works because True = 1 and False = 0
        too_low_pct = (float(too_low_count) / compressed_data.size) * 100.0

        compressed_data[too_low_bool_array] = 0

        # Lou's code converted values between 255.0 and 256.0 to 255 with an int(...) conversion.
        # This is covered by the compressed_data.astype(dtype=np.uint8 ... call,
        # so we only count values >= 256.0 as "too high".
        too_high_bool_array = compressed_data >= 256.0
        too_high_count = too_high_bool_array.sum()  # works because True = 1 and False = 0
        too_high_pct = (float(too_high_count) / compressed_data.size) * 100.0

        compressed_data[too_high_bool_array] = 255

        logger.info(f"compress_compute: {too_low_count} ({too_low_pct:.5f}%) clipped to black, "
                    f"{too_high_count} ({too_high_pct:.5f}%) clipped to white")

        compressed_data_2d_np = compressed_data.astype(dtype=np.uint8)

        # return 2D compressed result as a 3D array (z, y, x)
        z_y_x_shape = (1, compressed_data_2d_np.shape[0], compressed_data_2d_np.shape[1])

        compressed_data_list.append(compressed_data_2d_np.reshape(z_y_x_shape))

    return compressed_data_list


def compress_and_save_layer(dat_path_list: list[Path],
                            compressed_path_list: list[Path]):
    """
    Compresses the specified list of dat files and saves them to the specified paths.

    Parameters
    ----------
    dat_path_list: Path
        list of source .dat paths.

    compressed_path_list: Path
        list of compressed output paths.
    """
    cyx_dat_record_list: list[np.ndarray] = []

    for dat_path in dat_path_list:
        dat_record = read(dat_path)
        # data comes in as x, y, c - we need to change it to c, x, y because dat reader no longer does that
        cyx_dat_record = np.rollaxis(dat_record, 2)
        logger.info(f"compress_and_save: loaded {cyx_dat_record.shape} {str(dat_path)}")
        cyx_dat_record_list.append(cyx_dat_record)

    compressed_data_list: list[np.ndarray] = compress_compute_layer(cyx_dat_record_list)

    for index in range(len(compressed_data_list)):
        compressed_path = compressed_path_list[index]
        compressed_record = compressed_data_list[index]
        im = Image.fromarray(compressed_record[0, :, :])
        im.save(compressed_path)
        logger.info(f"compress_and_save: saved {str(compressed_path)}")


if __name__ == '__main__':
    # NOTE: to fix module not found errors, export PYTHONPATH="/.../EM_recon_pipeline/src/python"

    init_logger(__file__)

    base_name = 'Merlin-6284_24-07-27_000003_0-0'
    # base_name = 'Merlin-6284_24-07-28_135631_0-0'
    dat_path_list = []
    compressed_path_list = []
    for column in range(1):
        dat_path_list.append(Path(f'/Users/trautmane/Desktop/16_to_8/dat/{base_name}-{column}.dat'))
        compressed_path_list.append(Path(f'/Users/trautmane/Desktop/16_to_8/out_test/{base_name}-{column}.png'))
    compress_and_save_layer(dat_path_list=dat_path_list,
                            compressed_path_list=compressed_path_list)
