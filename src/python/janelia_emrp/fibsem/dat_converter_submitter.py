import argparse
import logging
import subprocess
import traceback
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import sys

from janelia_emrp.fibsem.dat_converter import get_layers_for_run
from janelia_emrp.fibsem.dat_path import DatPath, new_dat_path, DatPathsForLayer
from janelia_emrp.fibsem.volume_transfer_info import VolumeTransferInfo, VolumeTransferTask, build_volume_transfer_list
from janelia_emrp.root_logger import init_logger

logger = logging.getLogger(__name__)


@dataclass
class DatBatch:
    data_set_id: str
    first_dat: DatPath
    last_dat: DatPath
    runtime_limit: str

    def get_job_name(self):
        # layer_id for Merlin-6049_15-06-16_000059_0-0-0.dat is Merlin-6049_15-06-16_000059
        # max LSF job name length is 512, should be fine here
        return f"convert_{self.data_set_id}_{self.first_dat.layer_id}_to_{self.last_dat.layer_id}"


def build_dat_batch_list(layers: list[DatPathsForLayer],
                         data_set_id: str,
                         number_dats_converted_in_one_hour: int) -> list[DatBatch]:
    batch_list: list[DatBatch] = []

    # build one-hour-ish batches with 3:59 runtime,
    # so we get access to most cluster nodes but don't have to worry about running out of time
    last_index = len(layers) - 1
    dat_count = 0
    first_index = 0
    for i in range(len(layers)):
        dat_paths_for_layer = layers[i].dat_paths
        dat_count = dat_count + len(dat_paths_for_layer)
        if dat_count >= number_dats_converted_in_one_hour or i == last_index:
            batch_list.append(DatBatch(data_set_id=data_set_id,
                                       first_dat=layers[first_index].dat_paths[0],
                                       last_dat=dat_paths_for_layer[-1],
                                       runtime_limit="3:59"))
            dat_count = 0
            first_index = i + 1

    return batch_list


def bsub_convert_dat_batch(dat_batch: DatBatch,
                           cluster_job_project_for_billing: str,
                           num_workers: int,
                           convert_script_path: Path,
                           base_log_dir_path: Path):
    args = [
        "bsub",
        "-P", cluster_job_project_for_billing,
        "-W", dat_batch.runtime_limit,
        "-J", dat_batch.get_job_name(),
        str(convert_script_path),
        str(num_workers),
        str(base_log_dir_path),
        str(dat_batch.first_dat.file_path),
        str(dat_batch.last_dat.file_path)
    ]

    subprocess.run(args,
                   stdout=sys.stdout,
                   stderr=sys.stdout,
                   check=True)


def main(arg_list: list[str]):
    parser = argparse.ArgumentParser(
        description="Partitions and submits LSF jobs to convert dat files to h5 raw and align files."
    )
    parser.add_argument(
        "--volume_transfer_dir",
        help="Path of directory containing volume_transfer_info.json files",
        required=True,
    )
    parser.add_argument(
        "--convert_script",
        help="Path of convert script to be called by bsub job",
        default="/groups/flyem/home/flyem/bin/dat_transfer/2022/02_convert_dats.sh"
    )
    parser.add_argument(
        "--num_workers",
        help="The number of workers to use for distributed processing",
        type=int,
        default=1
    )
    parser.add_argument(
        "--max_batch_count",
        help="The maximum number of conversion batches to schedule",
        type=int
    )
    parser.add_argument(
        "--dats_per_hour",
        help="The expected number of dats to be converted in one hour by a process "
             "(a slow 8250x8875 dat conversion takes 180 seconds => 20 dats per hour)",
        type=int,
        default=20
    )
    args = parser.parse_args(args=arg_list)

    convert_script_path = Path(args.convert_script)
    if not convert_script_path.exists():
        raise ValueError(f"{convert_script_path} does not exist")

    volume_transfer_dir_path = Path(args.volume_transfer_dir)
    volume_transfer_list: list[VolumeTransferInfo] = \
        build_volume_transfer_list(volume_transfer_dir_path=volume_transfer_dir_path,
                                   for_scope=None,
                                   for_tasks=[VolumeTransferTask.GENERATE_CLUSTER_H5_RAW,
                                              VolumeTransferTask.GENERATE_CLUSTER_H5_ALIGN])

    processed_batch_count = 0
    for transfer_info in volume_transfer_list:

        cluster_root_dat_path = transfer_info.cluster_root_paths.raw_dat
        if not cluster_root_dat_path.is_dir():
            raise ValueError(f"cluster_root_paths.raw_dat {cluster_root_dat_path} is not a directory")

        first_dat: Optional[str] = None
        last_converted_dat_path: Optional[DatPath] = None
        last_conversion_path = cluster_root_dat_path / "last_conversion.txt"
        if last_conversion_path.exists():
            with open(last_conversion_path, "r") as last_conversion_file:
                first_dat = last_conversion_file.readline().strip()
                last_converted_dat_path = new_dat_path(Path(first_dat))

        layers = get_layers_for_run(dat_root=cluster_root_dat_path,
                                    first_dat=first_dat,
                                    last_dat=None,
                                    skip_existing=True,
                                    volume_transfer_info=transfer_info)

        if len(layers) > 0 and \
                last_converted_dat_path is not None and \
                layers[0].get_layer_id() == last_converted_dat_path.layer_id:
            layer_id = last_converted_dat_path.layer_id
            logger.info(f"main: removing first layer {layer_id} because it has already been converted")
            layers = layers[1:]

        if len(layers) > 0:
            for dat_batch in build_dat_batch_list(layers=layers,
                                                  data_set_id=transfer_info.scope_data_set.data_set_id,
                                                  number_dats_converted_in_one_hour=args.dats_per_hour):
                if args.max_batch_count is not None and processed_batch_count >= args.max_batch_count:
                    break

                bsub_convert_dat_batch(dat_batch=dat_batch,
                                       cluster_job_project_for_billing=transfer_info.cluster_job_project_for_billing,
                                       num_workers=args.num_workers,
                                       convert_script_path=convert_script_path,
                                       base_log_dir_path=(cluster_root_dat_path / "logs"))

                with open(last_conversion_path, "w") as last_conversion_file:
                    last_conversion_file.write(f"{dat_batch.last_dat.file_path}\n")

                processed_batch_count += 1

        else:
            logger.info(f"main: no layers remain to process")

        if args.max_batch_count is not None and processed_batch_count >= args.max_batch_count:
            logger.info(f"main: stopping after processing max number of batches ({args.max_batch_count})")
            break

    logger.info(f"main: done")

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
