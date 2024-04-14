#!/usr/bin/env python

import copy
import requests


def get_stack_url(owner, project, stack):
    return f'http://em-services-1.int.janelia.org:8080/render-ws/v1/owner/{owner}/project/{project}/stack/{stack}'


def get_response_json(url):
    response = requests.get(url)
    if response.status_code != 200:
        raise Exception("request failed for %s\n  status_code: %d\n  text: %s" %
                        (url, response.status_code, response.text))
    return response.json()


def get_tile_spec(owner, project, stack, tile_id):
    stack_url = get_stack_url(owner, project, stack)
    return get_response_json(f'{stack_url}/tile/{tile_id}')


def get_resolved_tiles_for_layer(owner, project, stack, z):
    stack_url = get_stack_url(owner, project, stack)
    return get_response_json(f'{stack_url}/z/{z}/resolvedTiles')


def to_patched_tile_spec(from_tile_spec, tile_spec_to_patch):
    patch_section_id = tile_spec_to_patch["layout"]["sectionId"]

    labels = {"patch"}
    if "labels" in from_tile_spec.keys():
        labels.update(from_tile_spec["labels"])
    if "labels" in tile_spec_to_patch.keys():
        labels.update(tile_spec_to_patch["labels"])

    patched_tile_spec = copy.deepcopy(from_tile_spec)
    patched_tile_spec["z"] = tile_spec_to_patch["z"]
    from_tile_id = from_tile_spec["tileId"]
    base_tile_id = from_tile_id[0:from_tile_id.find('.')]  # tileId: 19-07-20_112626_0-0-2.9359.0
    patched_tile_spec["tileId"] = f'{base_tile_id}.patch.{patch_section_id}'
    patched_tile_spec["layout"]["sectionId"] = patch_section_id
    patched_tile_spec["labels"] = sorted(labels)
    return patched_tile_spec


def same_row_and_column(tile_spec_a, tile_spec_b):
    return tile_spec_a["layout"]["imageRow"] == tile_spec_b["layout"]["imageRow"] and \
           tile_spec_a["layout"]["imageCol"] == tile_spec_b["layout"]["imageCol"]


def set_stack_state(owner, project, stack, state):
    stack_url = get_stack_url(owner, project, stack)
    url = f'{stack_url}/state/{state}'
    print(f'submitting PUT {url}')

    response = requests.put(url)
    response.raise_for_status()


def remove_tile_spec(owner, project, stack, tile_id):
    stack_url = get_stack_url(owner, project, stack)
    url = f'{stack_url}/tile/{tile_id}'
    print(f'submitting DELETE {url}')

    response = requests.delete(url)
    response.raise_for_status()


def save_resolved_tiles(owner, project, stack, resolved_tiles):
    stack_url = get_stack_url(owner, project, stack)
    url = f'{stack_url}/resolvedTiles'
    print(f'submitting PUT {url} for {len(resolved_tiles["tileIdToSpecMap"])} tile specs')

    response = requests.put(url, json=resolved_tiles)
    response.raise_for_status()


def build_missing_tile_json_string(layer_timestamp, z, row, column):
    tile_id = f'{layer_timestamp}_0-{row}-{column}.{z}.0'
    layout = f'{{"sectionId": "{z}.0", "imageRow": {row}, "imageCol": {column}}}'
    tile_spec = f'{{"tileId": "{tile_id}", "z": {z}, "layout": {layout}}}'

    # "24-03-01_143550_0-0-3.15438.0": {
    #     "tileId": "24-03-01_143550_0-0-3.15438.0",
    #     "z": 15438,
    #     "layout": { "sectionId": "15438.0", "imageRow": 0, "imageCol": 3}
    # },
    return f'"{tile_id}": {tile_spec}'


def main():
    owner = "RENDER_OWNER"  # TODO: update with render stack owner
    project = "RENDER_PROJECT"  # TODO: render stack project
    stack = "ACQUIRE_TRIMMED_STACK"  # TODO: update with render stack

    # TODO: update tile ids
    tile_ids_to_patch = [
    ]

    # missing_layer_timestamp = "24-03-01_143550"
    # missing_layer_z = 15438
    missing_tile_ids_to_specs = {
        # build_missing_tile_json_string(missing_layer_timestamp, missing_layer_z, 0, 3),
        # build_missing_tile_json_string(missing_layer_timestamp, missing_layer_z, 0, 4),
        # build_missing_tile_json_string(missing_layer_timestamp, missing_layer_z, 1, 0),
        # build_missing_tile_json_string(missing_layer_timestamp, missing_layer_z, 1, 1),
        # build_missing_tile_json_string(missing_layer_timestamp, missing_layer_z, 1, 2),
        # build_missing_tile_json_string(missing_layer_timestamp, missing_layer_z, 1, 3),
        # build_missing_tile_json_string(missing_layer_timestamp, missing_layer_z, 1, 4),
    }

    patched_resolved_tiles = {
        "transformIdToSpecMap": {},
        "tileIdToSpecMap": {}
    }

    tile_ids_to_remove = []

    for tile_id, delta_z in tile_ids_to_patch:

        if tile_id in missing_tile_ids_to_specs:
            tile_spec_to_patch = missing_tile_ids_to_specs[tile_id]
        else:
            tile_spec_to_patch = get_tile_spec(owner, project, stack, tile_id)

        adjacent_layer_resolved_tiles = \
            get_resolved_tiles_for_layer(owner, project, stack, tile_spec_to_patch["z"] + delta_z)
        if "transformIdToSpecMap" in adjacent_layer_resolved_tiles:
            transform_id_to_spec_map = adjacent_layer_resolved_tiles["transformIdToSpecMap"]
            for transform_id in transform_id_to_spec_map.keys():
                patched_resolved_tiles["transformIdToSpecMap"][transform_id] = transform_id_to_spec_map[transform_id]
            
        from_tile_spec = None
        for prior_tile_id in adjacent_layer_resolved_tiles["tileIdToSpecMap"].keys():
            prior_tile_spec = adjacent_layer_resolved_tiles["tileIdToSpecMap"][prior_tile_id]
            if same_row_and_column(tile_spec_to_patch, prior_tile_spec):
                from_tile_spec = prior_tile_spec
                break
        if from_tile_spec:
            patched_tile_spec = to_patched_tile_spec(from_tile_spec, tile_spec_to_patch)
            patched_resolved_tiles["tileIdToSpecMap"][patched_tile_spec["tileId"]] = patched_tile_spec
            tile_ids_to_remove.append(tile_id)

    if len(tile_ids_to_remove) > 0:
        set_stack_state(owner, project, stack, "LOADING")
        save_resolved_tiles(owner, project, stack, patched_resolved_tiles)
        for tile_id in tile_ids_to_remove:
            remove_tile_spec(owner, project, stack, tile_id)
        set_stack_state(owner, project, stack, "COMPLETE")


if __name__ == '__main__':
    main()

