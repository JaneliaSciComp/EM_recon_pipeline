import argparse
import datetime
import logging
import traceback
from pathlib import Path

import sys
import time

from janelia_emrp.fibsem.dat_copier import add_dat_copy_arguments, copy_dat_file, day_range, \
    get_dats_acquired_on_day, get_scope_day_numbers_with_dats, max_transfer_seconds_exceeded, \
    get_h5_dat_names_for_day, get_h5_raw_dat_names_for_day
from janelia_emrp.fibsem.dat_path import dat_to_target_path, new_dat_path, new_dat_layer
from janelia_emrp.fibsem.volume_transfer_info import build_volume_transfer_list, VolumeTransferInfo, VolumeTransferTask
from janelia_emrp.root_logger import init_logger

logger = logging.getLogger(__name__)


def main(arg_list: list[str]):
    start_time = time.time()

    parser = argparse.ArgumentParser(
        description="Finds scope dat files that are missing from network storage."
    )
    add_dat_copy_arguments(parser)
    parser.add_argument(
        "--copy_missing",
        help="Copy (restore) any missing dat files to cluster dat storage",
        action=argparse.BooleanOptionalAction
    )
    parser.add_argument(
        "--dat_path_output_file",
        help="If specified, write all dat paths to this file and skip missing dat check"
    )

    args = parser.parse_args(args=arg_list)

    max_transfer_seconds = None if args.max_transfer_minutes is None else args.max_transfer_minutes * 60

    volume_transfer_dir_path = Path(args.volume_transfer_dir)
    volume_transfer_list: list[VolumeTransferInfo] = \
        build_volume_transfer_list(volume_transfer_dir_path=volume_transfer_dir_path,
                                   for_scope=args.scope,
                                   for_tasks=[VolumeTransferTask.COPY_SCOPE_DAT_TO_CLUSTER])

    missing_count = 0
    copy_count = 0

    stop_processing = False
    for transfer_info in volume_transfer_list:

        logger.info(f"main: start processing for {transfer_info}")

        cluster_root_dat_path = transfer_info.cluster_root_paths.raw_dat
        if not cluster_root_dat_path.is_dir():
            raise ValueError(f"cluster_root_paths.raw_dat {cluster_root_dat_path} is not a directory")

        first_dat_acquire_time = transfer_info.scope_data_set.first_dat_acquire_time()
        last_dat_acquire_time = transfer_info.scope_data_set.last_dat_acquire_time()
        if last_dat_acquire_time is None:
            last_dat_acquire_time = datetime.datetime.now()

        end_date = last_dat_acquire_time + datetime.timedelta(days=1)
        end_date = end_date.replace(hour=23, minute=59, second=59, microsecond=999999)

        raw_h5_cluster_root = transfer_info.get_raw_h5_cluster_root()
        raw_h5_archive_root = transfer_info.get_raw_h5_archive_root()
        align_h5_cluster_root = transfer_info.get_align_h5_cluster_root()

        month = None
        day_numbers = []

        logger.info(f"main: checking dats imaged between {first_dat_acquire_time} and {end_date}")

        for day in day_range(first_dat_acquire_time, end_date):

            if month is None or day.month != month:
                day_numbers = get_scope_day_numbers_with_dats(transfer_info.scope_data_set.host,
                                                              transfer_info.scope_data_set.root_dat_path,
                                                              day)
                month = day.month

            if day.day not in day_numbers:
                logger.info(f'main: no dats imaged on {day.strftime("%y-%m-%d")}, skipping day')
                continue

            dat_list = get_dats_acquired_on_day(transfer_info.scope_data_set.host,
                                                transfer_info.scope_data_set.root_dat_path,
                                                day)

            raw_h5_dat_names_set = set()

            if len(dat_list) > 0:
                if args.dat_path_output_file is not None:
                    with open(args.dat_path_output_file, mode='a', encoding='utf-8') as dat_path_output_file:
                        dat_path_output_file.write('\n'.join([str(p) for p in dat_list]))
                    logger.info(f'main: wrote scope paths for {len(dat_list)} dat files '
                                f'imaged on {day.strftime("%y-%m-%d")} to {args.dat_path_output_file}')
                    continue  # skip check for missing dat files when dat_path_output_file is specified

                raw_h5_dat_names = get_h5_raw_dat_names_for_day(scope_dat_paths=dat_list,
                                                                raw_h5_archive_root=raw_h5_archive_root,
                                                                raw_h5_cluster_root=raw_h5_cluster_root)
                raw_h5_dat_names_set = set(raw_h5_dat_names)

                if transfer_info.get_align_h5_root_for_conversion() is not None:
                    first_dat_path = new_dat_path(dat_list[0])
                    first_dat_layer = new_dat_layer(first_dat_path)

                    align_h5_dat_names = get_h5_dat_names_for_day(layer_for_day=first_dat_layer,
                                                                  h5_root_path=align_h5_cluster_root,
                                                                  source_type="uint8")
                    align_h5_dat_names_set = set(align_h5_dat_names)

                    raw_v_align_diff = raw_h5_dat_names_set.difference(align_h5_dat_names_set)
                    if len(raw_v_align_diff) > 0:
                        logger.warning(f'main: found {len(raw_v_align_diff)} dat names in {raw_h5_archive_root} '
                                       f'and {raw_h5_cluster_root} that are missing from {align_h5_cluster_root}')
                        logger.info(f'main: missing align dats are {sorted(raw_v_align_diff)}')

                    align_v_raw_diff = align_h5_dat_names_set.difference(raw_h5_dat_names_set)
                    if len(align_v_raw_diff) > 0:
                        logger.warning(f'main: found {len(align_v_raw_diff)} dat names in {align_h5_cluster_root} '
                                       f'that are missing from {align_h5_cluster_root} and {raw_h5_cluster_root}')
                        logger.info(f'main: missing raw dats are {sorted(align_v_raw_diff)}')

            for scope_dat_path in dat_list:
                dat_path = new_dat_path(dat_to_target_path(scope_dat_path, cluster_root_dat_path))

                if first_dat_acquire_time <= dat_path.acquire_time <= last_dat_acquire_time:
                    if not dat_path.file_path.exists() and dat_path.file_path.name not in raw_h5_dat_names_set:

                        logger.info(f"main: {dat_path.file_path} is missing")
                        missing_count += 1

                        if args.copy_missing:
                            copy_dat_file(scope_host=transfer_info.scope_data_set.host,
                                          scope_dat_path=scope_dat_path,
                                          dat_storage_root=cluster_root_dat_path)
                            copy_count += 1

                            if max_transfer_seconds_exceeded(max_transfer_seconds, start_time):
                                stop_processing = True
                                break

            if stop_processing or max_transfer_seconds_exceeded(max_transfer_seconds, start_time):
                stop_processing = True
                break

        if stop_processing or max_transfer_seconds_exceeded(max_transfer_seconds, start_time):
            stop_processing = True
            break

    if stop_processing:
        logger.info(f"main: stopping because elapsed time exceeds {max_transfer_seconds / 60} minutes")

    elapsed_seconds = int(time.time() - start_time)
    copy_msg = f"and restored {copy_count} of them in" if copy_count > 0 else "in"
    logger.info(f"main: found {missing_count} missing dat files {copy_msg} {elapsed_seconds} seconds")

    return 0


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
