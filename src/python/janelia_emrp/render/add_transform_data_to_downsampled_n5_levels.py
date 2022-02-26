#!/usr/bin/env python

import json
import sys


def main(group_path):
    group_attributes_path = f'{group_path}/attributes.json'
    with open(group_attributes_path, 'r') as group_attributes_file:
        print(f'loading {group_attributes_path}')
        group_attributes = json.load(group_attributes_file)

    group_axes = group_attributes["axes"]
    group_dimensions = group_attributes["pixelResolution"]["dimensions"]
    group_units = group_attributes["units"]

    scales_index = 0
    for level_factors in group_attributes["scales"]:

        s_name = f's{scales_index}'

        transform_data = {
            "axes": [],
            "ordering": "C",
            "scale": [],
            "translate": [],
            "units": []
        }

        dimension_index = 0
        for factor in level_factors:
            unscaled_translation = (factor - 1) / 2
            transform_data["axes"].append(group_axes[dimension_index])
            transform_data["scale"].append(factor * group_dimensions[dimension_index])
            transform_data["translate"].append(unscaled_translation * group_dimensions[dimension_index])
            transform_data["units"].append(group_units[dimension_index])
            dimension_index += 1

        level_attributes_path = f'{group_path}/{s_name}/attributes.json'
        with open(level_attributes_path, 'r') as level_attributes_file:
            print(f'loading {level_attributes_path}')
            level_attributes = json.load(level_attributes_file)

        level_attributes["transform"] = transform_data

        with open(level_attributes_path, 'w') as level_attributes_file:
            json.dump(level_attributes, level_attributes_file, indent=2)
            print(f'updated {level_attributes_path}')

        scales_index += 1


if __name__ == '__main__':
    if len(sys.argv) == 2:
        main(sys.argv[1])
    else:
        print(f'USAGE: {sys.argv[0]} <n5GroupPath>')
