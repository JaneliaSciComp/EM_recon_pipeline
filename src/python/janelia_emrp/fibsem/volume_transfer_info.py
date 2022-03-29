import datetime
from dataclasses import dataclass
from pathlib import Path
from typing import Optional


@dataclass
class VolumeTransferInfo:
    # """
    # Information for managing the transfer of volume data from a scope to centralized storage.
    #
    # Attributes
    # ----------
    # scope : str
    #     hostname for scope acquiring data
    #     (e.g. 'jeiss3.hhmi.org')
    #
    # scope_storage_root : Path
    #     scope root path excluding datetime-based subdirectories for acquired data
    #     (e.g. '/cygdrive/e/Images/Fly Brain' for full paths like
    #     '/cygdrive/e/Images/Fly Brain/Y2021/M05/D05/Merlin-6257_21-05-05_102654_0-0-0.dat')
    #
    # acquire_start : Optional[datetime.datetime]
    #     time first volume image was acquired, None if acquisition has not started
    #
    # acquire_stop : Optional[datetime.datetime]
    #     time last volume image was acquired, None if acquisition has not completed
    #
    # dat_storage_root : Path
    #     network storage path for dat files after transfer from scope
    #
    # remove_dat_after_archive : bool
    #     indicates whether dat files should be removed from network storage after they are successfully archived
    #
    # archive_storage_root : Optional[Path]
    #     root path for archive HDF5 data, None if archival is not needed
    #
    # align_storage_root : Optional[Path]
    #     root path for 8-bit alignment HDF5 data, None if alignment data set is not needed
    #
    # max_mipmap_level : Optional[int]
    #     maximum number of down-sampled mipmap levels to produce for each image,
    #     None to produce as many levels as possible,
    #     ignored if align_storage_root is None
    #
    # render_owner : str
    #     owner of the render stacks for this volume
    #
    # render_project : str
    #     project for the render stacks for this volume
    # """
    scope: str
    scope_storage_root: Path
    acquire_start: Optional[datetime.datetime]
    acquire_stop: Optional[datetime.datetime]
    dat_storage_root: Path
    archive_storage_root: Optional[Path]
    remove_dat_after_archive: bool
    align_storage_root: Optional[Path]
    max_mipmap_level: Optional[int]
    render_owner: str
    render_project: str

    def __str__(self):
        return f"{self.render_owner}::{self.render_project}::{self.scope}"
