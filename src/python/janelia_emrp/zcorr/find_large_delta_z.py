#!/usr/bin/env python

import sys


def print_batch(stretched_or_squished_z):
    layer_count = len(stretched_or_squished_z)
    (first_z, first_corrected_z, first_delta) = stretched_or_squished_z[0]
    (last_z, last_corrected_z, last_delta) = stretched_or_squished_z[-1]
    print(f'found {layer_count:4} layers, '
          f'first: z {first_z:5} corrected to z {first_corrected_z:8.2f} with delta {first_delta:3.2f}, '
          f'last: z {last_z:5} corrected to z {last_corrected_z:8.2f} with delta {last_delta:3.2f} ')


def print_large_delta_z(min_consecutive_layers, min_delta_z, max_delta_z, z_coords_path):

    layer_count = 0
    first_z = None
    previous_corrected_z = 0

    print('\n------------------------------------------------------------------')
    print(f'checking {z_coords_path}')
    print(f'for groups of {min_consecutive_layers} layers or more '
          f'with delta z < {min_delta_z} or delta z > {max_delta_z}:\n')

    stretched_or_squished_z = []
    with open(z_coords_path, 'r') as z_coords_file:
        for line in z_coords_file:
            layer_count = layer_count + 1
            words = line.split()
            original_z = int(words[0])
            corrected_z = float(words[1])
            if not first_z:
                first_z = original_z
            else:
                delta = corrected_z - previous_corrected_z
                if delta < min_delta_z or delta > max_delta_z:
                    stretched_or_squished_z.append((original_z, corrected_z, delta))
                else:
                    if len(stretched_or_squished_z) > min_consecutive_layers:
                        print_batch(stretched_or_squished_z)
                    stretched_or_squished_z = []

            previous_corrected_z = corrected_z

    if len(stretched_or_squished_z) > min_consecutive_layers:
        print_batch(stretched_or_squished_z)


if __name__ == '__main__':
    if len(sys.argv) < 5:
        print(f'USAGE: {sys.argv[0]} <min_consecutive_layers> <min_delta_z> <max_delta_z> <zCoords.txt> [zCoords.txt ...]')
    else:
        for z_coords_path in sys.argv[4:]:
            print_large_delta_z(
                min_consecutive_layers=int(sys.argv[1]),
                min_delta_z=float(sys.argv[2]),
                max_delta_z=float(sys.argv[3]),
                z_coords_path=z_coords_path)
            