#!/usr/bin/env python

import requests
import sys


def get_stack_url(owner, project, stack):
    return f'http://tem-services.int.janelia.org:8080/render-ws/v1/owner/{owner}/project/{project}/stack/{stack}'


def get_response_json(url):
    response = requests.get(url)
    if response.status_code != 200:
        raise Exception("request failed for %s\n  status_code: %d\n  text: %s" %
                        (url, response.status_code, response.text))
    return response.json()


def get_resolved_tiles_for_layer(owner, project, stack, z):
    stack_url = get_stack_url(owner, project, stack)
    return get_response_json(f'{stack_url}/z/{z}/resolvedTiles')


def set_stack_state(owner, project, stack, state):
    stack_url = get_stack_url(owner, project, stack)
    url = f'{stack_url}/state/{state}'
    print(f'submitting PUT {url}')

    response = requests.put(url)
    response.raise_for_status()


def save_resolved_tiles(owner, project, stack, resolved_tiles):
    stack_url = get_stack_url(owner, project, stack)
    url = f'{stack_url}/resolvedTiles'
    print(f'submitting PUT {url} for {len(resolved_tiles["tileIdToSpecMap"])} tile specs')

    response = requests.put(url, json=resolved_tiles)
    response.raise_for_status()


def set_group_id(group_id, owner, project, stack, z_values):
    set_stack_state(owner, project, stack, "LOADING")

    for z in z_values:
        resolved_tiles = get_resolved_tiles_for_layer(owner, project, stack, z)
        tile_id_to_spec_map = resolved_tiles["tileIdToSpecMap"]
        for tile_id in tile_id_to_spec_map.keys():
            tile_spec = tile_id_to_spec_map[tile_id]
            tile_spec["groupId"] = group_id
        save_resolved_tiles(owner, project, stack, resolved_tiles)

    set_stack_state(owner, project, stack, "COMPLETE")


if __name__ == '__main__':
    if len(sys.argv) < 6:
        print(f'USAGE: {sys.argv[0]} <group_id> <owner> <project> <stack> <z> [z ...]')
    else:
        set_group_id(group_id=sys.argv[1],
                     owner=sys.argv[2],
                     project=sys.argv[3],
                     stack=sys.argv[4],
                     z_values=sys.argv[5:])

