#!/usr/bin/env python

import os
import sys

import requests


def get_stack_url(owner, project, stack):
    return "http://em-services-1.int.janelia.org:8080/render-ws/v1/owner/%s/project/%s/stack/%s" % \
           (owner, project, stack)


def get_response_json(url):
    response = requests.get(url)
    if response.status_code != 200:
        raise Exception("request failed for %s\n  status_code: %d\n  text: %s" %
                        (url, response.status_code, response.text))
    return response.json()


def print_batch_parameters(owner, project, stack, seconds_per_layer, minutes_per_job):
    z_values = get_response_json(f'{get_stack_url(owner, project, stack)}/zValues')
    number_of_layers_per_job = minutes_per_job * 60 / seconds_per_layer
    total_batch_count = int( len(z_values) / number_of_layers_per_job ) + 1
    for i in range(0, total_batch_count):
        print(f'--correlationBatch {i+1}:{total_batch_count}')


if __name__ == '__main__':
    if len(sys.argv) < 6:
        print(f'USAGE: {os.path.basename(sys.argv[0])} <owner> <project> <stack> <seconds_per_layer> <minutes_per_job>')
        sys.exit(1)
        # main("/Users/trautmane/Desktop/zcorr/roi.json")
    else:
        print_batch_parameters(sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5]))
