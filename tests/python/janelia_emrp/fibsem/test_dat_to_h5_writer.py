import h5py
import numpy as np

from janelia_emrp.fibsem.cyx_dat import CYXDat, new_cyx_dat
from janelia_emrp.fibsem.dat_converter import DatConverter
from janelia_emrp.fibsem.dat_path import new_dat_path, new_dat_layer
from janelia_emrp.fibsem.dat_to_h5_writer import DatToH5Writer, ELEMENT_SIZE_UM_KEY


def test_create_and_add_mipmap_data_sets(volume_transfer_info,
                                         small_dat_path,
                                         small_uint8_path):
    align_writer = DatToH5Writer(chunk_shape=(1, 20, 20))
    converter = DatConverter(volume_transfer_info=volume_transfer_info,
                             raw_writer=None,
                             align_writer=align_writer,
                             skip_existing=True)

    dat_path = new_dat_path(small_dat_path)
    dat_paths_for_layer = new_dat_layer(dat_path)

    cyx_dat: CYXDat = new_cyx_dat(dat_path)

    align_path = dat_paths_for_layer.get_h5_path(volume_transfer_info.cluster_root_paths.align_h5,
                                                 source_type="uint8")
    align_path = converter.setup_h5_path("align source", align_path, True)

    with align_writer.open_h5_file(str(align_path)) as align_file, \
            h5py.File(name=str(small_uint8_path), mode="r") as expected_align_file:
        align_writer.create_and_add_mipmap_data_sets(cyx_dat_list=[cyx_dat],
                                                     max_mipmap_level=volume_transfer_info.max_mipmap_level,
                                                     to_h5_file=align_file,
                                                     fill_info=None)
        
        assert align_path.exists(), f"{str(align_path)} not created"

        expected_group_name = "0-0-1"
        group = align_file.get(expected_group_name)
        assert group is not None, f"group {expected_group_name} not found"

        data_set_names = sorted(group.keys())
        assert len(data_set_names) == 7, "incorrect number of data sets created"

        assert "XResolution" in group.attrs, "XResolution missing from group attributes"
        assert ELEMENT_SIZE_UM_KEY not in group.attrs, "element_size_um should not be in group attributes"

        data_set_name = data_set_names[2]
        data_set = group.get(data_set_name)
        assert ELEMENT_SIZE_UM_KEY in data_set.attrs, \
            f"element_size_um missing from {data_set_name} data set attributes"
        assert "XResolution" not in data_set.attrs, f"XResolution should not be in {data_set_name} data set attributes"

        expected_group = expected_align_file.get(expected_group_name)
        expected_data_set = expected_group.get(data_set_name)
        expected_pixels = np.array(expected_data_set[:])
        actual_pixels = np.array(data_set[:])

        assert np.array_equal(actual_pixels, expected_pixels), f"{data_set_name} pixels do not match expected result"
