import datetime
from pathlib import Path
from typing import Dict

from janelia_emrp.fibsem.dat_copier import find_missing_scope_dats_for_day
from janelia_emrp.fibsem.dat_keep_file import KeepFile, build_keep_file
from janelia_emrp.fibsem.dat_path import new_dat_path


def test_find_missing_scope_dats_for_day(tmp_path):

    host = "jeiss6.hhmi.org"
    dat_prefix = "/cygdrive/e/Images/Mouse/Y2022/M07/D21/"
    keep_file_root = Path("/cygdrive/d/UploadFlags")
    keep_prefix = "zonation2^E^^Images^Mouse^Y2022^M07^D21^"
    scope_dat_names = [
        "Merlin-6281_22-07-21_014314_0-0-0.dat",
        "Merlin-6281_22-07-21_014314_0-0-1.dat",
        "Merlin-6281_22-07-21_014518_0-0-0.dat",
        "Merlin-6281_22-07-21_014518_0-0-1.dat",
        "Merlin-6281_22-07-21_014722_0-0-0.dat",
        "Merlin-6281_22-07-21_014722_0-0-1.dat",
        "Merlin-6281_22-07-21_014926_0-0-0.dat",
        "Merlin-6281_22-07-21_014926_0-0-1.dat",
        "Merlin-6281_22-07-21_015130_0-0-0.dat",
        "Merlin-6281_22-07-21_015130_0-0-1.dat"
    ]
    scope_dat_paths: list[Path] = []
    keep_file_list: list[KeepFile] = []
    for i in range(0, len(scope_dat_names)):
        dat_path_str = f"{dat_prefix}{scope_dat_names[i]}"
        scope_dat_paths.append(Path(dat_path_str))
        if i > 3 and i != 7:
            keep_file = build_keep_file(host, str(keep_file_root), f"{keep_prefix}{scope_dat_names[i]}^keep")
            keep_file_list.append(keep_file)

    cluster_root_dat_path: Path = tmp_path
    start_time: datetime.datetime = new_dat_path(scope_dat_paths[0]).acquire_time
    stop_time: datetime.datetime = new_dat_path(scope_dat_paths[9]).acquire_time

    time_to_keep_files: Dict[datetime.datetime, list[KeepFile]] = {}
    for keep_file in keep_file_list:
        keep_files_for_time = time_to_keep_files.setdefault(keep_file.acquire_time(), [])
        keep_files_for_time.append(keep_file)

    result: list[KeepFile] = find_missing_scope_dats_for_day(scope_dat_paths,
                                                             cluster_root_dat_path,
                                                             start_time,
                                                             stop_time,
                                                             keep_file_list[0],
                                                             keep_file_list[-1],
                                                             time_to_keep_files)

    assert len(result) == 5, "incorrect number of missing dat files found"
