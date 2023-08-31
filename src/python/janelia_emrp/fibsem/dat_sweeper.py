import argparse
import datetime
import logging
import sys
import time
import traceback
from pathlib import Path

from janelia_emrp.fibsem.dat_copier import add_dat_copy_arguments, copy_dat_file, day_range, \
    get_dats_acquired_on_day, get_scope_day_numbers_with_dats, max_transfer_seconds_exceeded
from janelia_emrp.fibsem.dat_path import dat_to_target_path, new_dat_path, new_dat_layer
from janelia_emrp.fibsem.h5_dat_name_helper import H5DatNameHelper
from janelia_emrp.fibsem.volume_transfer_info import build_volume_transfer_list, VolumeTransferInfo, VolumeTransferTask
from janelia_emrp.root_logger import init_logger

logger = logging.getLogger(__name__)


def parse_args(arg_list: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Finds scope dat files that are missing from network storage."
    )
    add_dat_copy_arguments(parser)
    # noinspection PyTypeChecker
    parser.add_argument(
        "--copy_missing",
        help="Copy (restore) any missing dat files to cluster dat storage",
        action=argparse.BooleanOptionalAction
    )
    parser.add_argument(
        "--dat_path_output_file",
        help="If specified, write all dat paths to this file and skip missing dat check"
    )
    parser.add_argument(
        "--first_dat",
        help="File name of first dat to verify (omit to use first dat from transfer info)",
    )
    parser.add_argument(
        "--last_dat",
        help="File name of last dat to verify (omit to use last dat from transfer info)",
    )
    parser.add_argument(
        "--num_workers",
        help="The number of workers to use for Dask (default of 1 indicates serial processing is desired)",
        type=int,
        default=1
    )
    parser.add_argument(
        "--parent_work_dir",
        help="Parent directory for Dask logs and worker data",
    )
    return parser.parse_args(args=arg_list)


def main(arg_list: list[str]):
    start_time = time.time()

    args = parse_args(arg_list)

    volume_transfer_dir_path = Path(args.volume_transfer_dir)
    volume_transfer_list: list[VolumeTransferInfo] = \
        build_volume_transfer_list(volume_transfer_dir_path=volume_transfer_dir_path,
                                   for_scope=args.scope,
                                   for_tasks=[VolumeTransferTask.COPY_SCOPE_DAT_TO_CLUSTER])

    max_transfer_seconds = None if args.max_transfer_minutes is None else args.max_transfer_minutes * 60
    total_missing_count = 0
    total_copy_count = 0

    with H5DatNameHelper(num_workers=args.num_workers,
                         dask_local_dir=args.parent_work_dir) as h5_dat_name_helper:

        for transfer_info in volume_transfer_list:
            copy_count, missing_count = check_volume(args,
                                                     max_transfer_seconds,
                                                     start_time,
                                                     transfer_info,
                                                     h5_dat_name_helper)
            total_copy_count += copy_count
            total_missing_count += missing_count

            if max_transfer_seconds_exceeded(max_transfer_seconds, start_time):
                break

    if max_transfer_seconds_exceeded(max_transfer_seconds, start_time):
        logger.info(f"main: stopping because elapsed time exceeds {max_transfer_seconds / 60} minutes")

    elapsed_seconds = int(time.time() - start_time)
    copy_msg = f"and restored {total_copy_count} of them in" if total_copy_count > 0 else "in"
    logger.info(f"main: found {total_missing_count} missing dat files {copy_msg} {elapsed_seconds} seconds")

    return 0


def check_volume(args: argparse.Namespace,
                 max_transfer_seconds: int,
                 start_time: float,
                 transfer_info: VolumeTransferInfo,
                 h5_dat_name_helper: H5DatNameHelper) -> (int, int):

    logger.info(f"check_volume: start processing for {transfer_info}")

    missing_count = 0
    copy_count = 0

    cluster_root_dat_path = transfer_info.cluster_root_paths.raw_dat
    if not cluster_root_dat_path.is_dir():
        raise ValueError(f"cluster_root_paths.raw_dat {cluster_root_dat_path} is not a directory")
    
    end_date, first_dat_acquire_time, last_dat_acquire_time = build_dates_and_times(args, transfer_info)
    month = None
    day_numbers = []

    logger.info(f"check_volume: checking dats imaged between {first_dat_acquire_time} and {end_date}")
    for day in day_range(first_dat_acquire_time, end_date):

        logger.info(f'check_volume: checking day {day.strftime("%y-%m-%d")}')
        if month is None or day.month != month:
            day_numbers = get_scope_day_numbers_with_dats(transfer_info.scope_data_set.host,
                                                          transfer_info.scope_data_set.root_dat_path,
                                                          day)
            month = day.month

        if day.day not in day_numbers:
            logger.info(f'check_volume: no dats imaged on {day.strftime("%y-%m-%d")}, skipping day')
            continue

        dat_list = get_dats_acquired_on_day(transfer_info.scope_data_set.host,
                                            transfer_info.scope_data_set.root_dat_path,
                                            day)

        if len(dat_list) > 0:
            if args.dat_path_output_file is not None:
                with open(args.dat_path_output_file, mode='a', encoding='utf-8') as dat_path_output_file:
                    dat_path_output_file.write('\n'.join([str(p) for p in dat_list]))
                logger.info(f'check_volume: wrote scope paths for {len(dat_list)} dat files '
                            f'imaged on {day.strftime("%y-%m-%d")} to {args.dat_path_output_file}')
                continue  # skip check for missing dat files when dat_path_output_file is specified

            raw_h5_dat_names_set = get_h5_dat_names(dat_list,
                                                    transfer_info,
                                                    h5_dat_name_helper)

            missing_scope_dat_paths = find_missing_dat_paths(cluster_root_dat_path,
                                                             dat_list,
                                                             first_dat_acquire_time,
                                                             last_dat_acquire_time,
                                                             raw_h5_dat_names_set)

            missing_count += len(missing_scope_dat_paths)

            if args.copy_missing:
                for scope_dat_path in missing_scope_dat_paths:
                    copy_dat_file(scope_host=transfer_info.scope_data_set.host,
                                  scope_dat_path=str(scope_dat_path),
                                  dat_storage_root=cluster_root_dat_path)
                    copy_count += 1
                    if max_transfer_seconds_exceeded(max_transfer_seconds, start_time):
                        break

        if max_transfer_seconds_exceeded(max_transfer_seconds, start_time):
            break

    return copy_count, missing_count


def build_dates_and_times(args: argparse.Namespace,
                          transfer_info: VolumeTransferInfo) -> (datetime, datetime, datetime):
    if args.first_dat is None:
        first_dat_acquire_time = transfer_info.scope_data_set.first_dat_acquire_time()
    else:
        first_dat_acquire_time = new_dat_path(file_path=Path(args.first_dat)).acquire_time

    if args.last_dat is None:
        last_dat_acquire_time = transfer_info.scope_data_set.last_dat_acquire_time()
    else:
        last_dat_acquire_time = new_dat_path(file_path=Path(args.last_dat)).acquire_time

    if last_dat_acquire_time is None:
        last_dat_acquire_time = datetime.datetime.now()

    end_date = last_dat_acquire_time + datetime.timedelta(days=1)
    end_date = end_date.replace(hour=23, minute=59, second=59, microsecond=999999)

    return end_date, first_dat_acquire_time, last_dat_acquire_time


def get_h5_dat_names(dat_list: list[Path],
                     transfer_info: VolumeTransferInfo,
                     h5_dat_name_helper: H5DatNameHelper) -> set[str]:

    raw_h5_cluster_root = transfer_info.get_raw_h5_cluster_root()
    raw_h5_archive_root = transfer_info.get_raw_h5_archive_root()
    align_h5_cluster_root = transfer_info.get_align_h5_cluster_root()

    raw_h5_dat_names = h5_dat_name_helper.raw_names_for_day(scope_dat_paths=dat_list,
                                                            raw_h5_archive_root=raw_h5_archive_root,
                                                            raw_h5_cluster_root=raw_h5_cluster_root)
    raw_h5_dat_names_set = set(raw_h5_dat_names)
    if transfer_info.get_align_h5_root_for_conversion() is not None:
        first_dat_path = new_dat_path(dat_list[0])
        first_dat_layer = new_dat_layer(first_dat_path)

        align_h5_dat_names = h5_dat_name_helper.names_for_day(layer_for_day=first_dat_layer,
                                                              h5_root_path=align_h5_cluster_root,
                                                              source_type="uint8")
        align_h5_dat_names_set = set(align_h5_dat_names)

        raw_v_align_diff = raw_h5_dat_names_set.difference(align_h5_dat_names_set)
        if len(raw_v_align_diff) > 0:
            logger.warning(f'get_h5_dat_names: found {len(raw_v_align_diff)} dat names in {raw_h5_archive_root} '
                           f'and {raw_h5_cluster_root} that are missing from {align_h5_cluster_root}')
            logger.info(f'get_h5_dat_names: missing align dats are {sorted(raw_v_align_diff)}')

        align_v_raw_diff = align_h5_dat_names_set.difference(raw_h5_dat_names_set)
        if len(align_v_raw_diff) > 0:
            logger.warning(f'get_h5_dat_names: found {len(align_v_raw_diff)} dat names in {align_h5_cluster_root} '
                           f'that are missing from {align_h5_cluster_root} and {raw_h5_cluster_root}')
            logger.info(f'get_h5_dat_names: missing raw dats are {sorted(align_v_raw_diff)}')

    return raw_h5_dat_names_set


def find_missing_dat_paths(cluster_root_dat_path: Path,
                           dat_list: list[Path],
                           first_dat_acquire_time: datetime,
                           last_dat_acquire_time: datetime,
                           raw_h5_dat_names_set: set[str]) -> list[Path]:
    missing_scope_dat_paths = []
    previous_layer_id = None
    previous_tiles_per_layer = None
    current_layer_id = None
    current_tiles_per_layer = None

    for scope_dat_path in dat_list:
        dat_path = new_dat_path(dat_to_target_path(scope_dat_path, cluster_root_dat_path))

        if current_layer_id is None:
            current_layer_id = dat_path.layer_id
            current_tiles_per_layer = 1
        elif dat_path.layer_id == current_layer_id:
            current_tiles_per_layer += 1
        else:  # new layer
            if previous_tiles_per_layer is not None and current_tiles_per_layer != previous_tiles_per_layer:
                logger.warning(f'find_missing_dat_paths: layer {current_layer_id} has {current_tiles_per_layer} tiles '
                               f'but layer {previous_layer_id} has {previous_tiles_per_layer} tiles')
            previous_layer_id = current_layer_id
            previous_tiles_per_layer = current_tiles_per_layer
            current_layer_id = dat_path.layer_id
            current_tiles_per_layer = 1

        if first_dat_acquire_time <= dat_path.acquire_time <= last_dat_acquire_time:
            if not dat_path.file_path.exists() and dat_path.file_path.name not in raw_h5_dat_names_set:
                logger.info(f"find_missing_dat_paths: {dat_path.file_path} is missing")
                missing_scope_dat_paths.append(scope_dat_path)

    return missing_scope_dat_paths


if __name__ == "__main__":
    # NOTE: to fix module not found errors, export PYTHONPATH="/.../EM_recon_pipeline/src/python"

    # setup logger since this module is the main program
    init_logger(__file__)

    # noinspection PyBroadException
    try:
        main(sys.argv[1:])
    except Exception as e:
        # ensure exit code is a non-zero value when Exception occurs
        traceback.print_exc()
        sys.exit(1)
