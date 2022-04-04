import datetime
from pathlib import Path
from typing import Optional

from pydantic import BaseModel


class RenderConnect(BaseModel):
    # """Render-python connection information (minus owner and project)."""
    host: str
    port: int = 8080
    web_only: bool
    validate_client: bool
    client_scripts: str
    memGB: str


class VolumeTransferInfo(BaseModel):
    # """
    # Information for managing the transfer of volume data from a scope to centralized storage.
    #
    # Attributes
    # ----------
    # scope : str
    #     hostname for scope acquiring data (e.g. 'jeiss3.hhmi.org')
    #
    # scope_storage_root : Path
    #     scope root path excluding datetime-based subdirectories for acquired data
    #     (e.g. '/cygdrive/e/Images/Fly Brain' for full paths like
    #     '/cygdrive/e/Images/Fly Brain/Y2021/M05/D05/Merlin-6257_21-05-05_102654_0-0-0.dat')
    #
    # acquire_start : Optional[datetime.datetime]
    #     time first volume image was acquired, None if acquisition has not started.
    #     JSON string representations must use ISO 8601 format (e.g. 2021-05-05T10:26:54).
    #
    # acquire_stop : Optional[datetime.datetime]
    #     time last volume image was acquired, None if acquisition has not completed
    #     JSON string representations must use ISO 8601 format (e.g. 2021-06-09T13:15:55).
    #
    # dat_storage_root : Path
    #     network storage path for dat files after transfer from scope
    #
    # dat_x_and_y_nm_per_pixel : int
    #     target nm pixel resolution for dat x and y dimensions
    #
    # dat_z_nm_per_pixel : int
    #     target nm pixel resolution for dat z dimension
    #
    # dat_tile_overlap_microns : int, default=2
    #     tile overlap width in microns for older dat volumes without stageX header values
    #
    # archive_storage_root : Optional[Path]
    #     root path for archive HDF5 data, None if archival is not needed
    #
    # remove_dat_after_archive : bool
    #     indicates whether dat files should be removed from network storage after they are successfully archived
    #
    # align_storage_root : Optional[Path]
    #     root path for 8-bit alignment HDF5 data, None if alignment data set is not needed
    #
    # align_mask_mipmap_root : Optional[Path]
    #     root path for 8-bit mask mipmap data, None if alignment data set is not needed
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
    #
    # render_stack : str, default="v1_acquire"
    #     name of the first render acquisition stack
    #
    # render_restart_context_layer_count : int, default=1
    #     number of layers to include in the restart stack before and after each restart
    #
    # render_connect : Optional[RenderConnect]
    #     render-python connection information (omit to skip writing to render web services)
    #
    # bill_project : Optional[str]
    #     project to bill cluster time to (omit to use default project)
    #
    # mask_storage_root : Optional[Path]
    #     directory containing mask files (omit if masks are not desired)
    #
    # mask_width : int, default=100
    #     left pixel width of masked area
    # """
    scope: str
    scope_storage_root: Path
    acquire_start: Optional[datetime.datetime]
    acquire_stop: Optional[datetime.datetime]
    dat_storage_root: Path
    dat_x_and_y_nm_per_pixel: int
    dat_z_nm_per_pixel: int
    dat_tile_overlap_microns: int = 2
    archive_storage_root: Optional[Path]
    remove_dat_after_archive: bool
    align_storage_root: Optional[Path]
    align_mask_mipmap_root: Optional[Path]
    max_mipmap_level: Optional[int]
    render_owner: str
    render_project: str
    render_stack: str = "v1_acquire"
    render_restart_context_layer_count: int = 1
    render_connect: Optional[RenderConnect]
    bill_project: Optional[str]
    mask_storage_root: Optional[Path]
    mask_width: int = 100

    def __str__(self):
        return f"{self.render_owner}::{self.render_project}::{self.scope}"

    def get_render_connect_params(self):
        if not self.render_connect:
            raise ValueError(f"render_connect value is not defined for {self}")

        return {
            "host": self.render_connect.host,
            "port": self.render_connect.port,
            "owner": self.render_owner,
            "project": self.render_project,
            "web_only": self.render_connect.web_only,
            "validate_client": self.render_connect.validate_client,
            "client_scripts": self.render_connect.client_scripts,
            "memGB": self.render_connect.memGB
        }
