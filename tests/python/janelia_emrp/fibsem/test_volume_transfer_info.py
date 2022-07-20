import json

from janelia_emrp.fibsem.volume_transfer_info import VolumeTransferInfo


def test_json(volume_transfer_info):
    json_string = volume_transfer_info.json()

    debug_json_object = json.loads(json_string)
    print(f"\nencoded {volume_transfer_info} as:")
    print(json.dumps(debug_json_object, indent=True))

    parsed_info = VolumeTransferInfo.parse_raw(json_string)

    assert volume_transfer_info == parsed_info, "source and parsed data differ"

    json_string_with_null_values = """
{
 "transfer_id": "test_owner::test_project::test_scope",
 "scope_data_set": {
  "host": "jeiss8.hhmi.org",
  "root_dat_path": "/cygdrive/e/Images/Fly Brain",
  "root_keep_path": "/cygdrive/d/UploadFlags",
  "data_set_id": "Z0720-07m_VNC_Sec06",
  "first_dat_name": "Merlin-6284_21-07-27_201550_0-0-0.dat",
  "last_dat_name": null,
  "dat_x_and_y_nm_per_pixel": 8,
  "dat_z_nm_per_pixel": 8,
  "dat_tile_overlap_microns": 2
 },
 "max_mipmap_level": 7,
 "transfer_tasks": [
  "COPY_SCOPE_DAT_TO_CLUSTER"
 ],
 "cluster_job_project_for_billing": "scicompsoft"
}"""
    parsed_info = VolumeTransferInfo.parse_raw(json_string_with_null_values)

    assert parsed_info.scope_data_set.last_dat_name is None, "failed to parse null last_dat_name value"
    assert parsed_info.render_data_set is None, "failed to parse missing render_data_set value"

