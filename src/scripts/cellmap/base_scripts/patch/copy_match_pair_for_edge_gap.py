#!/usr/bin/env python

from dataclasses import dataclass

import requests


@dataclass
class CanvasIdPair:
    p_group_id: str
    p_id: str
    q_group_id: str
    q_id: str


def get_stack_url(host, owner, project, stack):
    return f'http://{host}/render-ws/v1/owner/{owner}/project/{project}/stack/{stack}'


def get_collection_url(host, owner, match_collection):
    return f'http://{host}/render-ws/v1/owner/{owner}/matchCollection/{match_collection}'


def get_response_json(url):
    response = requests.get(url)
    if response.status_code != 200:
        raise Exception("request failed for %s\n  status_code: %d\n  text: %s" %
                        (url, response.status_code, response.text))
    return response.json()


def get_tile_spec(host, owner, project, stack, tile_id):
    stack_url = get_stack_url(host, owner, project, stack)
    return get_response_json(f'{stack_url}/tile/{tile_id}')


def get_resolved_tiles_for_layer(host, owner, project, stack, z):
    stack_url = get_stack_url(host, owner, project, stack)
    return get_response_json(f'{stack_url}/z/{z}/resolvedTiles')


def get_pair_matches(host, owner, collection, pair):
    url = "%s/group/%s/id/%s/matchesWith/%s/id/%s" % \
          (get_collection_url(host, owner, collection), pair.p_group_id, pair.p_id, pair.q_group_id, pair.q_id)
    matches = get_response_json(url)
    print("retrieved %d pairs" % len(matches))

    return matches


def save_matches(host, owner, collection, matches):
    if len(matches) > 0:
        url = "%s/matches" % get_collection_url(host, owner, collection)
        print("submitting PUT %s" % url)

        response = requests.put(url, json=matches)
        response.raise_for_status()


def tile_spec_to_data(tile_spec):
    return tile_spec, tile_spec["layout"]["sectionId"], tile_spec["layout"]["imageRow"], tile_spec["layout"]["imageCol"]


def get_tile_data(host, owner, project, stack, tile_id):
    tile_spec = get_tile_spec(host, owner, project, stack, tile_id)
    return tile_spec_to_data(tile_spec)


def copy_pair(host,
              owner,
              project,
              stack,
              p_tile_id,
              q_tile_id,
              from_collection,
              to_collection,
              min_z,
              max_z_inclusive,
              z_step,
              override_row_col = None):

    p_tile_spec, p_section_id, p_image_row, p_image_col = get_tile_data(host, owner, project, stack, p_tile_id)
    q_tile_spec, q_section_id, q_image_row, q_image_col = get_tile_data(host, owner, project, stack, q_tile_id)

    if p_section_id != q_section_id:
        raise Exception(f'p sectionId {p_section_id} differs from q sectionId {q_section_id}')

    if override_row_col is not None:
        if len(override_row_col) != 4:
            raise Exception(f'override_row_col must be a list of 4 integers')
        p_image_row = override_row_col[0]
        p_image_col = override_row_col[1]
        q_image_row = override_row_col[2]
        q_image_col = override_row_col[3]

    from_id = CanvasIdPair(p_section_id, p_tile_id, q_section_id, q_tile_id)

    from_match_pair = get_pair_matches(host, owner, from_collection, from_id)[0]

    # set all weights to 0.1 to make it easier to find copied matches later
    from_match_pair_weights = from_match_pair["matches"]["w"]
    for i in range(len(from_match_pair_weights)):
        from_match_pair_weights[i] = 0.1

    patched_match_list = []

    for z in range(min_z, max_z_inclusive + 1, z_step):
        patch_p_section_id = None
        patch_p_tile_id = None
        patch_q_section_id = None
        patch_q_tile_id = None
        resolved_tiles = get_resolved_tiles_for_layer(host, owner, project, stack, z)
        tile_id_to_spec = resolved_tiles["tileIdToSpecMap"]
        for tile_id in tile_id_to_spec:
            tile_spec, section_id, image_row, image_col = tile_spec_to_data(tile_id_to_spec[tile_id])
            if image_row == p_image_row and image_col == p_image_col:
                patch_p_section_id = section_id
                patch_p_tile_id = tile_id
            elif image_row == q_image_row and image_col == q_image_col:
                patch_q_section_id = section_id
                patch_q_tile_id = tile_id
            if patch_p_section_id and patch_q_section_id:
                break

        if patch_p_section_id and patch_q_section_id:
            patched_match_list.append(
                {
                    'pGroupId': patch_p_section_id, 'pId': patch_p_tile_id,
                    'qGroupId': patch_q_section_id, 'qId': patch_q_tile_id,
                    'matches': from_match_pair["matches"],
                    'matchCount': from_match_pair["matchCount"]
                }
            )
        else:
            raise Exception(f'could not find patch pair for z {z}')

    save_matches(host, owner, to_collection, patched_match_list)

    print("Done!")


if __name__ == '__main__':
    copy_pair(host='em-services-1.int.janelia.org:8080',
              owner='RENDER_OWNER', project='RENDER_PROJECT', stack='ACQUIRE_TRIMMED_STACK',
              p_tile_id='PID', q_tile_id='QID',
              from_collection='MATCH_COLLECTION', to_collection='MATCH_COLLECTION',
              min_z=0, max_z_inclusive=0, z_step=10)
              # add override_row_col=[]
