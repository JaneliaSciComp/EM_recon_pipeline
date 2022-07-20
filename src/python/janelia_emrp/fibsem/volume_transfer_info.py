import datetime
from enum import Enum
from pathlib import Path
from typing import Optional, Any

from pydantic import BaseModel


class VolumeTransferTask(Enum):
    """Tasks supported by volume transfer functions."""
    COPY_SCOPE_DAT_TO_CLUSTER = "COPY_SCOPE_DAT_TO_CLUSTER"
    GENERATE_CLUSTER_H5_RAW = "GENERATE_CLUSTER_H5_RAW"
    GENERATE_ARCHIVE_H5_RAW = "GENERATE_ARCHIVE_H5_RAW"
    GENERATE_CLUSTER_H5_ALIGN = "GENERATE_CLUSTER_H5_ALIGN"
    ARCHIVE_DAT = "ARCHIVE_DAT"
    ARCHIVE_H5_RAW = "ARCHIVE_H5_RAW"
    REMOVE_DAT_AFTER_H5_CONVERSION = "REMOVE_DAT_AFTER_H5_CONVERSION"
    IMPORT_H5_ALIGN_INTO_RENDER = "IMPORT_H5_ALIGN_INTO_RENDER"
    APPLY_FIBSEM_CORRECTION_TRANSFORM = "APPLY_FIBSEM_CORRECTION_TRANSFORM"


class ScopeDataSet(BaseModel):
    """FIBSEM scope information for a volume.
    #
    # Attributes:
    #     host:
    #         hostname for scope acquiring data (e.g. 'jeiss3.hhmi.org')
    #     root_dat_path:
    #         root path excluding datetime-based subdirectories for acquired data
    #         (e.g. '/cygdrive/e/Images/Fly Brain' for full paths like
    #         '/cygdrive/e/Images/Fly Brain/Y2021/M05/D05/Merlin-6257_21-05-05_102654_0-0-0.dat')
    #     root_keep_path:
    #         root path excluding datetime-based subdirectories for dat keep files
    #         (e.g. '/cygdrive/d/UploadFlags')
    #     data_set_id:
    #         data set identifier included in keep file name and in SampleId and Notes dat header fields
    #     acquire_start:
    #         time first volume image was acquired, None if acquisition has not started.
    #         JSON string representations must use ISO 8601 format (e.g. 2021-05-05T10:26:54).
    #     acquire_stop:
    #         time last volume image was acquired, None if acquisition has not completed
    #         JSON string representations must use ISO 8601 format (e.g. 2021-06-09T13:15:55).
    #     dat_x_and_y_nm_per_pixel:
    #         target nm pixel resolution for dat x and y dimensions
    #     dat_z_nm_per_pixel:
    #         target nm pixel resolution for dat z dimension
    #     dat_tile_overlap_microns:
    #         tile overlap width in microns for older dat volumes without stageX header values
    #         (ignored if StageX and StageY positions exist in dat header - e.g. for FIBSEM version >= 9)
    """
    host: str
    root_dat_path: Path
    root_keep_path: Path
    data_set_id: str
    acquire_start: Optional[datetime.datetime]
    acquire_stop: Optional[datetime.datetime]
    dat_x_and_y_nm_per_pixel: int
    dat_z_nm_per_pixel: int
    dat_tile_overlap_microns: int = 2

    def acquisition_started(self,
                            before: Optional[datetime.datetime] = None) -> bool:
        if before is None:
            before = datetime.datetime.now()
        return self.acquire_start is not None and self.acquire_start < before

    def acquisition_stopped(self,
                            before: Optional[datetime.datetime] = None) -> bool:
        if before is None:
            before = datetime.datetime.now()
        return self.acquire_stop is not None and self.acquire_stop < before


class ClusterRootDirectoryPaths(BaseModel):
    """Cluster accessible (e.g. dm11 or nrs) paths for data."""
    raw_dat: Optional[Path]
    raw_h5: Optional[Path]
    align_h5: Optional[Path]


class ArchiveRootDirectoryPaths(BaseModel):
    """Archive (e.g. nearline) paths for data."""
    raw_dat: Optional[Path]
    raw_h5: Optional[Path]


class RenderConnect(BaseModel):
    """Render-python connection information (minus owner and project)."""
    host: str
    port: int = 8080
    web_only: bool
    validate_client: bool
    client_scripts: str
    memGB: str


def params_to_render_connect(params: dict[str, Any]) -> RenderConnect:
    return RenderConnect(host=params["host"],
                         port=params["port"],
                         web_only=params["web_only"],
                         validate_client=params["validate_client"],
                         client_scripts=params["client_scripts"],
                         memGB=params["memGB"])


class RenderDataSet(BaseModel):
    """Information needed for importing a volume into Render web services.
    #
    # Attributes:
    #     owner:                       owner of the render stacks for this volume
    #     project:                     project for the render stacks for this volume
    #     stack:                       name of the first render acquisition stack
    #     restart_context_layer_count: number of layers to include in the restart stack before and after each restart
    #     mask_width:                  left pixel width of masked area (omit to skip masking left edges of each tile)
    #     mask_height:                 top pixel height of masked area (omit to skip masking top edges of each tile)
    #     connect:                     render-python connection info (omit to skip writing to render web services)
    """
    owner: str
    project: str
    stack: str
    restart_context_layer_count: int
    mask_width: Optional[int]
    mask_height: Optional[int]
    connect: Optional[RenderConnect]

    def __str__(self):
        return f"{self.owner}::{self.project}"

    def get_render_connect_params(self):
        if not self.connect:
            raise ValueError(f"render_connect value is not defined for {self}")

        return {
            "host": self.connect.host,
            "port": self.connect.port,
            "owner": self.owner,
            "project": self.project,
            "web_only": self.connect.web_only,
            "validate_client": self.connect.validate_client,
            "client_scripts": self.connect.client_scripts,
            "memGB": self.connect.memGB
        }


class VolumeTransferInfo(BaseModel):
    """Information for managing the transfer of volume data from a scope to centralized storage.
    #
    # Attributes:
    #     transfer_id:
    #         identifier or simple name for this volume transfer configuration
    #     scope_data_set:
    #         FIBSEM scope information for this volume
    #         (omit if transfer tasks don't require scope information)
    #     cluster_root_paths:
    #         cluster accessible root paths for data
    #         (omit if transfer tasks don't involve cluster processing)
    #     archive_root_paths:
    #         archive root paths for data
    #         (omit if transfer tasks don't involve archival processing)
    #     max_mipmap_level:
    #         maximum number of down-sampled mipmap levels to produce for each image
    #         (omit to skip generation of down-sampled mipmaps)
    #     render_data_set:
    #         information for render web services import
    #         (omit if transfer tasks don't involve render web services processing)
    #     transfer_tasks:
    #         set of tasks to perform for this volume
    #     cluster_job_project_for_billing:
    #         project to bill cluster time to
    """
    transfer_id: str
    scope_data_set: Optional[ScopeDataSet]
    cluster_root_paths: Optional[ClusterRootDirectoryPaths]
    archive_root_paths: Optional[ArchiveRootDirectoryPaths]
    max_mipmap_level: Optional[int]
    render_data_set: Optional[RenderDataSet]
    transfer_tasks: list[VolumeTransferTask]
    cluster_job_project_for_billing: str

    def __str__(self):
        return self.transfer_id

    def includes_task(self,
                      task: VolumeTransferTask):
        return task in self.transfer_tasks

    def acquisition_started(self):
        started_for_scope = False
        if self.scope_data_set is not None:
            started_for_scope = self.scope_data_set.acquisition_started()
        return started_for_scope

    def acquisition_stopped(self):
        stopped_for_scope = False
        if self.scope_data_set is not None:
            stopped_for_scope = self.scope_data_set.acquisition_stopped()
        return stopped_for_scope

    def get_dat_root_for_conversion(self):
        dat_root = None
        if self.cluster_root_paths is not None:
            dat_root = self.cluster_root_paths.raw_dat
        if dat_root is None and self.archive_root_paths is not None:
            dat_root = self.archive_root_paths.raw_dat
        return dat_root

    def get_raw_h5_root_for_conversion(self):
        raw_h5_root = None
        if self.includes_task(VolumeTransferTask.GENERATE_CLUSTER_H5_RAW):
            if self.cluster_root_paths is not None:
                raw_h5_root = self.cluster_root_paths.raw_h5
        elif self.includes_task(VolumeTransferTask.GENERATE_ARCHIVE_H5_RAW):
            if self.archive_root_paths is not None:
                raw_h5_root = self.archive_root_paths.raw_h5
        return raw_h5_root

    def get_align_h5_root_for_conversion(self):
        align_h5_root = None
        if self.includes_task(VolumeTransferTask.GENERATE_CLUSTER_H5_ALIGN):
            if self.cluster_root_paths is not None:
                align_h5_root = self.cluster_root_paths.align_h5
        return align_h5_root
