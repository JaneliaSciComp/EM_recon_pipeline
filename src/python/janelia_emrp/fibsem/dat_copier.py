import argparse
import datetime
import logging
import subprocess
import traceback
from pathlib import Path
from typing import Optional

import sys
import time

from janelia_emrp.fibsem.dat_keep_file import KeepFile, build_keep_file
from janelia_emrp.fibsem.dat_path import dat_to_target_path
from janelia_emrp.fibsem.volume_transfer_info import VolumeTransferInfo, VolumeTransferTask
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
                       data_set_id: str) -> list[KeepFile]:
    keep_file_list = []
    args = get_base_ssh_args(host)
    args.append(f'ls "{keep_file_root}"')

    completed_process = subprocess.run(args,
                                       capture_output=True,
                                       check=True)
    for name in completed_process.stdout.decode("utf-8").split("\n"):
        name = name.strip()
        if name.endswith("^keep"):
            keep_file = build_keep_file(host, str(keep_file_root), name)
            if keep_file is not None and keep_file.data_set == data_set_id:
                keep_file_list.append(keep_file)

    return keep_file_list


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


def build_volume_transfer_list(volume_transfer_dir_path: Path,
                               scope: Optional[str]):
    volume_transfer_list: list[VolumeTransferInfo] = []

    f_name = "build_volume_transfer_list"

    if volume_transfer_dir_path.is_dir():
        for path in volume_transfer_dir_path.glob("volume_transfer*.json"):

            transfer_info: VolumeTransferInfo = VolumeTransferInfo.parse_file(path)

            if transfer_info.includes_task(VolumeTransferTask.COPY_SCOPE_DAT_TO_CLUSTER):
                if transfer_info.cluster_root_paths is None:
                    logger.info(f"{f_name}: ignoring {transfer_info} because cluster_root_paths not defined")
                elif transfer_info.acquisition_started():
                    if scope is None or scope == transfer_info.scope_data_set.host:
                        volume_transfer_list.append(transfer_info)
                    else:
                        logger.info(f"{f_name}: ignoring {transfer_info} because scope differs")
                else:
                    logger.info(f"{f_name}: ignoring {transfer_info} because acquisition has not started")
            else:
                logger.info(f"{f_name}: ignoring {transfer_info} because it does not include copy task")
    else:
        raise ValueError(f"volume_transfer_dir {volume_transfer_dir_path} is not a directory")

    return volume_transfer_list


def max_transfer_seconds_exceeded(max_transfer_seconds: int,
                                  start_time: float):
    result = False
    if max_transfer_seconds is not None:
        elapsed_seconds = time.time() - start_time
        result = elapsed_seconds > max_transfer_seconds
    return result


def main(arg_list: list[str]):
    start_time = time.time()

    parser = argparse.ArgumentParser(
        description="Copies dat files identified by keep files on remote scope."
    )
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

    args = parser.parse_args(args=arg_list)

    max_transfer_seconds = None if args.max_transfer_minutes is None else args.max_transfer_minutes * 60

    volume_transfer_dir_path = Path(args.volume_transfer_dir)
    volume_transfer_list: list[VolumeTransferInfo] = build_volume_transfer_list(volume_transfer_dir_path,
                                                                                args.scope)
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
                                            data_set_id=transfer_info.scope_data_set.data_set_id)

        logger.info(f"main: found {len(keep_file_list)} keep files on {transfer_info.scope_data_set.host} for the "
                    f"{transfer_info.scope_data_set.data_set_id} data set")

        if len(keep_file_list) > 0:
            logger.info(f"main: start copying dat files to {cluster_root_dat_path}")
            logger.info(f"main: first keep file is {keep_file_list[0].keep_path}")
            logger.info(f"main: last keep file is {keep_file_list[-1].keep_path}")

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
