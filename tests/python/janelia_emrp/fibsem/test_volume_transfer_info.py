import json
from datetime import datetime
from pathlib import Path

from janelia_emrp.fibsem.volume_transfer_info import VolumeTransferInfo


def test_json():

    volume_transfer_info = VolumeTransferInfo(
        scope="jeiss2.hhmi.org",
        scope_storage_root=Path("/cygdrive/e/Images/Renel Cell Carcinoma"),
        dat_storage_root=Path("/nearline/flyem2/data/NIH-J1/dat"),
        acquire_start=datetime.strptime("22-03-08_223009", "%y-%m-%d_%H%M%S"),
        acquire_stop=datetime.strptime("22-03-17_082104", "%y-%m-%d_%H%M%S"),
        archive_storage_root=Path("/nearline/flyem2/data/NIH-J1/h5"),
        remove_dat_after_archive=False,
        align_storage_root=Path("/nrs/flyem/render/data/test_h5/NIH_J1"),
        max_mipmap_level=7,
        render_owner="test_h5",
        render_project="NIH_J1"
    )

    json_string = volume_transfer_info.json()

    debug_json_object = json.loads(json_string)
    print(f"\nencoded {volume_transfer_info} as:")
    print(json.dumps(debug_json_object, indent=True))

    parsed_info = VolumeTransferInfo.parse_raw(json_string)

    assert volume_transfer_info == parsed_info, "source and parsed data differ"
