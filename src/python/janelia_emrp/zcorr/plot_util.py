#!/usr/bin/env python

import gzip
import json

import requests


def load_json_file_data(json_path):

    if json_path.endswith('.gz'):
        with gzip.open(json_path, 'r') as data_file:
            json_bytes = data_file.read()
            json_str = json_bytes.decode('utf-8')
    else:
        with open(json_path, 'r') as data_file:
            json_str = data_file.read()

    return json.loads(json_str)


def get_stack_metadata(owner, project, stack):
    host = 'tem-services.int.janelia.org:8080'
    # noinspection HttpUrlsUsage
    url = f'http://{host}/render-ws/v1/owner/{owner}/project/{project}/stack/{stack}'
    response = requests.get(url)
    if response.status_code == 200:
        stack_metadata = response.json()
    else:
        raise Exception(f'status code {response.status_code} returned for {url}')

    return stack_metadata
