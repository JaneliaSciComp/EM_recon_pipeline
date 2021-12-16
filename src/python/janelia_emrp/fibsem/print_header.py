#!/usr/bin/env python

import re
import sys

from fibsem_tools.io import read

# the name of this program
program_name = "print_header.py"

# Merlin-6049_15-06-16_000059_0-0-0-InLens.png
base_name_pattern = re.compile(r".*((\d\d-\d\d-\d\d_\d{6})_\d-(\d)-(\d)).*")
common_tile_header_keys = [
    "XResolution", "YResolution", "PixelSize", "EightBit", "ChanNum", "SWdate",
    "StageX", "StageY", "StageZ", "StageR"
]
retained_tile_header_keys = common_tile_header_keys + ["WD"]
checked_tile_header_keys = common_tile_header_keys + ["TabID"]

new_keys = ["Restart", "StageMove", "FirstX", "FirstY", "SampleID"]

print_keys = common_tile_header_keys + ["WD", "TabID", "Notes"] + new_keys


def print_headers(dat_file_names, print_all_keys):
    print(f'reading headers for: {dat_file_names}')
    records = read(dat_file_names)
    headers = []
    for i in range(0, len(records)):
        print('\n===========================================')
        record = records[i]
        for key in sorted(record.header.__dict__):
            if print_all_keys or key in print_keys:
                print(f'{key}: {record.header.__dict__[key]}')

    return headers


if __name__ == "__main__":
    if sys.argv[1] == "all":
        print_all = True
        file_names = sys.argv[2:]
    else:
        print_all = False
        file_names = sys.argv[1:]

    print_headers(file_names, print_all)