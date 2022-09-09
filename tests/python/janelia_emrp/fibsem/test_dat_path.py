from pathlib import Path

from janelia_emrp.fibsem.dat_path import rename_dat_files, split_into_layers


def test_dat_path_parsing():
    dat_file_paths = [
        Path("/flyem2/data/Z0720-07m_BR_Sec18/dat/Merlin-6257_21-05-20_125416_0-0-0.dat"),
        Path("/flyem2/data/Z0720-07m_BR_Sec18/dat/Merlin-6257_21-05-20_125416_0-0-1.dat"),
        Path("/flyem2/data/Z0720-07m_BR_Sec18/dat/Merlin-6257_21-05-20_125416_0-0-2.dat"),
        Path("/flyem2/data/Z0720-07m_BR_Sec18/dat/Merlin-6257_21-05-20_125416_0-0-3.dat"),
        Path("/flyem2/data/Z0720-07m_BR_Sec18/dat/Merlin-6257_21-05-20_125527_0-0-0.dat"),
        Path("/flyem2/data/Z0720-07m_BR_Sec18/dat/Merlin-6257_21-05-20_125527_0-0-1.dat"),
        Path("/flyem2/data/Z0720-07m_BR_Sec18/dat/Merlin-6257_21-05-20_125527_0-0-2.dat"),
        Path("/flyem2/data/Z0720-07m_BR_Sec18/dat/Merlin-6257_21-05-20_125638_0-0-0.dat"),
        Path("/flyem2/data/Z0720-07m_BR_Sec18/dat/Merlin-6257_21-05-20_125749_0-0-0.dat"),
        Path("/flyem2/data/Z0720-07m_BR_Sec18/dat/Merlin-6257_21-05-20_125749_0-0-1.dat"),
        Path("/flyem2/data/Z0720-07m_BR_Sec18/dat/Merlin-6257_21-05-20_125749_0-0-2.dat"),
        Path("/flyem2/data/Z0720-07m_BR_Sec18/dat/Merlin-6257_21-05-20_125749_0-0-3.dat"),
    ]

    dat_layers = split_into_layers(path_list=dat_file_paths)

    expected_layer_ids = [
        "Merlin-6257_21-05-20_125416",
        "Merlin-6257_21-05-20_125527",
        "Merlin-6257_21-05-20_125638",
        "Merlin-6257_21-05-20_125749"
    ]
    expected_number_of_paths = [4, 3, 1, 4]

    assert len(expected_layer_ids) == len(dat_layers), "split returned incorrect number of layers"

    for i in range(0, len(dat_layers)):
        assert expected_layer_ids[i] == dat_layers[i].get_layer_id(), f"incorrect layer id for layer {i}"
        assert expected_number_of_paths[i] == len(dat_layers[i].dat_paths), f"incorrect number of paths for layer {i}"

    h5_path = dat_layers[0].get_h5_path(Path("/h5_root"))

    expected_h5_path = Path("/h5_root/Merlin-6257/2021/05/20/12/Merlin-6257_21-05-20_125416.raw.h5")
    assert expected_h5_path == h5_path, "invalid h5_path for default case"

    h5_path = dat_layers[0].get_h5_path(h5_root_path=Path("/h5_root"),
                                        append_acquisition_based_subdirectories=False,
                                        source_type="uint8")

    expected_h5_path = Path("/h5_root/Merlin-6257_21-05-20_125416.uint8.h5")
    assert expected_h5_path == h5_path, "invalid h5_path when excluding subdirectories"


def test_rename_dat_files(tmp_path: Path):

    dat_names = [
        "Merlin-6281_22-07-21_014314_0-0-0.dat",
        "Merlin-6281_22-07-21_014314_0-0-1.dat",
        "Merlin-6281_22-07-29_151723_0-0-0.dat",
        "Merlin-6281_22-07-29_151723_0-0-1.dat"
    ]
    source_dir = tmp_path / "source"
    source_dir.mkdir()
    for dat_name in dat_names:
        dat_path = source_dir / dat_name
        dat_path.write_text("test")

    target_dir = tmp_path / "target"
    target_dir.mkdir()

    rename_dat_files(source_dir=source_dir,
                     target_dir=target_dir)

    expected_dir = target_dir / "2022/07/21/01"
    assert expected_dir.is_dir(), f"{expected_dir} does not exist"

    expected_file = expected_dir / dat_names[0]
    assert expected_file.exists(), f"{expected_file} does not exist"

    expected_dir = target_dir / "2022/07/29/15"
    assert expected_dir.is_dir(), f"{expected_dir} does not exist"

    expected_file = expected_dir / dat_names[3]
    assert expected_file.exists(), f"{expected_file} does not exist"
