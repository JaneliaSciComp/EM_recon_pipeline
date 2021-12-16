#!/usr/bin/env python

import glob
import os
import sys

from bokeh.io import output_file
from bokeh.models import SingleIntervalTicker
from bokeh.plotting import figure, show


def load_z_coords_file_data(z_coords_path):

    z_values = []
    delta_values = []
    layer_count = 0
    first_z = None
    previous_corrected_z = 0

    with open(z_coords_path, 'r') as z_coords_file:
        for line in z_coords_file:
            layer_count = layer_count + 1
            words = line.split()
            original_z = float(words[0])
            corrected_z = float(words[1])
            if not first_z:
                first_z = original_z
                delta = -1
            else:
                delta = corrected_z - previous_corrected_z
            z_values.append(original_z)
            delta_values.append(delta)
            previous_corrected_z = corrected_z

    return first_z, z_values, delta_values


def normalize_legacy_data(legacy_data_path, first_z, last_z, z_offset):

    legacy_first_z, legacy_z_values, legacy_delta_values = load_z_coords_file_data(legacy_data_path)
    normalized_first_z = None
    normalized_z_values = []
    normalized_delta_values = []
    for i in range(0, len(legacy_z_values)):
        z = legacy_z_values[i] + z_offset
        if first_z <= z <= last_z:
            normalized_z_values.append(z)
            normalized_delta_values.append(legacy_delta_values[i])
            if not normalized_first_z:
                normalized_first_z = z
        elif z > last_z:
            break

    return normalized_first_z, normalized_z_values, normalized_delta_values


def get_line_color(for_index):
    line_colors = ['red', 'blue', 'cyan', 'brown', 'lightgreen', 'yellow']
    return line_colors[for_index % len(line_colors)]


def plot_delta_z(title, data_paths, ignore_margin=35, plot_width=2400, plot_height=1200,
                 legacy_data_path=None, legacy_z_offset=1, output_file_path=None, max_batches_to_plot=None,
                 ticker_interval=None):

    data = []
    z_coords_paths = []
    unmerged_data = False

    for data_path in data_paths:
        if os.path.isdir(data_path):
            z_coords_paths.extend(glob.glob(f'{data_path}/**/Zcoords.txt', recursive=True))
            unmerged_data = True
        else:
            z_coords_paths.append(data_path)

    for z_coords_path in z_coords_paths:
        data.append(load_z_coords_file_data(z_coords_path))

    if output_file_path:
        output_file(output_file_path)
        print(f'writing plot to {output_file_path}')

    tooltips = [("z", "@x"), ("delta", "@y")]
    # , y_range=Range1d(0, 3.9)
    p = figure(title=title, x_axis_label='z', y_axis_label='delta z',
               tooltips=tooltips, plot_width=plot_width, plot_height=plot_height)

    if ticker_interval:
        p.xaxis.ticker = SingleIntervalTicker(interval=ticker_interval)
        p.xaxis.major_label_orientation = "vertical"

    if unmerged_data:
        sorted_data = sorted(data, key=lambda tup: tup[0])
    else:
        sorted_data = data

    if max_batches_to_plot and max_batches_to_plot < len(sorted_data):
        sorted_data = sorted_data[0:max_batches_to_plot]

    if legacy_data_path:
        first_z = sorted_data[0][0]
        last_z_values = sorted_data[-1][1]
        last_z = last_z_values[-1]
        sorted_data.insert(0, normalize_legacy_data(legacy_data_path, first_z, last_z, legacy_z_offset))

    plotted_batch_count = 0
    for (first_z, z_values, delta_values) in sorted_data:
        if ignore_margin == 0:
            stop = len(z_values)
            start = 1
        else:
            stop = len(z_values) - ignore_margin
            start = ignore_margin
        trimmed_z_values = z_values[start:stop]
        trimmed_delta_values = delta_values[start:stop]
        line_color = get_line_color(plotted_batch_count)
        p.circle(trimmed_z_values, trimmed_delta_values,
                 line_color=line_color, fill_color=line_color,
                 legend_label=f'batch {plotted_batch_count}')
        plotted_batch_count = plotted_batch_count + 1

    show(p)


def plot_run(owner, project, stack, run, solve_labels=None):
    owner_run_sub_path = f'{owner}/{project}/{stack}/{run}'
    run_dir = f'/nrs/flyem/render/z_corr/{owner_run_sub_path}'
    plot_html_name = 'delta_z_plot.html'
    output_file_path = f'{run_dir}/{plot_html_name}'
    plot_url = f'http://renderer-data4.int.janelia.org:8080/z_corr_plots/{owner_run_sub_path}/{plot_html_name}'

    data_paths = []
    solve_title = " "
    solve_index = 0
    for data_path in sorted(glob.glob(f'{run_dir}/solve_*/Zcoords.txt')):
        data_paths.append(data_path)
        color = get_line_color(solve_index)
        if solve_labels and solve_index < len(solve_labels):
            label = solve_labels[solve_index]
        else:
            label = os.path.basename(os.path.dirname(data_path))
        solve_title = f'{solve_title} {color}={label},'
        solve_index += 1

    solve_title = solve_title[:-1] # trim trailing comma

    if len(data_paths) > 0:
        plot_delta_z(title=f'{owner} : {project} : {stack} :{solve_title}',
                     data_paths=data_paths,
                     plot_height=1000,
                     ignore_margin=10,
                     output_file_path=output_file_path)
        print(f'view plot at {plot_url}')

    else:
        print(f'ERROR: no solve data to plot in {run_dir}')


if __name__ == '__main__':
    if len(sys.argv) < 4:
        print(f'USAGE: {sys.argv[0]} <owner> <project> <stack> <run> [label ...]')
    else:
        plot_run(owner=sys.argv[1],
                 project=sys.argv[2],
                 stack=sys.argv[3],
                 run=sys.argv[4],
                 solve_labels=[] if len(sys.argv) == 4 else sys.argv[5:])
        
