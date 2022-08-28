import logging
from pathlib import Path

import pytest
from _pytest.tmpdir import TempPathFactory

from janelia_emrp.fibsem.volume_transfer_info import VolumeTransferInfo, RenderConnect, VolumeTransferTask, \
    ScopeDataSet, ClusterRootDirectoryPaths, ArchiveRootDirectoryPaths, RenderDataSet

logger = logging.getLogger(__name__)


@pytest.fixture
def volume_transfer_info(tmpdir_factory: TempPathFactory) -> VolumeTransferInfo:
    # see https://docs.pytest.org/en/6.2.x/tmpdir.html
    h5_archive_storage_root: Path = tmpdir_factory.mktemp(basename='raw')
    logger.debug(f"volume_transfer_info: created {str(h5_archive_storage_root)}")

    h5_align_storage_root: Path = tmpdir_factory.mktemp(basename='align')
    logger.debug(f"volume_transfer_info: created {str(h5_align_storage_root)}")

    return VolumeTransferInfo(
        transfer_id="test_owner::test_project::test_scope",
        scope_data_set=ScopeDataSet(
            host="jeiss8.hhmi.org",
            root_dat_path=Path("/cygdrive/e/Images/Fly Brain"),
            root_keep_path=Path("/cygdrive/d/UploadFlags"),
            data_set_id="Z0720-07m_VNC_Sec06",
            first_dat_name="Merlin-6284_21-07-27_201550_0-0-0.dat",
            last_dat_name="Merlin-6284_21-08-04_213050_0-0-0.dat",
            dat_x_and_y_nm_per_pixel=8,
            dat_z_nm_per_pixel=8
        ),
        cluster_root_paths=ClusterRootDirectoryPaths(
            align_h5=h5_align_storage_root
        ),
        archive_root_paths=ArchiveRootDirectoryPaths(
            raw_dat=Path("/nearline/flyem2/data/Z0720-07m_VNC_Sec06/dat"),
            raw_h5=h5_archive_storage_root
        ),
        max_mipmap_level=7,
        render_data_set=RenderDataSet(
            owner="test_h5",
            project="VNC_Sec06",
            stack="v1_acquire",
            restart_context_layer_count=1,
            connect=RenderConnect(host="renderer-dev.int.janelia.org",
                                  port=8080,
                                  web_only=True,
                                  validate_client=False,
                                  client_scripts="/groups/flyTEM/flyTEM/render/bin",
                                  memGB="1G"),
        ),
        transfer_tasks=[VolumeTransferTask.COPY_SCOPE_DAT_TO_CLUSTER],
        cluster_job_project_for_billing="scicompsoft"
    )


@pytest.fixture
def small_dat_path() -> Path:
    # small dat created by clipping /nearline/flyem2/data/Z0720-07m_VNC_Sec06/dat/Merlin-6284_21-07-31_152727_0-0-1.dat
    path = Path("../resources/janelia_emrp/fibsem/small_21-07-31_152727_0-0-1.dat").resolve()
    assert path.exists(), f"{str(path)} does not exist, base test path is {str(Path('.').resolve())}"
    return path


@pytest.fixture
def small_uint8_path() -> Path:
    path = Path("../resources/janelia_emrp/fibsem/small_21-07-31_152727.uint8.h5").resolve()
    assert path.exists(), f"{str(path)} does not exist, base test path is {str(Path('.').resolve())}"
    return path
