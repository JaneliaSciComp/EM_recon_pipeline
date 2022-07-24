from janelia_emrp.fibsem.dat_keep_file import KeepFile


def test_serialization(tmp_path):
    keep_root = "/cygdrive/d/UploadFlags"
    keep_path = f"{keep_root}/zonation2^E^^Images^Mouse^Y2022^M07^D21^Merlin-6281_22-07-21_012643_0-1-2.dat^keep"
    keep_file = KeepFile(host="jeiss6.hhmi.org",
                         keep_path=keep_path,
                         data_set="zonation2",
                         dat_path="/cygdrive/E/Images/Mouse/Y2022/M07/D21/Merlin-6281_22-07-21_012643_0-1-2.dat")

    json_path = tmp_path / "keep.json"
    with open(json_path, 'w', encoding='utf-8') as f:
        f.write(keep_file.json())

    parsed_keep_file = KeepFile.parse_file(json_path)

    assert parsed_keep_file.keep_path == keep_path, "serialized keep path does not match"
