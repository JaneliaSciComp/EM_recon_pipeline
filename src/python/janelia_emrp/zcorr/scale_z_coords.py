#!/usr/bin/env python
import argparse
import csv
import sys
from typing import Optional


def parse_scale_file(scale_csv_path: str) -> dict[int, float]:
    z_to_scale = {}
    if scale_csv_path is not None:
        with open(scale_csv_path, 'r') as scale_file:
            csv_reader = csv.reader(scale_file)
            for row in csv_reader:
                if len(row) == 2:
                    z_to_scale[int(row[0])] = float(row[1])
    return z_to_scale


def parse_z_coords_file(z_coords_path: str) -> list[(int, float)]:
    z_to_corrected = []
    print(f'reading {z_coords_path}')
    with open(z_coords_path, 'r') as z_coords_file:
        for line in z_coords_file:
            words = line.split()
            z_to_corrected.append((int(words[0]), float(words[1])))
    return z_to_corrected


def scale_z_coords(from_original_z: int,
                   to_original_z: int,
                   default_scale_factor: float,
                   z_to_scale: dict[int, float],
                   z_coords_path: Optional[str],
                   scaled_z_coords_path: str):

    layer_count = 0
    first_z = None
    previous_corrected_z = 0
    previous_original_corrected_z = 0

    print('\n------------------------------------------------------------------')

    if z_coords_path is not None:
        z_to_corrected = parse_z_coords_file(z_coords_path)
    else:
        z_to_corrected = [(z, float(z)) for z in range(from_original_z, to_original_z + 1)]

    with open(scaled_z_coords_path, 'w') as scaled_file:
        for (original_z, original_corrected_z) in z_to_corrected:
            layer_count = layer_count + 1
            corrected_z = original_corrected_z
            if not first_z:
                first_z = original_z
            elif original_z >= from_original_z:
                delta = original_corrected_z - previous_original_corrected_z
                scale = z_to_scale[original_z] if original_z in z_to_scale else default_scale_factor
                if original_z <= to_original_z:
                    scaled_delta = scale * delta
                    corrected_z = previous_corrected_z + scaled_delta
                else:
                    corrected_z = previous_corrected_z + delta

            scaled_file.write(f'{original_z} {corrected_z}\n')

            previous_original_corrected_z = original_corrected_z
            previous_corrected_z = corrected_z

    print(f'wrote corrections for {layer_count} layers to {scaled_z_coords_path}')


def main(arg_list: list[str]):
    parser = argparse.ArgumentParser(
        description="Produce Zcoords.txt file with scaled values"
    )
    parser.add_argument(
        "--min_z",
        help="First z to scale",
        type=int,
        required=True
    )
    parser.add_argument(
        "--max_z",
        help="Last z to scale",
        type=int,
        required=True
    )
    parser.add_argument(
        "--out",
        help="Output file path",
        required=True
    )
    parser.add_argument(
        "--z_coords_file",
        help="Zcoords.txt file to scale (omit to use and scale min_z to max_z range)",
        default=None
    )
    parser.add_argument(
        "--scale_csv_file",
        help="CSV file with z to scale mapping",
        default=None
    )
    parser.add_argument(
        "--scale",
        help="Scaling factor to apply to all z",
        type=float,
        default=1.0
    )
    args = parser.parse_args(arg_list)

    z_to_scale = parse_scale_file(args.scale_csv_file)

    scale_z_coords(from_original_z=args.min_z,
                   to_original_z=args.max_z,
                   default_scale_factor=args.scale,
                   z_to_scale=z_to_scale,
                   z_coords_path=args.z_coords_file,
                   scaled_z_coords_path=args.out)


if __name__ == '__main__':
    main(sys.argv[1:])
    # main([
    #     "--min_z", "1",
    #     "--max_z", "67392",
    #     "--out", "/Users/trautmane/Desktop/stern/VNC_z_corr/Zcoords.scaled.txt",
    #     "--scale_csv_file", "/Users/trautmane/Desktop/stern/VNC_z_corr/zsteps.txt"
    # ])
