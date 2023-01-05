#!/usr/bin/env python
import argparse
import json
import urllib.parse

import sys

from bokeh.io import output_file
from bokeh.models import Range1d, ColumnDataSource, TapTool, OpenURL
from bokeh.plotting import figure, show

from janelia_emrp.zcorr.plot_util import get_stack_metadata, load_json_file_data


def plot_correlations_with_next(title, cc_data_path, owner, project, stack,
                                tap_to_ng=True, plot_width=2400, plot_height=400, output_file_path=None):
    stack_metadata = get_stack_metadata(owner, project, stack)
    bounds = stack_metadata["stats"]["stackBounds"]
    stack_version = stack_metadata["currentVersion"]
    res_x = stack_version["stackResolutionX"]
    res_y = stack_version["stackResolutionY"]
    res_z = stack_version["stackResolutionZ"]

    # "layerCount" : 27499,
    # "comparisonRange" : 10,
    # "firstLayerOffset" : 0,
    # "data" : [][]
    merged_cc_result = load_json_file_data(cc_data_path)

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
        zp_values.append(z * res_z)
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

    # open Neuroglancer or CATMAID when circle glyphs are clicked
    center_x = int(bounds["minX"] + (bounds["maxX"] - bounds["minX"]) / 2)
    center_y = int(bounds["minY"] + (bounds["maxY"] - bounds["minY"]) / 2)

    if tap_to_ng:
        tap_help = "to view in Neuroglancer"
        tap_url = build_neuroglancer_tap_url(owner, project, stack, res_x, res_y, res_z, center_x, center_y,
                                             z_token="@x")  # confusing, but z values are x in the plot
    else:
        tap_help = "to view in CATMAID"
        catmaid_base_url = 'http://renderer-catmaid.int.janelia.org:8000'
        xp = center_x * res_x
        yp = center_y * res_y
        tap_url = f'{catmaid_base_url}/?pid={owner}__{project}&sid0={stack}&tool=navigator&s0=5&xp={xp}&yp={yp}&zp=@zp'

    tooltips = [("z", "@x"), ("correlation with next", "@y"), (tap_help, "click point")]
    p = figure(title=title, x_axis_label='z', y_axis_label='correlation with next layer',
               tooltips=tooltips, tools='tap,pan,box_zoom,wheel_zoom,save,reset',
               plot_width=plot_width, plot_height=plot_height,
               y_range=Range1d(min_cc, max_cc))

    data_source = ColumnDataSource(data=dict(x=z_values, y=cc_with_next, zp=zp_values))
    p.circle(source=data_source)

    tap_tool = p.select(type=TapTool)
    tap_tool.callback = OpenURL(url=tap_url)

    show(p)


def build_neuroglancer_tap_url(owner: str,
                               project: str,
                               stack: str,
                               res_x: int,
                               res_y: int,
                               res_z: int,
                               center_x: int,
                               center_y: int,
                               z_token: str) -> str:

    ng_source_url = f'render://http://renderer.int.janelia.org:8080/{owner}/{project}/{stack}'
    layer_name = f'{project} {stack}'
    replace_with_z_token_after_encoding = 0.123456789
    ng_state = {
        "dimensions": {
            "x": [res_x, "nm"],
            "y": [res_y, "nm"],
            "z": [res_z, "nm"]
        },
        "position": [center_x, center_y, replace_with_z_token_after_encoding],
        "crossSectionScale": 32, "projectionScale": 32768,
        "layers": [
            {
                "type": "image",
                "source": {
                    "url": ng_source_url,
                    "subsources": {"default": True, "bounds": True}, "enableDefaultSubsources": False
                },
                "tab": "source",
                "name": layer_name
            }
        ],
        "selectedLayer": {"layer": layer_name},
        "layout": "xy"
    }
    ng_state_json_string = json.dumps(ng_state)
    encoded_ng_state = urllib.parse.quote(ng_state_json_string)
    encoded_ng_state_with_at_z = encoded_ng_state.replace(str(replace_with_z_token_after_encoding), z_token)
    ng_url = f'http://renderer.int.janelia.org:8080/ng/#!{encoded_ng_state_with_at_z}'
    return ng_url


def plot_run(base_dir, owner, project, stack, run):
    owner_run_sub_path = f'{owner}/{project}/{stack}/{run}'
    run_dir = f'{base_dir}/{owner_run_sub_path}'
    plot_html_name = 'cc_with_next_plot.html'
    output_file_path = f'{run_dir}/{plot_html_name}'
    plot_url = f'http://renderer-data4.int.janelia.org:8080/z_corr_plots/{owner_run_sub_path}/{plot_html_name}'

    plot_correlations_with_next(title=f'{owner} : {project} : {stack} correlations with next',
                                cc_data_path=f'{run_dir}/merged_cc_data.json.gz',
                                owner=owner, project=project, stack=stack,
                                output_file_path=output_file_path)
    print(f'view plot at {plot_url}')


def main(arg_list):
    parser = argparse.ArgumentParser(description="Build plot of cross correlation values.")
    parser.add_argument("--owner", required=True)
    parser.add_argument("--project", required=True)
    parser.add_argument("--stack", required=True)
    parser.add_argument("--run", required=True)
    parser.add_argument("--base_dir", default="/nrs/flyem/render/z_corr")

    args = parser.parse_args(arg_list)

    plot_run(base_dir=args.base_dir,
             owner=args.owner,
             project=args.project,
             stack=args.stack,
             run=args.run)


if __name__ == '__main__':
    main(sys.argv[1:])

    # test ng url
    # s = build_neuroglancer_tap_url('cellmap', 'jrc_mus_kidney_2', 'v1_acquire_align', 8, 8, 8, 0, 0, "2013")
    # print(s)
