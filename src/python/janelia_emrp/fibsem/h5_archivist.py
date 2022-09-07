import argparse
import logging
import os
import subprocess
import traceback
from pathlib import Path

import psutil
import sys
import time

from janelia_emrp.fibsem.volume_transfer_info import build_volume_transfer_list, VolumeTransferInfo, VolumeTransferTask
from janelia_emrp.root_logger import init_logger

logger = logging.getLogger(__name__)


def check_and_save_pid(pid_path: Path,
                       skip_log_path: Path):
    is_archive_already_running = False

    if pid_path.exists():
        with open(pid_path, "r") as pid_file:
            saved_pid = int(pid_file.readline().strip())

        if psutil.pid_exists(saved_pid):
            is_archive_already_running = True
            running_archive_process = psutil.Process(saved_pid)

            time_fmt = "%Y-%m-%d %H:%M:%S"
            start_time_str = time.strftime(time_fmt, time.localtime(running_archive_process.create_time()))
            run_time_str = time.strftime(time_fmt)

            skip_message = f"skipping run, process {saved_pid} started at {start_time_str} is still running"
            logger.warning(skip_message)

            with open(skip_log_path, "a") as skip_file:
                skip_file.write(f"{run_time_str} {skip_message}\n")

    if not is_archive_already_running:
        with open(pid_path, "w") as pid_file:
            pid_file.write(f"{os.getpid()}\n")

    return is_archive_already_running


def archive_volume(transfer_info: VolumeTransferInfo,
                   number_of_processes: int):

    logger.info(f"archive_volume: archiving {transfer_info}")

    # "cluster_root_paths": {
    #     "raw_h5": "/groups/cellmap/cellmap/render/h5/jrc_zf-cardiac-1/raw",
    # },
    if not transfer_info.cluster_root_paths.raw_h5.is_dir():
        raise ValueError(f"missing directory {transfer_info.cluster_root_paths.raw_h5}")

    # "archive_root_paths": {
    #     "raw_h5": "/nearline/cellmap/data/jrc_zf-cardiac-1/raw"
    # },
    transfer_info.archive_root_paths.raw_h5.mkdir(parents=True, exist_ok=True)

    # note: Path object removes trailing slash for directories, so it is ok to always add it here for rsync
    src_dir = f"{transfer_info.cluster_root_paths.raw_h5}/"
    dest_dir = f"{transfer_info.archive_root_paths.raw_h5}/"

    rsync_options = "--include='*.raw-archive.h5' --include='*/' " \
                    "--exclude='*' " \
                    "--chmod=D775 " \
                    "--chmod=F444 " \
                    "--remove-source-files"
    args = [
        "/misc/local/msrsync/msrsync3",
        "--processes", str(number_of_processes),
        "--progress", "--stats",
        "--rsync", rsync_options,
        src_dir, dest_dir
    ]

    subprocess.run(args,
                   stdout=sys.stdout,
                   stderr=sys.stdout,
                   check=True)


def main(arg_list: list[str]):
    start_time = time.time()

    parser = argparse.ArgumentParser(
        description="Archives h5 raw files."
    )
    parser.add_argument(
        "--volume_transfer_dir",
        help="Path of directory containing volume_transfer_info.json files",
        required=True,
    )
    parser.add_argument(
        "--processes",
        type=int,
        default=1,
        help="Number of processes to use for msrsync",
    )
    args = parser.parse_args(args=arg_list)

    volume_transfer_dir_path = Path(args.volume_transfer_dir)

    pid_path = volume_transfer_dir_path / "h5_archivist.pid"
    skip_log_path = volume_transfer_dir_path / "h5_archivist.skip.log"
    is_archive_already_running = check_and_save_pid(pid_path=pid_path,
                                                    skip_log_path=skip_log_path)

    if not is_archive_already_running:
        volume_transfer_list: list[VolumeTransferInfo] = \
            build_volume_transfer_list(volume_transfer_dir_path=volume_transfer_dir_path,
                                       for_scope=None,
                                       for_tasks=[VolumeTransferTask.ARCHIVE_H5_RAW])

        for transfer_info in volume_transfer_list:
            # noinspection PyBroadException
            try:
                archive_volume(transfer_info=transfer_info,
                               number_of_processes=args.processes)
            except Exception:
                logger.exception(f"caught exception attempting to archive {transfer_info}")

    os.remove(pid_path)

    elapsed_seconds = int(time.time() - start_time)
    logger.info(f"main: finished archival in {elapsed_seconds} seconds")

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
