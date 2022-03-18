#!/usr/bin/env python

import json

import requests


def get_stack_url(owner, project, stack):
    return f'http://tem-services.int.janelia.org:8080/render-ws/v1/owner/{owner}/project/{project}/stack/{stack}'


def get_response_json(url):
    response = requests.get(url)
    if response.status_code != 200:
        raise Exception("request failed for %s\n  status_code: %d\n  text: %s" %
                        (url, response.status_code, response.text))
    return response.json()


def get_stack_z_values(owner, project, stack):
    stack_url = get_stack_url(owner, project, stack)
    return get_response_json(f'{stack_url}/zValues')


def get_resolved_tiles_for_layer(owner, project, stack, z):
    stack_url = get_stack_url(owner, project, stack)
    return get_response_json(f'{stack_url}/z/{z}/resolvedTiles')


def main():
    owner = "flyTEM"
    project = "FAFB00"
    stack = "v14_align_tps_20170818"

    z_with_tps = []
    for z in get_stack_z_values(owner, project, stack):
        resolved_tiles = get_resolved_tiles_for_layer(owner, project, stack, z)
        for key in resolved_tiles["transformIdToSpecMap"]:
            if key.endswith("TPS"):
                z_with_tps.append(z)
                break
        if z % 50 == 0:
            print(f'checked z {z}, found {len(z_with_tps)} TPS layers')

    z_with_tps_path = '/Users/trautmane/Desktop/z_with_tps.json'
    print(f'writing z values for {len(z_with_tps)} TPS layers to {z_with_tps_path}')

    with open(z_with_tps_path, 'w') as results_file:
        json.dump(z_with_tps, results_file)


if __name__ == '__main__':
    main()
