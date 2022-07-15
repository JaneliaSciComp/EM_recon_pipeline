import argparse
import logging
import subprocess
from typing import Optional

import sys
from pathlib import Path

import time

from janelia_emrp.fibsem.dat_keep_file import KeepFile, build_keep_file
from janelia_emrp.fibsem.volume_transfer_info import VolumeTransferInfo
from janelia_emrp.root_logger import init_logger

logger = logging.getLogger(__name__)


def get_base_ssh_args(host: Optional[str]):
    if host is not None and len(host) > 0:
        # see https://man.openbsd.org/ssh_config.5 for descriptions of ssh -o args
        args = [
            "ssh",
            "-o", "ConnectTimeout=10",
            "-o", "ServerAliveCountMax=2",
            "-o", "ServerAliveInterval=5",
            "-o", "StrictHostKeyChecking=no",  # Disable checking to avoid problems when scopes get new IPs
            host
        ]
    else:
        args = []
    return args


def get_keep_file_list(host: str,
                       keep_file_root: str) -> list[KeepFile]:
    keep_file_list = []
    args = get_base_ssh_args(host)
    args.append(f'ls "{keep_file_root}"')

    completed_process = subprocess.run(args,
                                       capture_output=True,
                                       check=True)
    for name in completed_process.stdout.decode("utf-8").split("\n"):
        name = name.strip()
        if name.endswith("^keep"):
            keep_file = build_keep_file(host, keep_file_root, name)
            if keep_file is not None:
                keep_file_list.append(keep_file)

    return keep_file_list


def copy_dat_file(keep_file: KeepFile,
                  dat_storage_root: Path):

    # see https://man.openbsd.org/ssh_config.5 for descriptions of ssh -o args
    args = [
        "scp",
        "-T",                              # needed to avoid protocol error: filename does not match request
        "-o", "ConnectTimeout=10",
        "-o", "StrictHostKeyChecking=no",  # Disable checking to avoid problems when scopes get new IPs
        f'{keep_file.host_prefix()}"{keep_file.dat_path}"',
        str(dat_storage_root)
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
            volume_transfer_info: VolumeTransferInfo = VolumeTransferInfo.parse_file(path)
            if args.scope is None or args.scope == volume_transfer_info.scope:
                if not volume_transfer_info.acquisition_started():
                    logger.info(f"main: ignoring {volume_transfer_info} because acquisition has not started")
                elif not volume_transfer_info.scope_defined():
                    logger.info(f"main: ignoring {volume_transfer_info} because scope is not defined")
                else:
                    volume_transfer_list.append(volume_transfer_info)

    else:
        raise ValueError(f"volume_transfer_dir {args.volume_transfer_dir} is not a directory")

    copy_count = 0

    stop_processing = False
    for volume_transfer_info in volume_transfer_list:

        if not volume_transfer_info.dat_storage_root.exists():
            logger.info(f"main: creating dat storage root {str(volume_transfer_info.dat_storage_root)}")
            volume_transfer_info.dat_storage_root.mkdir()

        if not volume_transfer_info.dat_storage_root.is_dir():
            raise ValueError(f"dat storage root {str(volume_transfer_info.dat_storage_root)} is not a directory")

        logger.info(f"main: checking on recently acquired data for {volume_transfer_info}")

        keep_file_list = get_keep_file_list(host=volume_transfer_info.scope,
                                            keep_file_root=volume_transfer_info.scope_keep_file_root)

        logger.info(f"main: found {len(keep_file_list)} keep files on {volume_transfer_info.scope}, "
                    f"will copy dat files to {volume_transfer_info.dat_storage_root}")

        for keep_file in keep_file_list:

            logger.info(f"main: copying {keep_file.dat_path}")

            copy_dat_file(keep_file=keep_file,
                          dat_storage_root=volume_transfer_info.dat_storage_root)

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
    main(sys.argv[1:])
