#!/usr/bin/env python

import gzip
import json
import sys

import requests
from bokeh.io import output_file
from bokeh.models import Range1d
from bokeh.plotting import figure, show


def load_cross_correlation_file_data(cc_data_path):

    if cc_data_path.endswith('.gz'):
        with gzip.open(cc_data_path, 'r') as cc_data_file:
            json_bytes = cc_data_file.read()
    else:
        with open(cc_data_path, 'r') as cc_data_file:
            json_bytes = cc_data_file.read()

    json_str = json_bytes.decode('utf-8')
    return json.loads(json_str)


def plot_correlations_with_next(title, cc_data_path, plot_width=2400, plot_height=400,
                                output_file_path=None, first_z=1):

    # "layerCount" : 27499,
    # "comparisonRange" : 10,
    # "firstLayerOffset" : 0,
    # "data" : [][]
    merged_cc_result = load_cross_correlation_file_data(cc_data_path)

    z_offset = first_z + merged_cc_result["firstLayerOffset"]
    data = merged_cc_result["data"]

    z_values = []
    cc_with_next = []
    min_cc = 1.0
    max_cc = 0.0
    for i in range(0, len(data) - 1):
        z_values.append(z_offset + i)
        cc = data[i][0]

        if not isinstance(cc, float):
            raise Exception(f'data element {i} in {cc_data_path} contains bad first correlation value {cc}')

        cc_with_next.append(cc)
        min_cc = min(min_cc, cc)
        max_cc = max(max_cc, cc)

    min_cc = min_cc - 0.005
    max_cc = max_cc + 0.005

    if output_file_path:
        output_file(output_file_path)
        print(f'writing plot to {output_file_path}')

    tooltips = [("z", "@x"), ("correlation with next", "@y")]
    p = figure(title=title, x_axis_label='z', y_axis_label='correlation with next layer',
               tooltips=tooltips, plot_width=plot_width, plot_height=plot_height,
               y_range=Range1d(min_cc, max_cc))

    p.circle(z_values, cc_with_next)

    show(p)


def get_stack_first_z(owner, project, stack):
    first_z = 1
    host = 'tem-services.int.janelia.org:8080'
    url = f'http://{host}/render-ws/v1/owner/{owner}/project/{project}/stack/{stack}'
    response = requests.get(url)
    if response.status_code == 200:
        stack_metadata = response.json()
        first_z = stack_metadata["stats"]["stackBounds"]["minZ"]
    else:
        print(f'WARNING: status code {response.status_code} returned for {url}, assuming first z is 1')

    return first_z


def plot_run(owner, project, stack, run):
    first_z = get_stack_first_z(owner, project, stack)
    owner_run_sub_path = f'{owner}/{project}/{stack}/{run}'
    run_dir = f'/nrs/flyem/render/z_corr/{owner_run_sub_path}'
    plot_html_name = 'cc_with_next_plot.html'
    output_file_path = f'{run_dir}/{plot_html_name}'
    plot_url = f'http://renderer-data4.int.janelia.org:8080/z_corr_plots/{owner_run_sub_path}/{plot_html_name}'

    plot_correlations_with_next(title=f'{owner} : {project} : {stack} correlations with next',
                                cc_data_path=f'{run_dir}/merged_cc_data.json.gz',
                                output_file_path=output_file_path,
                                first_z=first_z)
    print(f'view plot at {plot_url}')


if __name__ == '__main__':
    if len(sys.argv) != 5:
        print(f'USAGE: {sys.argv[0]} <owner> <project> <stack> <run>')

    else:
        plot_run(owner=sys.argv[1],
                 project=sys.argv[2],
                 stack=sys.argv[3],
                 run=sys.argv[4])
        
