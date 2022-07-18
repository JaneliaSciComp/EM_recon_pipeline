import datetime
import logging
import re
from dataclasses import dataclass, field
from pathlib import Path, PurePath
from typing import List

logger = logging.getLogger(__name__)

# pattern for parsing dat files named with standard convention (e.g. Merlin-6049_15-06-16_000059_0-0-0.dat)
base_name_pattern = re.compile(r"(.*)_(\d\d-\d\d-\d\d_\d{6})_(\d+)-(\d+)-(\d+).*")


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


def new_dat_path(file_path: Path) -> DatPath:
    """
    Returns
    -------
    DatPath
        A new instance parsed from the specified `file_path`.
    """
    m = base_name_pattern.match(file_path.name)
    if not m:
        raise ValueError(f"base name for {file_path} does not follow expected pattern")

    scope = m.group(1)
    acquire_time_string = m.group(2)
    layer_id = f"{scope}_{acquire_time_string}"
    acquire_time = datetime.datetime.strptime(acquire_time_string, "%y-%m-%d_%H%M%S")
    section = int(m.group(3))
    row = int(m.group(4))
    column = int(m.group(5))

    return DatPath(file_path, scope, layer_id, acquire_time, section, row, column)


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
