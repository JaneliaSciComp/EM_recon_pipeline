import logging
import sys
from datetime import datetime
from pathlib import Path

from janelia_emrp.fibsem.dat_converter import DatConverter
from janelia_emrp.fibsem.dat_path import split_into_layers
from janelia_emrp.fibsem.dat_to_h5_writer import DatToH5Writer
from janelia_emrp.fibsem.volume_transfer_info import VolumeTransferInfo

root_logger = logging.getLogger()
c_handler = logging.StreamHandler(sys.stdout)
c_formatter = logging.Formatter("%(asctime)s [%(threadName)s] [%(name)s] [%(levelname)s] %(message)s")
c_handler.setFormatter(c_formatter)
root_logger.addHandler(c_handler)
root_logger.setLevel(logging.INFO)

volume_transfer_info = VolumeTransferInfo(
    scope="jeiss3.hhmi.org",
    scope_storage_root=Path("/cygdrive/e/Images/Fly Brain"),
    dat_storage_root=Path("/Volumes/flyem2/data/Z0720-07m_BR_Sec18/dat"),
    acquire_start=datetime.strptime("21-05-05_102654", "%y-%m-%d_%H%M%S"),
    acquire_stop=datetime.strptime("21-06-09_131555", "%y-%m-%d_%H%M%S"),
    archive_storage_root=Path("/Users/trautmane/Desktop/fibsem-tests/archive"),
    remove_dat_after_archive=False,
    align_storage_root=Path("/Users/trautmane/Desktop/fibsem-tests/align"),
    max_mipmap_level=7,
    render_owner="Z0720_07m_BR",
    render_project="Sec18"
)


def test_derive_max_mipmap_level():
    converter = DatConverter(volume_transfer_info)
    assert 3 == converter.derive_max_mipmap_level(3), "actual mipmap level should be selected"
    assert 7 == converter.derive_max_mipmap_level(12), "volume max mipmap level should be selected"


def main():
    dat_file_paths = [
        Path("/Volumes/flyem2/data/Z0720-07m_BR_Sec18/dat/Merlin-6257_21-05-20_125304_0-0-0.dat"),
        Path("/Volumes/flyem2/data/Z0720-07m_BR_Sec18/dat/Merlin-6257_21-05-20_125304_0-0-1.dat"),
        Path("/Volumes/flyem2/data/Z0720-07m_BR_Sec18/dat/Merlin-6257_21-05-20_125304_0-0-2.dat"),
        Path("/Volumes/flyem2/data/Z0720-07m_BR_Sec18/dat/Merlin-6257_21-05-20_125304_0-0-3.dat"),
        Path("/Volumes/flyem2/data/Z0720-07m_BR_Sec18/dat/Merlin-6257_21-05-20_125416_0-0-0.dat"),
        Path("/Volumes/flyem2/data/Z0720-07m_BR_Sec18/dat/Merlin-6257_21-05-20_125416_0-0-1.dat"),
        Path("/Volumes/flyem2/data/Z0720-07m_BR_Sec18/dat/Merlin-6257_21-05-20_125416_0-0-2.dat"),
        Path("/Volumes/flyem2/data/Z0720-07m_BR_Sec18/dat/Merlin-6257_21-05-20_125416_0-0-3.dat"),
    ]

    layers = split_into_layers(dat_file_paths)

    writer = DatToH5Writer(chunk_shape=(2, 256, 256))
    converter = DatConverter(volume_transfer_info)

    converter.convert(dat_layers=layers,
                      archive_writer=writer,
                      align_writer=writer,
                      skip_existing=True)

    # h5f = h5py.File(layer_h5_output_path)
    #
    # print(list(h5f.keys()))
    #
    # attributes = h5f['0-0-0'].attrs
    # for k, v in attributes.items():
    #     print(f"{k}: {v}")


if __name__ == "__main__":
    main()
