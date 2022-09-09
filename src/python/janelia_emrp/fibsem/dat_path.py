import argparse
import datetime
import logging
import re
import traceback

import sys
from dataclasses import dataclass, field
from pathlib import Path, PurePath
from typing import List, Optional, Final

from janelia_emrp.root_logger import init_logger

logger = logging.getLogger(__name__)

# pattern for parsing dat files named with standard convention (e.g. Merlin-6049_15-06-16_000059_0-0-0.dat)
BASE_NAME_PATTERN: Final = re.compile(r"(.*)_(\d\d-\d\d-\d\d_\d{6})_(\d+)-(\d+)-(\d+).*")
DAT_TIME_FORMAT: Final = "%y-%m-%d_%H%M%S"

@dataclass
class DatPath:
    # Keeps track of metadata parsed from a dat file path.
    file_path: Path
    scope: str = field(compare=False)
    layer_id: str = field(compare=False)
    acquire_time: datetime.datetime = field(compare=False)
    section: int = field(compare=False)
    row: int = field(compare=False)
    column: int = field(compare=False)

    def tile_key(self) -> str:
        return f"{self.section}-{self.row}-{self.column}"

    def layer_and_tile(self):
        return f"{self.layer_id}::{self.tile_key()}"

    def acquired_before(self,
                        before: Optional[datetime.datetime] = None) -> bool:
        if before is None:
            before = datetime.datetime.now()
        return self.acquire_time < before


def new_dat_path(file_path: Path) -> DatPath:
    """
    Returns
    -------
    DatPath
        A new instance parsed from the specified `file_path`.
    """
    m = BASE_NAME_PATTERN.match(file_path.name)
    if not m:
        raise ValueError(f"base name for {file_path} does not follow expected pattern")

    scope = m.group(1)
    acquire_time_string = m.group(2)
    layer_id = f"{scope}_{acquire_time_string}"
    acquire_time = datetime.datetime.strptime(acquire_time_string, DAT_TIME_FORMAT)
    section = int(m.group(3))
    row = int(m.group(4))
    column = int(m.group(5))

    return DatPath(file_path, scope, layer_id, acquire_time, section, row, column)


def dat_to_target_path(from_dat_path: [Path, str],
                       to_root_path: Path) -> Path:
    dat_path = new_dat_path(Path(from_dat_path))
    hourly_relative_path_string = dat_path.acquire_time.strftime("%Y/%m/%d/%H")
    return to_root_path / hourly_relative_path_string / dat_path.file_path.name


@dataclass
class DatPathsForLayer:
    # Container for list of dat paths comprising one layer of a volume.
    dat_paths: List[DatPath]

    def append(self, dat_path: DatPath) -> None:
        layer_id = self.get_layer_id()
        if layer_id != dat_path.layer_id:
            raise ValueError(f"layer id {dat_path.layer_id} for {dat_path.file_path} should be {layer_id}")
        self.dat_paths.append(dat_path)

    def get_layer_id(self) -> str:
        if len(self.dat_paths) == 0:
            raise ValueError(f"cannot derive id for empty layer, use new_layer function to create a new layer")
        return self.dat_paths[0].layer_id

    def get_h5_path(self,
                    h5_root_path: Path,
                    append_acquisition_based_subdirectories: bool = True,
                    source_type="raw") -> Path:
        if len(self.dat_paths) == 0:
            raise ValueError(f"cannot derive h5 path for empty layer, use new_layer function to create a new layer")

        first_dat_path = self.dat_paths[0]
        layer_h5_file_name = f"{first_dat_path.layer_id}.{source_type}.h5"

        if append_acquisition_based_subdirectories:

            # A 7500 x 3500 pixel dat takes about 30 seconds to acquire.  Acquisition of a
            # volume with single tile layers this size would result in 120 layer files per hour.
            # Therefore, dividing layer files into subdirectories by scope and hour should
            # prevent accumulation of too many files in any one directory.

            # Merlin-6049_15-06-16_000059_0-0-0.dat => Merlin-6049/2015/06/16/00/Merlin-6049_15-06-16_000059.raw.h5
            hourly_relative_path_string = first_dat_path.acquire_time.strftime("%Y/%m/%d/%H")
            relative_path = PurePath(first_dat_path.scope, hourly_relative_path_string, layer_h5_file_name)

        else:
            relative_path = PurePath(layer_h5_file_name)

        return h5_root_path / relative_path

    def h5_exists(self,
                  h5_root_path: Path,
                  append_acquisition_based_subdirectories: bool = True,
                  source_type="raw") -> bool:
        exists = False
        if h5_root_path is not None:
            exists = self.get_h5_path(h5_root_path=h5_root_path,
                                      append_acquisition_based_subdirectories=append_acquisition_based_subdirectories,
                                      source_type=source_type).exists()
        return exists


def new_dat_layer(dat_path: DatPath) -> DatPathsForLayer:
    """
    Returns
    -------
    DatPathsForLayer
        A new instance that contains the specified `dat_path`.
    """
    return DatPathsForLayer(dat_paths=[dat_path])


def get_sorted_dat_file_paths(path_list: List[Path]) -> List[Path]:
    """
    Builds a sorted list of explicit dat file paths from the specified path list.
    Specified directories are searched recursively for dat files, whose explicit paths are added to the returned list.

    Returns
    -------
    List[Path]
        A list of explicit and sorted dat file paths.
    """
    dat_file_paths = []

    for path in path_list:
        if path.is_dir():
            dat_file_paths.extend(path.glob("**/*.dat"))
        else:
            dat_file_paths.append(path)

    if len(dat_file_paths) > 0:
        dat_file_paths = sorted(dat_file_paths)

    return dat_file_paths


def split_into_layers(path_list: List[Path]) -> List[DatPathsForLayer]:
    """
    Converts the specified path list into a sorted list of explicit dat file paths
    and then aggregates the dat paths by z layer, returning a list of layers.

    Returns
    -------
    List[DatPathsForLayer]
        A list of layer instances.
    """
    layers = []
    sorted_dat_file_paths = get_sorted_dat_file_paths(path_list)
    if len(sorted_dat_file_paths) > 0:
        dat_path = new_dat_path(sorted_dat_file_paths[0])
        paths_for_layer = new_dat_layer(dat_path)

        for i in range(1, len(sorted_dat_file_paths)):
            dat_path = new_dat_path(sorted_dat_file_paths[i])
            if dat_path.layer_id != paths_for_layer.get_layer_id():
                layers.append(paths_for_layer)
                paths_for_layer = new_dat_layer(dat_path)
            else:
                paths_for_layer.append(dat_path)

        layers.append(paths_for_layer)

    return layers


def rename_dat_files(source_dir: Path,
                     target_dir: Path):

    if not source_dir.is_dir():
        raise ValueError(f"source {source_dir} is not a directory")

    sorted_dat_file_paths = get_sorted_dat_file_paths([source_dir])

    number_to_rename = len(sorted_dat_file_paths)
    if number_to_rename > 0:
        logger.info(f"rename_dat_files: found {number_to_rename} dat files to rename/move")

        target_dir.mkdir(parents=True, exist_ok=True)

        created_target_dirs = set()

        rename_count = 0
        for dat_file_path in sorted_dat_file_paths:
            dat_target_path = dat_to_target_path(from_dat_path=dat_file_path,
                                                 to_root_path=target_dir)
            dat_target_parent_path = dat_target_path.parent
            if dat_target_parent_path not in created_target_dirs:
                dat_target_parent_path.mkdir(parents=True, exist_ok=True)
                created_target_dirs.add(dat_target_parent_path)

            dat_file_path.rename(dat_target_path)
            rename_count += 1

            if rename_count % 1000 == 0:
                logger.info(f"rename_dat_files: renamed {rename_count} out of {number_to_rename} dat files")

    logger.info(f"rename_dat_files: renamed {number_to_rename} dat files")

    return 0


def main(arg_list: list[str]):
    parser = argparse.ArgumentParser(
        description="Renames (moves) dat files from a flat directory structure to one with hourly relative paths "
                    "(e.g. /source-dat/Merlin-6257_22-07-29_151723_0-0-0.dat to "
                    "/target-dat/2022/07/29/15/Merlin-6257_22-07-29_151723_0-0-0.dat)"
    )
    parser.add_argument(
        "--source",
        help="Path of root source directory containing dat files to move.",
        required=True,
    )
    parser.add_argument(
        "--target",
        help="Path of root target directory to contain dat files with hourly relative paths.",
        required=True,
    )
    args = parser.parse_args(args=arg_list)

    rename_dat_files(source_dir=Path(args.source),
                     target_dir=Path(args.target))

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
