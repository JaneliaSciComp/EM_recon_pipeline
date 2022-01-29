#!/usr/bin/env python
import argparse
import os
import re

from fibsem_tools.io import read

# Merlin-6049_15-06-16_000059_0-0-0-InLens.png
base_name_pattern = re.compile(r".*((\d\d-\d\d-\d\d_\d{6})_\d-(\d)-(\d)).*")
default_print_keys = [
    "ChanNum", "EightBit", "FirstX", "FirstY", "PixelSize", "Restart",
    "SampleID" "StageMove", "StageR", "StageX", "StageY", "StageZ",
    "SWdate", "TabID", "WD", "XResolution", "YResolution"
]


def print_headers(dat_file_paths, print_keys, format_tsv=None):
    for path in dat_file_paths:
        if not os.path.exists(path):
            raise ValueError(f"file not found: {path}")

    header_index = 0
    batch_size = 100
    for i in range(0, len(dat_file_paths), batch_size):
        header_dict_list = [record.header.__dict__ for record in read(dat_file_paths[i:i+batch_size])]

        if header_index == 0 and format_tsv:
            print("path", end='\t')
            for key in sorted(header_dict_list[0].keys()):
                if print_keys is None or key in print_keys:
                    print(key, end='\t')
            print()

        for j in range(0, len(header_dict_list)):
            header_dict = header_dict_list[j]
            file_path = dat_file_paths[header_index]

            if format_tsv:
                print(file_path, end='\t')
            else:
                print('\n===========================================')
                print(f'{file_path}:\n')

            for key in sorted(header_dict):
                if print_keys is None or key in print_keys:
                    value = header_dict[key]
                    if format_tsv:
                        print(value, end='\t')
                    else:
                        print(f'  {key}: {value}')

            if format_tsv:
                print()

            header_index += 1


def main():
    parser = argparse.ArgumentParser(
        description="Parse and print dat header information."
    )
    parser.add_argument(
        "--tsv",
        help="print data in tab separated value format",
        action='store_true'
    )
    parser.add_argument(
        "--all_keys",
        help="print all header key values (overrides any explicitly identified keys)",
        action='store_true'
    )
    parser.add_argument(
        "--key",
        help="keys of headers to print",
        default=default_print_keys,
        nargs="+"
    )
    parser.add_argument(
        "--file",
        help="path(s) of dat file(s) to parse",
        nargs="+"
    )
    parser.add_argument(
        "--file_list",
        help="text file containing paths of dat files to parse",
    )

    args = parser.parse_args()

    print_keys = None if args.all_keys else args.key

    if args.file_list:
        with open(args.file_list) as file:
            path_list = file.read().splitlines()
    else:
        path_list = args.file

    if path_list and len(path_list) > 0:
        print_headers(path_list, print_keys, args.tsv)
    else:
        print("No dat files to parse!  Use --file or --file_list to specify data files.")


if __name__ == "__main__":
    main()
