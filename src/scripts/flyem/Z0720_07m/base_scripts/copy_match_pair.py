#!/usr/bin/env python

from dataclasses import dataclass

import requests


@dataclass
class CanvasIdPair:
    p_group_id: str
    p_id: str
    q_group_id: str
    q_id: str


def get_collection_url(host, owner, match_collection):
    return "http://%s/render-ws/v1/owner/%s/matchCollection/%s" % (host, owner, match_collection)


def get_pair_matches(host, owner, collection, pair):

    url = "%s/group/%s/id/%s/matchesWith/%s/id/%s" % \
          (get_collection_url(host, owner, collection), pair.p_group_id, pair.p_id, pair.q_group_id, pair.q_id)

    print("submitting GET %s" % url)
    response = requests.get(url)
    response.raise_for_status()

    matches = response.json()
    print("retrieved %d pairs" % len(matches))

    return matches


def save_matches(host, owner, collection, matches):

    if len(matches) > 0:
        url = "%s/matches" % get_collection_url(host, owner, collection)
        print("submitting PUT %s" % url)

        response = requests.put(url, json=matches)
        response.raise_for_status()


def main():

    host = 'tem-services.int.janelia.org:8080'
    owner = 'Z0720_07m_??'        # TODO: fill in region (BR or VNC)
    from_collection = 'Sec??_v1'  # TODO: fill in section number
    to_collection = from_collection

    from_id = CanvasIdPair('1500.0', '20-12-25_124256_0-0-2.1500.0', '1501.0', '20-12-25_124352_0-0-2.1501.0')  # TODO: set from pair id info
    to_id = CanvasIdPair('1499.0', '20-12-25_124201_0-0-2.1499.0', '1500.0', '20-12-25_124256_0-0-2.1500.0')    # TODO: set to pair id info

    matches = get_pair_matches(host, owner, from_collection, from_id)

    pair = matches[0]

    pair['pGroupId'] = to_id.p_group_id
    pair['pId'] = to_id.p_id
    pair['qGroupId'] = to_id.q_group_id
    pair['qId'] = to_id.q_id

    save_matches(host, owner, to_collection, matches)

    print("Done!")


if __name__ == '__main__':
    main()

