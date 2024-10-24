import argparse
import datetime
import glob
import logging
import re
import subprocess
import traceback
from pathlib import Path
from typing import Dict, Optional

import sys
import time

from janelia_emrp.fibsem.dat_keep_file import KeepFile, build_keep_file
from janelia_emrp.fibsem.dat_path import dat_to_target_path, new_dat_path, DAT_TIME_FORMAT
from janelia_emrp.fibsem.h5_dat_name_helper import H5DatNameHelper
from janelia_emrp.fibsem.volume_transfer_info import VolumeTransferInfo, VolumeTransferTask, build_volume_transfer_list
from janelia_emrp.root_logger import init_logger

logger = logging.getLogger(__name__)


def get_base_ssh_args(host: str):
    return [
        "ssh",                             # see https://man.openbsd.org/ssh_config.5 for descriptions of ssh -o args
        "-o", "ConnectTimeout=10",
        "-o", "ServerAliveCountMax=2",
        "-o", "ServerAliveInterval=5",
        "-o", "StrictHostKeyChecking=no",  # Disable checking to avoid problems when scopes get new IPs
        host
    ]


def get_keep_file_list(host: str,
                       keep_file_root: Path,
                       data_set_id: str,
                       first_dat_name: str,
                       last_dat_name: str) -> list[KeepFile]:
    keep_file_list = []
    args = get_base_ssh_args(host)
    args.append(f'ls "{keep_file_root}"')

    completed_process = subprocess.run(args,
                                       capture_output=True,
                                       check=True)
    for name in completed_process.stdout.decode("utf-8").split("\n"):
        name = name.strip()

        if name.endswith("^keep"):
            # jrc_celegans_20241007^E^^Images^C_elegans^Y2024^M10^D24^Merlin-6281_24-10-24_100613_0-0-0.dat^keep
            name_pieces = name.split("^")

            if len(name_pieces) > 2:
                dat_data_set_id = name_pieces[0]
                dat_name = name_pieces[-2]

                if (dat_data_set_id == data_set_id) and (dat_name >= first_dat_name) and \
                        ((last_dat_name is None) or (dat_name <= last_dat_name)):

                    keep_file = build_keep_file(host, str(keep_file_root), name)
                    if keep_file is not None:
                        keep_file_list.append(keep_file)



    return keep_file_list


def get_scope_day_numbers_with_dats(host: str,
                                    dat_storage_root: Path,
                                    for_month_of: datetime.datetime) -> list[int]:
    # /cygdrive/E/Images/Mouse/Y2022/M07
    month_path = dat_storage_root / for_month_of.strftime("Y%Y/M%m")

    logger.info(f"get_scope_day_numbers_with_dats: checking {month_path} on {host}")

    day_numbers: list[int] = []
    args = get_base_ssh_args(host)
    args.append(f'ls "{month_path}"')

    completed_process = subprocess.run(args,
                                       capture_output=True,
                                       check=True)
    for name in completed_process.stdout.decode("utf-8").split("\n"):
        name = name.strip()
        if name.startswith("D"):
            day_numbers.append(int(name[1:]))

    return day_numbers


def get_dats_acquired_on_day(host: str,
                             dat_storage_root: Path,
                             acquisition_date: datetime.datetime) -> list[Path]:
    # /cygdrive/E/Images/Mouse/Y2022/M07/D13
    day_path = dat_storage_root / acquisition_date.strftime("Y%Y/M%m/D%d")

    logger.info(f"get_dats_acquired_on_day: checking {day_path} on {host}")

    dat_list: list[Path] = []
    args = get_base_ssh_args(host)
    args.append(f'ls "{day_path}"')

    completed_process = subprocess.run(args,
                                       capture_output=True,
                                       check=True)
    for name in completed_process.stdout.decode("utf-8").split("\n"):
        name = name.strip()
        if name.endswith(".dat"):
            dat_list.append(day_path / name)

    return dat_list


def copy_dat_file(scope_host: str,
                  scope_dat_path: [Path, str],
                  dat_storage_root: Path):

    logger.info(f"copy_dat_file: copying {scope_dat_path}")

    target_dir: Path = dat_to_target_path(scope_dat_path, dat_storage_root).parent
    target_dir.mkdir(parents=True, exist_ok=True)

    host_prefix = "" if scope_host is None or len(scope_host) == 0 else f"{scope_host}:"

    args = [
        "scp",
        "-T",                              # needed to avoid protocol error: filename does not match request
        "-o", "ConnectTimeout=10",
        "-o", "StrictHostKeyChecking=no",  # Disable checking to avoid problems when scopes get new IPs
        f'{host_prefix}"{scope_dat_path}"',
        str(target_dir)
    ]

    subprocess.run(args, check=True)


def remove_keep_file(keep_file: KeepFile):
    logger.info(f"remove_keep_file: removing {keep_file.keep_path}")

    args = get_base_ssh_args(keep_file.host)
    args.append(f'rm "{keep_file.keep_path}"')

    subprocess.run(args, check=True)


def day_range(start_date: datetime.datetime,
              end_date: datetime.datetime):
    for n in range(int((end_date - start_date).days)):
        yield start_date + datetime.timedelta(n)


def max_transfer_seconds_exceeded(max_transfer_seconds: int,
                                  start_time: float):
    result = False
    if max_transfer_seconds is not None:
        elapsed_seconds = time.time() - start_time
        result = elapsed_seconds > max_transfer_seconds
    return result


def derive_missing_check_start_from_path(root_path: Path,
                                         dir_pattern: str,
                                         file_pattern: str) -> Optional[datetime.datetime]:
    nothing_missing_before: Optional[datetime.datetime] = None

    if root_path is not None and root_path.exists():
        logger.info(f"derive_missing_check_start_from_path: checking {root_path}")
        dir_list = sorted(glob.glob(dir_pattern))
        if len(dir_list) > 0:
            dir_and_file_pattern = f"{dir_list[-1]}{file_pattern}"
            latest_hour_files = [] if len(dir_list) == 0 else sorted(glob.glob(dir_and_file_pattern))

            if len(latest_hour_files) > 0:
                latest_file = latest_hour_files[-1]
                if latest_file.endswith(".h5"):
                    latest_file = re.sub(r"\.raw.*h5", "_0-0-0.dat", latest_file)
                latest_dat_path = new_dat_path(Path(latest_file))
                nothing_missing_before = latest_dat_path.acquire_time
                logger.info(f"derive_missing_check_start_from_path: used {latest_hour_files[-1]} as source")

    return nothing_missing_before


def derive_missing_check_start(last_dat_time_path: Path,
                               transfer_info: VolumeTransferInfo) -> datetime:
    nothing_missing_before: Optional[datetime] = None

    if last_dat_time_path.exists():
        logger.info(f"derive_missing_check_start: reading {last_dat_time_path}")
        # noinspection PyBroadException
        try:
            last_dat_time_str = last_dat_time_path.read_text()
            nothing_missing_before = datetime.datetime.strptime(last_dat_time_str, DAT_TIME_FORMAT)
            logger.info(f"derive_missing_check_start: used {last_dat_time_path} as source")
        except Exception:
            logger.exception(f"caught exception attempting to read {last_dat_time_path}")
            nothing_missing_before = None

    if nothing_missing_before is None:
        # /groups/cellmap/cellmap/render/dat/jrc_zf-cardiac-1
        #   /2022/07/08/23/Merlin-6257_22-07-08_230122_0-0-0.dat
        dir_pattern = f"{transfer_info.cluster_root_paths.raw_dat}/2*/*/*/*/"
        nothing_missing_before = \
            derive_missing_check_start_from_path(root_path=transfer_info.cluster_root_paths.raw_dat,
                                                 dir_pattern=dir_pattern,
                                                 file_pattern="*.dat")

    if nothing_missing_before is None:
        # /groups/cellmap/cellmap/render/h5/jrc_zf-cardiac-1/raw
        #  /Merlin-6257/2022/07/08/23/Merlin-6257_22-07-08_230122.raw.h5
        dir_pattern = f"{transfer_info.cluster_root_paths.raw_h5}/*/2*/*/*/*/"
        nothing_missing_before = \
            derive_missing_check_start_from_path(root_path=transfer_info.cluster_root_paths.raw_h5,
                                                 dir_pattern=dir_pattern,
                                                 file_pattern="*.h5")

    if nothing_missing_before is None:
        # /groups/cellmap/cellmap/render/h5/jrc_zf-cardiac-1/raw
        #  /Merlin-6257/2022/07/08/23/Merlin-6257_22-07-08_230122.raw.h5
        dir_pattern = f"{transfer_info.archive_root_paths.raw_h5}/*/2*/*/*/*/"
        nothing_missing_before = \
            derive_missing_check_start_from_path(root_path=transfer_info.archive_root_paths.raw_h5,
                                                 dir_pattern=dir_pattern,
                                                 file_pattern="*.h5")

    if nothing_missing_before is None:
        nothing_missing_before = transfer_info.scope_data_set.first_dat_acquire_time()

    logger.info(f"derive_missing_check_start: returning {nothing_missing_before.strftime('%Y-%m-%d %H:%M:%S')}")

    return nothing_missing_before


def find_missing_scope_dats_for_day(scope_dat_paths: list[Path],
                                    cluster_root_dat_path: Path,
                                    h5_dat_names_for_day: list[str],
                                    start_time: datetime.datetime,
                                    stop_time: datetime.datetime,
                                    first_keep_file: KeepFile,
                                    last_keep_file: KeepFile,
                                    time_to_keep_files: Dict[datetime.datetime, list[KeepFile]]):

    missing_scope_dats: list[Path] = []

    first_keep_file_dat_name = Path(first_keep_file.dat_path).name
    last_keep_file_dat_name = Path(last_keep_file.dat_path).name

    keep_layer_times = time_to_keep_files.keys()

    h5_dat_names_set = set(h5_dat_names_for_day)

    for scope_dat in scope_dat_paths:
        is_missing = True

        dat_path = new_dat_path(dat_to_target_path(scope_dat, cluster_root_dat_path))

        if start_time <= dat_path.acquire_time <= stop_time:
            if dat_path.acquire_time in keep_layer_times:
                for keep_file in time_to_keep_files[dat_path.acquire_time]:
                    # use case-insensitive comparison for Windows paths
                    if keep_file.dat_path.casefold() == str(scope_dat).casefold():
                        is_missing = False
                        break
                if is_missing:
                    # check for dats in same layer as first or last keep files
                    if dat_path.file_path.name < first_keep_file_dat_name:
                        is_missing = not dat_path.file_path.exists()
                    elif dat_path.file_path.name > last_keep_file_dat_name:
                        is_missing = False

            else:
                is_missing = not dat_path.file_path.exists()
        else:
            is_missing = False

        if is_missing:
            is_missing = dat_path.file_path.name not in h5_dat_names_set

        if is_missing:
            logger.info(f"find_missing_scope_dats_for_day: {scope_dat} is missing")
            missing_scope_dats.append(scope_dat)

    return missing_scope_dats


def find_missing_scope_dats(keep_file_list: list[KeepFile],
                            nothing_missing_before: datetime.datetime,
                            transfer_info: VolumeTransferInfo) -> list[Path]:

    missing_scope_dats: list[Path] = []

    scope_data_set = transfer_info.scope_data_set
    cluster_root_dat_path = transfer_info.cluster_root_paths.raw_dat
    raw_h5_cluster_root = transfer_info.get_raw_h5_cluster_root()
    raw_h5_archive_root = transfer_info.get_raw_h5_archive_root()

    last_keep_time = keep_file_list[-1].acquire_time()
    day_after_last_keep_time = last_keep_time + datetime.timedelta(days=1)
    day_after_last_keep_time = day_after_last_keep_time.replace(hour=23, minute=59, second=59, microsecond=999999)

    formatted_start = nothing_missing_before.strftime("%y-%m-%d %H:%M:%S")
    formatted_stop = last_keep_time.strftime("%y-%m-%d %H:%M:%S")
    logger.info(f"find_missing_scope_dats: checking {formatted_start} to {formatted_stop}")

    time_to_keep_files: Dict[datetime.datetime, list[KeepFile]] = {}
    for keep_file in keep_file_list:
        keep_files_for_time = time_to_keep_files.setdefault(keep_file.acquire_time(), [])
        keep_files_for_time.append(keep_file)

    h5_dat_name_helper = H5DatNameHelper(num_workers=1, dask_local_dir=None)
    month = None
    day_numbers = []

    for day in day_range(nothing_missing_before, day_after_last_keep_time):

        if month is None or day.month != month:
            day_numbers = get_scope_day_numbers_with_dats(scope_data_set.host,
                                                          scope_data_set.root_dat_path,
                                                          day)
            month = day.month
            
        if day.day not in day_numbers:
            logger.info(f'find_missing_scope_dats: no dats imaged on {day.strftime("%y-%m-%d")}, skipping day')
            continue

        scope_dat_paths = get_dats_acquired_on_day(scope_data_set.host,
                                                   scope_data_set.root_dat_path,
                                                   day)

        h5_dat_names_for_day = h5_dat_name_helper.raw_names_for_day(scope_dat_paths=scope_dat_paths,
                                                                    raw_h5_archive_root=raw_h5_archive_root,
                                                                    raw_h5_cluster_root=raw_h5_cluster_root)

        missing_scope_dats.extend(
            find_missing_scope_dats_for_day(scope_dat_paths=scope_dat_paths,
                                            cluster_root_dat_path=cluster_root_dat_path,
                                            h5_dat_names_for_day=h5_dat_names_for_day,
                                            start_time=nothing_missing_before,
                                            stop_time=last_keep_time,
                                            first_keep_file=keep_file_list[0],
                                            last_keep_file=keep_file_list[-1],
                                            time_to_keep_files=time_to_keep_files))
    return missing_scope_dats


def add_dat_copy_arguments(parser):
    parser.add_argument(
        "--volume_transfer_dir",
        help="Path of directory containing volume_transfer_info.json files",
        required=True,
    )
    parser.add_argument(
        "--scope",
        help="If specified, only process volumes being acquired on this scope"
    )
    parser.add_argument(
        "--max_transfer_minutes",
        type=int,
        help="If specified, stop copying after this number of minutes has elapsed",
    )


def main(arg_list: list[str]):
    start_time = time.time()

    parser = argparse.ArgumentParser(
        description="Copies dat files identified by keep files on remote scope."
    )
    add_dat_copy_arguments(parser)
    args = parser.parse_args(args=arg_list)

    max_transfer_seconds = None if args.max_transfer_minutes is None else args.max_transfer_minutes * 60

    volume_transfer_dir_path = Path(args.volume_transfer_dir)
    volume_transfer_list: list[VolumeTransferInfo] = \
        build_volume_transfer_list(volume_transfer_dir_path=volume_transfer_dir_path,
                                   for_scope=args.scope,
                                   for_tasks=[VolumeTransferTask.COPY_SCOPE_DAT_TO_CLUSTER])
    copy_count = 0

    stop_processing = False
    for transfer_info in volume_transfer_list:

        logger.info(f"main: start processing for {transfer_info}")

        cluster_root_dat_path = transfer_info.cluster_root_paths.raw_dat
        if not cluster_root_dat_path.exists():
            logger.info(f"main: creating cluster_root_paths.raw_dat directory {cluster_root_dat_path}")
            cluster_root_dat_path.mkdir(parents=True)

        if not cluster_root_dat_path.is_dir():
            raise ValueError(f"cluster_root_paths.raw_dat {cluster_root_dat_path} is not a directory")

        keep_file_list = get_keep_file_list(host=transfer_info.scope_data_set.host,
                                            keep_file_root=transfer_info.scope_data_set.root_keep_path,
                                            data_set_id=transfer_info.scope_data_set.data_set_id,
                                            first_dat_name=transfer_info.scope_data_set.first_dat_name,
                                            last_dat_name=transfer_info.scope_data_set.last_dat_name)

        logger.info(f"main: found {len(keep_file_list)} keep files on {transfer_info.scope_data_set.host} for the "
                    f"{transfer_info.scope_data_set.data_set_id} data set for dat files with names between "
                    f"{transfer_info.scope_data_set.first_dat_name} and {transfer_info.scope_data_set.last_dat_name}")

        last_dat_time_path: Path = cluster_root_dat_path / "last_dat_time.txt"
        nothing_missing_before = derive_missing_check_start(last_dat_time_path=last_dat_time_path,
                                                            transfer_info=transfer_info)

        if len(keep_file_list) > 0:
            logger.info(f"main: start copying dat files to {cluster_root_dat_path}")
            logger.info(f"main: first keep file is {keep_file_list[0].keep_path}")
            logger.info(f"main: last keep file is {keep_file_list[-1].keep_path}")

            missing_scope_dats = find_missing_scope_dats(keep_file_list=keep_file_list,
                                                         nothing_missing_before=nothing_missing_before,
                                                         transfer_info=transfer_info)
            if len(missing_scope_dats) > 0:
                missing_dat_list_path: Path = cluster_root_dat_path / "missing_dat_list.txt"
                with open(missing_dat_list_path, 'a', encoding='utf-8') as missing_dat_list_file:
                    for scope_dat in missing_scope_dats:
                        missing_dat_list_file.write(f"{str(scope_dat)}\n")
                logger.info(f"main: added {len(missing_scope_dats)} missing dat file paths to {missing_dat_list_path}")

            # noinspection PyBroadException
            try:
                # save last dat time so checks are not repeated by subsequent runs
                last_dat_time_str = keep_file_list[-1].acquire_time().strftime(DAT_TIME_FORMAT)
                logger.info(f"main: saving {last_dat_time_str} to {last_dat_time_path}")
                last_dat_time_path.write_text(last_dat_time_str)
            except Exception:
                logger.exception(f"caught exception attempting to write {last_dat_time_path}")

        for keep_file in keep_file_list:
            copy_dat_file(scope_host=keep_file.host,
                          scope_dat_path=keep_file.dat_path,
                          dat_storage_root=cluster_root_dat_path)

            remove_keep_file(keep_file)

            copy_count += 1

            if max_transfer_seconds_exceeded(max_transfer_seconds, start_time):
                stop_processing = True
                break

        if stop_processing:
            break

    if stop_processing:
        logger.info(f"main: stopping because elapsed time exceeds {max_transfer_seconds / 60} minutes")

    elapsed_seconds = int(time.time() - start_time)
    logger.info(f"main: transferred {copy_count} dat files in {elapsed_seconds} seconds")

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
