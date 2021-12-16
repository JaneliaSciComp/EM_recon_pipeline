#!/usr/bin/env python

import requests


def get_p_group_ids(collection_url):

    url = f'{collection_url}/pGroupIds'

    print(f'submitting GET {url}')
    response = requests.get(url)
    response.raise_for_status()

    p_group_ids = response.json()
    print(f'retrieved {len(p_group_ids)} pGroupId values')

    return p_group_ids


def get_matches_outside_group(collection_url, group_id):

    url = f'{collection_url}/group/{group_id}/matchesOutsideGroup'

    print(f'submitting GET {url}')
    response = requests.get(url)
    response.raise_for_status()

    matches = response.json()
    print(f'retrieved {len(matches)} pairs for groupId {group_id}')

    return matches


def save_matches(collection_url, group_id, matches):

    if len(matches) > 0:
        url = f'{collection_url}/matches'
        print(f'submitting PUT {url} for {len(matches)} pairs with groupId {group_id}')
        response = requests.put(url, json=matches)
        response.raise_for_status()


def delete_matches_outside_group(collection_url, group_id):

    url = f'{collection_url}/group/{group_id}/matchesOutsideGroup'

    print("submitting DELETE %s" % url)
    response = requests.delete(url)
    response.raise_for_status()


def main():

    host = 'tem-services.int.janelia.org:8080'
    owner = 'Z0720_07m_??'
    from_collection = 'Sec??_v1'
    to_collection = 'Sec??_v1_multi'
    min_z = 0
    max_z = -1

    from_collection_url = f'http://{host}/render-ws/v1/owner/{owner}/matchCollection/{from_collection}'
    to_collection_url = f'http://{host}/render-ws/v1/owner/{owner}/matchCollection/{to_collection}'

    # group_ids = [
    #      "1.0"
    # ]

    # group_ids = get_p_group_ids(from_collection_url)

    group_ids = [f'{z}.0' for z in range(min_z, max_z)]

    for group_id in group_ids:
        matches = get_matches_outside_group(from_collection_url, group_id)
        save_matches(to_collection_url, group_id, matches)
        delete_matches_outside_group(from_collection_url, group_id)

    print("Done!")


if __name__ == '__main__':
    main()

