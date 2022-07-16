import json

from janelia_emrp.fibsem.volume_transfer_info import VolumeTransferInfo


def test_json(volume_transfer_info):
    json_string = volume_transfer_info.json()

    debug_json_object = json.loads(json_string)
    print(f"\nencoded {volume_transfer_info} as:")
    print(json.dumps(debug_json_object, indent=True))

    parsed_info = VolumeTransferInfo.parse_raw(json_string)

    assert volume_transfer_info == parsed_info, "source and parsed data differ"
