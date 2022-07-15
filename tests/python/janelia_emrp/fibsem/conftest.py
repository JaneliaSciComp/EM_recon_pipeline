import logging
from datetime import datetime
from pathlib import Path

import pytest
from _pytest.tmpdir import TempPathFactory

from janelia_emrp.fibsem.volume_transfer_info import VolumeTransferInfo, RenderConnect

logger = logging.getLogger(__name__)


@pytest.fixture
def volume_transfer_info(tmpdir_factory: TempPathFactory) -> VolumeTransferInfo:
    # see https://docs.pytest.org/en/6.2.x/tmpdir.html
    h5_archive_storage_root = tmpdir_factory.mktemp(basename='raw')
    logger.debug(f"volume_transfer_info: created {str(h5_archive_storage_root)}")

    h5_align_storage_root = tmpdir_factory.mktemp(basename='align')
    logger.debug(f"volume_transfer_info: created {str(h5_align_storage_root)}")

    return VolumeTransferInfo(
        scope="jeiss8.hhmi.org",
        scope_storage_root="/cygdrive/e/Images/Fly Brain",
        scope_keep_file_root="/cygdrive/d/UploadFlags",
        dat_storage_root="/nearline/flyem2/data/Z0720-07m_VNC_Sec06/dat",
        dat_x_and_y_nm_per_pixel=8,
        dat_z_nm_per_pixel=8,
        acquire_start=datetime.strptime("21-07-27_201550", "%y-%m-%d_%H%M%S"),
        acquire_stop=datetime.strptime("21-08-04_213050", "%y-%m-%d_%H%M%S"),
        h5_archive_storage_root=h5_archive_storage_root,
        remove_dat_after_h5_archive=False,
        h5_align_storage_root=h5_align_storage_root,
        max_mipmap_level=7,
        render_owner="test_h5",
        render_project="VNC_Sec06",
        render_connect=RenderConnect(host="renderer-dev.int.janelia.org",
                                     port=8080,
                                     web_only=True,
                                     validate_client=False,
                                     client_scripts="/groups/flyTEM/flyTEM/render/bin",
                                     memGB="1G")
    )


@pytest.fixture
def small_dat_path() -> Path:
    # small dat created by clipping /nearline/flyem2/data/Z0720-07m_VNC_Sec06/dat/Merlin-6284_21-07-31_152727_0-0-1.dat
    dat_path = Path("../resources/janelia_emrp/fibsem/small_21-07-31_152727_0-0-1.dat").resolve()
    assert dat_path.exists(), f"{str(dat_path)} does not exist, base test path is {str(Path('.').resolve())}"
    return dat_path
