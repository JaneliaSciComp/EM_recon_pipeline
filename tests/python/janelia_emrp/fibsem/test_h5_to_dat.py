from janelia_emrp.fibsem.h5_to_dat import validate_original_dat_bytes_match


def test_validate_original_dat_bytes_match(small_dat_path,
                                           small_raw_path):

    try:
        matched_dat_file_paths = validate_original_dat_bytes_match(h5_path=small_raw_path,
                                                                   dat_parent_path=small_dat_path.parent)
    except ValueError as ve:
        assert False, f"caught exception: {ve}"

    assert len(matched_dat_file_paths) == 1, "restored dat bytes do not match"
