#!/usr/bin/env python
import sys
from pathlib import Path

from bokeh.io import output_file
from bokeh.models import Range1d, ColumnDataSource, TapTool, OpenURL
from bokeh.plotting import figure, show

from janelia_emrp.zcorr.plot_util import get_stack_metadata, load_json_file_data


def plot_fit_results(title, base_data_path, owner_run_sub_path, owner, project, stack,
                     plot_width=2400, plot_height=400):
    run_dir = f'{base_data_path}/{owner_run_sub_path}'
    fit_data_directory_path = f'{run_dir}/results'

    stack_metadata = get_stack_metadata(owner, project, stack)
    bounds = stack_metadata["stats"]["stackBounds"]
    stack_version = stack_metadata["currentVersion"]

    # "z" : 15000.0,
    # "tileId" : "21-09-28_123114_0-0-0.15000.0",
    # "fitResult" : {
    #    "numInliers" : 669,
    #    "goodnessOfFit" : 0.9907784424770952,
    #    "valueAt0" : -38.07869372583859
    # }

    merged_fit_data = {}
    for json_path in Path(fit_data_directory_path).glob("*.json*"):
        for fit_data in load_json_file_data(str(json_path)):
            merged_fit_data[fit_data["z"]] = fit_data["fitResult"]

    if len(merged_fit_data) == 0:
        raise Exception(f'no data found in {fit_data_directory_path}')

    result_keys = ["numInliers", "goodnessOfFit", "valueAt0"]
    min_value = {}
    max_value = {}

    z_values = []
    zp_values = []
    num_inliers_values = []
    goodness_values = []
    at_zero_values = []
    for z in sorted(merged_fit_data):
        z_values.append(z)
        zp_values.append(z * stack_version["stackResolutionZ"])
        num_inliers_values.append(merged_fit_data[z]["numInliers"])
        goodness_values.append(merged_fit_data[z]["goodnessOfFit"])
        at_zero_values.append(merged_fit_data[z]["valueAt0"])
        for result_key in result_keys:
            result_value = merged_fit_data[z][result_key]
            if result_key in min_value:
                min_value[result_key] = min(min_value[result_key], result_value)
                max_value[result_key] = max(max_value[result_key], result_value)
            else:
                min_value[result_key] = result_value
                max_value[result_key] = result_value

    tip_z = ("z", "@x")
    tip_inliers = ("inliers", "@inliers")
    tip_goodness = ("goodness", "@goodness")
    tip_at_zero = ("at_zero", "@at_zero")
    tip_catmaid = ("to view in CATMAID", "click point")

    figure_data = {
        "goodnessOfFit": (goodness_values, [tip_z, ("goodness", "@y"), tip_inliers, tip_at_zero, tip_catmaid]),
        "numInliers": (num_inliers_values, [tip_z, ("inliers", "@y"), tip_goodness, tip_at_zero, tip_catmaid]),
        "valueAt0": (at_zero_values, [tip_z, ("at_zero", "@y"), tip_goodness, tip_inliers, tip_catmaid]),
    }

    # open CATMAID when circle glyphs are clicked
    xp = int(bounds["minX"] + (bounds["maxX"] - bounds["minX"]) / 2) * stack_version["stackResolutionX"]
    yp = int(bounds["minY"] + (bounds["maxY"] - bounds["minY"]) / 2) * stack_version["stackResolutionY"]
    catmaid_base_url = 'http://renderer-catmaid.int.janelia.org:8000'
    catmaid_url = f'{catmaid_base_url}/?pid={owner}__{project}&sid0={stack}&tool=navigator&s0=5&xp={xp}&yp={yp}&zp=@zp'

    plot_base_url = "http://renderer-data4.int.janelia.org:8080/curve_fit_plots"

    for result_key in figure_data:
        result_values, tooltips = figure_data[result_key]

        plot_html_name = f'curve_fit_{result_key}_plot.html'
        output_file_path = f'{run_dir}/{plot_html_name}'
        output_file(output_file_path)
        print(f'writing plot to {output_file_path}')
        plot_url = f'{plot_base_url}/{owner_run_sub_path}/{plot_html_name}'
        print(f'view plot at {plot_url}')

        p = figure(title=f'{title} {result_key}', x_axis_label='z', y_axis_label=result_key,
                   tooltips=tooltips, tools='tap,pan,box_zoom,wheel_zoom,save,reset',
                   plot_width=plot_width, plot_height=plot_height,
                   y_range=Range1d(min_value[result_key], max_value[result_key]))

        data_source = ColumnDataSource(data=dict(x=z_values, y=result_values,
                                                 zp=zp_values,
                                                 inliers=num_inliers_values,
                                                 goodness=goodness_values,
                                                 at_zero=at_zero_values))
        p.circle(source=data_source)

        tap_tool = p.select(type=TapTool)
        tap_tool.callback = OpenURL(url=catmaid_url)

        show(p)


def plot_run(owner, project, stack, run, base_data_path="/nrs/flyem/render/curve_fit"):
    plot_fit_results(title=f'{owner} : {project} : {stack}',
                     base_data_path=base_data_path,
                     owner_run_sub_path=f'{owner}/{project}/{stack}/{run}',
                     owner=owner, project=project, stack=stack)


if __name__ == '__main__':
    if len(sys.argv) != 5:
        print(f'USAGE: {sys.argv[0]} <owner> <project> <stack> <run>')

    else:
        plot_run(owner=sys.argv[1],
                 project=sys.argv[2],
                 stack=sys.argv[3],
                 run=sys.argv[4])

    # plot_run(owner="Z0720_07m_VNC",
    #          project="Sec19",
    #          stack="v1_acquire_trimmed",
    #          run="run_20220418_223048_954_curve_fit",
    #          base_data_path="/Users/trautmane/Desktop/test-fit")
