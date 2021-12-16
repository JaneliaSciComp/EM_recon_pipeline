#!/usr/bin/env python

import sys


def scale_delta_z(from_original_z, to_original_z, scale, z_coords_path):

    scaled_z_coords_path = f'{z_coords_path}.scaled'

    layer_count = 0
    first_z = None
    previous_corrected_z = 0
    previous_original_corrected_z = 0

    print('\n------------------------------------------------------------------')
    print(f'reading {z_coords_path}')
    print(f'scaling z {from_original_z} to z {to_original_z} by {scale}')

    with open(z_coords_path, 'r') as z_coords_file, open(scaled_z_coords_path, 'w') as scaled_file:
        for line in z_coords_file:
            layer_count = layer_count + 1
            words = line.split()
            original_z = int(words[0])
            original_corrected_z = float(words[1])
            corrected_z = original_corrected_z
            if not first_z:
                first_z = original_z
            elif original_z >= from_original_z:
                delta = original_corrected_z - previous_original_corrected_z
                if original_z <= to_original_z:
                    scaled_delta = scale * delta
                    corrected_z = previous_corrected_z + scaled_delta
                else:
                    corrected_z = previous_corrected_z + delta

            scaled_file.write(f'{original_z} {corrected_z}\n')

            previous_original_corrected_z = original_corrected_z
            previous_corrected_z = corrected_z

    print(f'wrote corrections for {layer_count} layers to {scaled_z_coords_path}')


if __name__ == '__main__':
    if len(sys.argv) != 5:
        print(f'USAGE: {sys.argv[0]} <from_original_z> <to_original_z> <scale> <zCoords.txt>')
    else:
        scale_delta_z(from_original_z=int(sys.argv[1]),
                      to_original_z=float(sys.argv[2]),
                      scale=float(sys.argv[3]),
                      z_coords_path=sys.argv[4])