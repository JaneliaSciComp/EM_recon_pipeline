import argparse
import traceback
from pathlib import Path

import h5py
import sys

from janelia_emrp.fibsem.dat_to_h5_writer import DAT_FILE_NAME_KEY


def print_header_data(h5_path: Path) -> None:
    with h5py.File(name=str(h5_path), mode="r") as h5_file:
        data_set_names = sorted(h5_file.keys())

        print(f"\n\n===============================================================================================")
        print(f"found {len(data_set_names)} data sets in {h5_path}\n")

        for data_set_name in data_set_names:
            data_set = h5_file.get(data_set_name)

            print(f"  -------------------------------------------------------------------------------------")
            print(f"  header attributes for data set '{data_set_name}' ({data_set.attrs[DAT_FILE_NAME_KEY]}):")
            print(f"  -------------------------------------------------------------------------------------")

            for key in sorted(data_set.attrs.keys()):
                print(f"    {key:30}: {data_set.attrs[key]}")

            print()


def main(arg_list: list[str]):
    parser = argparse.ArgumentParser(
        description="Validate that byte contents of HDF5 and dat files match or restore dat files to disk."
    )
    parser.add_argument(
        "--h5_path",
        help="Path(s) of source HDF5 file(s)",
        required=True,
        nargs='+'
    )

    args = parser.parse_args(arg_list)

    h5_path_list = [Path(p) for p in args.h5_path]
    for h5_path in h5_path_list:
        print_header_data(h5_path)


if __name__ == "__main__":
    # NOTE: to fix module not found errors, export PYTHONPATH="/.../EM_recon_pipeline/src/python"

    # noinspection PyBroadException
    try:
        # main(sys.argv[1:])
        main(["--h5_path", "/Users/trautmane/Desktop/Merlin-6284_22-10-12_112309.raw-archive.h5"])
    except Exception as e:
        # ensure exit code is a non-zero value when Exception occurs
        traceback.print_exc()
        sys.exit(1)
