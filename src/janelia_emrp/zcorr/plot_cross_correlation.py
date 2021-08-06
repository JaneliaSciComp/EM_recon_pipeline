#!/usr/bin/env python

import gzip
import json
import sys

import requests
from bokeh.io import output_file
from bokeh.models import Range1d, ColumnDataSource, TapTool, OpenURL
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


def get_stack_metadata(owner, project, stack):
    host = 'tem-services.int.janelia.org:8080'
    url = f'http://{host}/render-ws/v1/owner/{owner}/project/{project}/stack/{stack}'
    response = requests.get(url)
    if response.status_code == 200:
        stack_metadata = response.json()
    else:
        raise Exception(f'status code {response.status_code} returned for {url}')

    return stack_metadata


def plot_correlations_with_next(title, cc_data_path, owner, project, stack,
                                plot_width=2400, plot_height=400, output_file_path=None):
    stack_metadata = get_stack_metadata(owner, project, stack)
    bounds = stack_metadata["stats"]["stackBounds"]
    stack_version = stack_metadata["currentVersion"]

    # "layerCount" : 27499,
    # "comparisonRange" : 10,
    # "firstLayerOffset" : 0,
    # "data" : [][]
    merged_cc_result = load_cross_correlation_file_data(cc_data_path)

    z_offset = bounds["minZ"] + merged_cc_result["firstLayerOffset"]
    data = merged_cc_result["data"]

    z_values = []
    zp_values = []
    cc_with_next = []
    min_cc = 1.0
    max_cc = 0.0
    for i in range(0, len(data) - 1):
        z = z_offset + i
        z_values.append(z)
        zp_values.append(z * stack_version["stackResolutionZ"])
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

    tooltips = [("z", "@x"), ("correlation with next", "@y"), ("to view in CATMAID", "click point")]
    p = figure(title=title, x_axis_label='z', y_axis_label='correlation with next layer',
               tooltips=tooltips, tools='tap',
               plot_width=plot_width, plot_height=plot_height,
               y_range=Range1d(min_cc, max_cc))

    data_source = ColumnDataSource(data=dict(x=z_values, y=cc_with_next, zp=zp_values))
    p.circle(source=data_source)

    # open CATMAID when circle glyphs are clicked
    xp = int( bounds["minX"] + (bounds["maxX"] - bounds["minX"]) / 2) * stack_version["stackResolutionX"]
    yp = int( bounds["minY"] + (bounds["maxY"] - bounds["minY"]) / 2) * stack_version["stackResolutionY"]
    catmaid_base_url = 'http://renderer-catmaid.int.janelia.org:8000'
    catmaid_url = f'{catmaid_base_url}/?pid={owner}__{project}&sid0={stack}&tool=navigator&s0=5&xp={xp}&yp={yp}&zp=@zp'

    tap_tool = p.select(type=TapTool)
    tap_tool.callback = OpenURL(url=catmaid_url)

    show(p)


def plot_run(owner, project, stack, run):
    owner_run_sub_path = f'{owner}/{project}/{stack}/{run}'
    run_dir = f'/nrs/flyem/render/z_corr/{owner_run_sub_path}'
    plot_html_name = 'cc_with_next_plot.html'
    output_file_path = f'{run_dir}/{plot_html_name}'
    plot_url = f'http://renderer-data4.int.janelia.org:8080/z_corr_plots/{owner_run_sub_path}/{plot_html_name}'

    plot_correlations_with_next(title=f'{owner} : {project} : {stack} correlations with next',
                                cc_data_path=f'{run_dir}/merged_cc_data.json.gz',
                                owner=owner, project=project, stack=stack,
                                output_file_path=output_file_path)
    print(f'view plot at {plot_url}')


if __name__ == '__main__':
    if len(sys.argv) != 5:
        print(f'USAGE: {sys.argv[0]} <owner> <project> <stack> <run>')

    else:
        plot_run(owner=sys.argv[1],
                 project=sys.argv[2],
                 stack=sys.argv[3],
                 run=sys.argv[4])
        
