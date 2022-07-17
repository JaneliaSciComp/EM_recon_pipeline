import argparse
import logging
import subprocess
import traceback
from pathlib import Path

import sys
import time

from janelia_emrp.fibsem.dat_keep_file import KeepFile, build_keep_file
from janelia_emrp.fibsem.dat_path import new_dat_path
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
                       keep_file_root: Path) -> list[KeepFile]:
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
            if keep_file is not None:
                keep_file_list.append(keep_file)

    return keep_file_list


def copy_dat_file(keep_file: KeepFile,
                  dat_storage_root: Path):

    dat_path = new_dat_path(Path(keep_file.dat_path))
    hourly_relative_path_string = dat_path.acquire_time.strftime("%Y/%m/%d/%H")
    target_dir = dat_storage_root / hourly_relative_path_string
    target_dir.mkdir(parents=True, exist_ok=True)

    args = [
        "scp",
        "-T",                              # needed to avoid protocol error: filename does not match request
        "-o", "ConnectTimeout=10",
        "-o", "StrictHostKeyChecking=no",  # Disable checking to avoid problems when scopes get new IPs
        f'{keep_file.host_prefix()}"{keep_file.dat_path}"',
        str(target_dir)
    ]

    subprocess.run(args, check=True)


def remove_keep_file(keep_file: KeepFile):
    args = get_base_ssh_args(keep_file.host)
    args.append(f'rm "{keep_file.keep_path}"')

    subprocess.run(args, check=True)


def main(arg_list):

    init_logger(__file__)

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
    volume_transfer_list: list[VolumeTransferInfo] = []
    if volume_transfer_dir_path.is_dir():
        for path in volume_transfer_dir_path.glob("volume_transfer*.json"):

            transfer_info: VolumeTransferInfo = VolumeTransferInfo.parse_file(path)

            if transfer_info.includes_task(VolumeTransferTask.COPY_SCOPE_DAT_TO_CLUSTER):
                if transfer_info.cluster_root_paths is None:
                    logger.info(f"main: ignoring {transfer_info} because cluster_root_paths not defined")
                elif transfer_info.acquisition_started_for_scope(args.scope):
                    volume_transfer_list.append(transfer_info)
                else:
                    logger.info(f"main: ignoring {transfer_info} because scope differs or acquisition has not started")
            else:
                logger.info(f"main: ignoring {transfer_info} because it does not include copy task")
    else:
        raise ValueError(f"volume_transfer_dir {args.volume_transfer_dir} is not a directory")

    copy_count = 0

    stop_processing = False
    for transfer_info in volume_transfer_list:

        logger.info(f"main: start processing for {transfer_info}")

        raw_dat_path = transfer_info.cluster_root_paths.raw_dat
        if not raw_dat_path.exists():
            logger.info(f"main: creating cluster_root_paths.raw_dat directory {raw_dat_path}")
            raw_dat_path.mkdir(parents=True)

        if not raw_dat_path.is_dir():
            raise ValueError(f"cluster_root_paths.raw_dat {raw_dat_path} is not a directory")

        keep_file_list = get_keep_file_list(host=transfer_info.scope_data_set.host,
                                            keep_file_root=transfer_info.scope_data_set.root_keep_path)

        logger.info(f"main: found {len(keep_file_list)} keep files on {transfer_info.scope_data_set.host}, "
                    f"will copy dat files to {raw_dat_path}")

        for keep_file in keep_file_list:

            logger.info(f"main: copying {keep_file.dat_path}")

            copy_dat_file(keep_file=keep_file,
                          dat_storage_root=raw_dat_path)

            logger.info(f"main: removing {keep_file.keep_path}")

            remove_keep_file(keep_file)

            copy_count += 1

            if max_transfer_seconds is not None:
                elapsed_seconds = time.time() - start_time
                if elapsed_seconds > max_transfer_seconds:
                    logger.info(f"main: stopping because elapsed time exceeds {max_transfer_seconds / 60} minutes")
                    stop_processing = True
                    break

        if stop_processing:
            break

    elapsed_seconds = int(time.time() - start_time)
    logger.info(f"main: transferred {copy_count} dat files in {elapsed_seconds} seconds")

    return 0


if __name__ == "__main__":
    # noinspection PyBroadException
    try:
        main(sys.argv[1:])
    except Exception as e:
        traceback.print_exc()
        sys.exit(1)
