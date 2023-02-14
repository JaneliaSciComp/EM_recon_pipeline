#!/usr/bin/env python

import requests


def get_stack_url(owner, project, stack):
    return f'http://tem-services.int.janelia.org:8080/render-ws/v1/owner/{owner}/project/{project}/stack/{stack}'


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


def set_stack_state(owner, project, stack, state):
    stack_url = get_stack_url(owner, project, stack)
    url = f'{stack_url}/state/{state}'
    print(f'submitting PUT {url}')

    response = requests.put(url)
    response.raise_for_status()


def patch_tile_specs(resolved_tiles,
                     old_correction_transform_name,
                     correction_transform_name,
                     correction_transform_value):
    del resolved_tiles["transformIdToSpecMap"][old_correction_transform_name]
    resolved_tiles["transformIdToSpecMap"][correction_transform_name] = correction_transform_value
    for tile_spec in resolved_tiles["tileIdToSpecMap"].values():
        tile_spec["transforms"]["specList"][0]["refId"] = correction_transform_name


def save_resolved_tiles_and_derive_data(owner, project, stack, resolved_tiles):
    stack_url = get_stack_url(owner, project, stack)
    url = f'{stack_url}/resolvedTiles?deriveData=true'
    print(f'submitting PUT {url} for {len(resolved_tiles["tileIdToSpecMap"])} tile specs')

    response = requests.put(url, json=resolved_tiles)
    response.raise_for_status()


def patch_v5(owner, project):
    stack = "v5_acquire"
    old_name = "FIBSEM_correct"
    for z in range(1, 1264):
        correction_transform_name = "FIBSEM_correct_ocellar_a"
        correction_transform_value = {
            "id": correction_transform_name,
            "className": "org.janelia.alignment.transform.SEMDistortionTransformA",
            "dataString": "21.17734375 74.809765625 42.730078125 1223.513671875 0"
        }
        resolved_tiles = get_resolved_tiles_for_layer(owner, project, stack, z)
        patch_tile_specs(resolved_tiles, old_name, correction_transform_name, correction_transform_value)
        save_resolved_tiles_and_derive_data(owner, project, stack, resolved_tiles)

    for z in range(1264, 19909):
        correction_transform_name = "FIBSEM_correct_ocellar_b"
        correction_transform_value = {
            "id": correction_transform_name,
            "className": "org.janelia.alignment.transform.SEMDistortionTransformA",
            "dataString": "19.4 301.05 54.4 3428.25 0"
        }
        resolved_tiles = get_resolved_tiles_for_layer(owner, project, stack, z)
        patch_tile_specs(resolved_tiles, old_name, correction_transform_name, correction_transform_value)
        save_resolved_tiles_and_derive_data(owner, project, stack, resolved_tiles)


def patch_v6(owner, project):
    stack = "v6_acquire"
    old_name = "FIBSEM_correct_ocellar_b"
    for z in range(1264, 19909):
        resolved_tiles = get_resolved_tiles_for_layer(owner, project, stack, z)
        correction_transform_name = "FIBSEM_correct_ocellar_b"
        correction_transform_value = {
            "id": correction_transform_name,
            "className": "org.janelia.alignment.transform.SEMDistortionTransformA",
            "dataString": "19.2438 98.9602 34.4000 1023.3672 0"
        }
        patch_tile_specs(resolved_tiles, old_name, correction_transform_name, correction_transform_value)
        save_resolved_tiles_and_derive_data(owner, project, stack, resolved_tiles)


def patch_v6b(owner, project):
    stack = "v6_acquire"
    old_name = "FIBSEM_correct_ocellar_b"
    for z in range(1264, 2100):
        resolved_tiles = get_resolved_tiles_for_layer(owner, project, stack, z)
        correction_transform_name = "FIBSEM_correct_ocellar_a"
        correction_transform_value = {
            "id": correction_transform_name,
            "className": "org.janelia.alignment.transform.SEMDistortionTransformA",
            "dataString": "21.17734375 74.809765625 42.730078125 1223.513671875 0"
        }
        patch_tile_specs(resolved_tiles, old_name, correction_transform_name, correction_transform_value)
        save_resolved_tiles_and_derive_data(owner, project, stack, resolved_tiles)

    for z in range(2100, 19909):
        resolved_tiles = get_resolved_tiles_for_layer(owner, project, stack, z)
        correction_transform_name = "FIBSEM_correct_ocellar_c"
        correction_transform_value = {
            "id": correction_transform_name,
            "className": "org.janelia.alignment.transform.SEMDistortionTransformA",
            "dataString": "19.2438 98.9602 34.4000 1023.3672 0"
        }
        patch_tile_specs(resolved_tiles, old_name, correction_transform_name, correction_transform_value)
        save_resolved_tiles_and_derive_data(owner, project, stack, resolved_tiles)


def main():
    owner = "reiser"
    project = "Z0422_05_Ocellar"
    # stack = "v5_acquire"
    stack = "v6_acquire"

    set_stack_state(owner, project, stack, "LOADING")

    # patch_v5(owner, project)
    # patch_v6(owner, project)
    patch_v6b(owner, project)

    set_stack_state(owner, project, stack, "COMPLETE")


if __name__ == '__main__':
    main()