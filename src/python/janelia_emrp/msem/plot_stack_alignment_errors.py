import gzip
import json
import sys

import pandas
from bokeh.io import show, output_file
from bokeh.models import ColumnDataSource, Whisker
from bokeh.plotting import figure
from bokeh.transform import jitter


def plot_stack_errors(stack_errors_json_path: str,
                      stack: str,
                      upper_quantile: float,
                      lower_quantile: float,
                      output_file_parent_directory: str = None):

    print(f"processing {stack_errors_json_path} ...")

    with gzip.open(stack_errors_json_path, "r") if stack_errors_json_path.endswith(".gz") \
            else open(stack_errors_json_path, "r") as error_json_file:
        # [
        #   {
        #     "canvasIdPair" : {
        #       "p" : { "groupId" : "6722.0", "id" : "232_000001_001_20220428_071045.6722.0" },
        #       "q" : { "groupId" : "6722.0", "id" : "232_000001_002_20220428_071045.6722.0" }
        #     },
        #     "value" : 6.964878846627996
        #   },
        #   ...
        # ]
        error_json = json.load(error_json_file)

        # normalized data_frame columns will be:
        #   value, canvasIdPair.p.groupId, canvasIdPair.p.id, canvasIdPair.q.groupId, canvasIdPair.q.id
        data_frame = pandas.json_normalize(error_json)

    group_by_name = "canvasIdPair.p.groupId"
    group_values = list(sorted(data_frame[group_by_name].unique()))
    print(f"loaded {len(data_frame)} errors for {len(group_values)} groups")

    title = f'Tile Pair Alignment Errors: {stack} (quantiles: {lower_quantile:.2f} to {upper_quantile:.2f})'
    tooltips = [("p", "@{canvasIdPair.p.id}"), ("q", "@{canvasIdPair.q.id}"), ("error", "@{value}")]

    plot = figure(title=title,
                  x_axis_label='pGroupId (z)',
                  y_axis_label='Alignment Error (isolated pair to full context distance)',
                  tooltips=tooltips,
                  plot_width=40 * len(group_values),
                  plot_height=800,
                  x_range=group_values,
                  background_fill_color="#efefef")

    plot.xgrid.grid_line_color = None

    grouped_data_frame = data_frame.groupby(group_by_name)

    upper = grouped_data_frame.value.quantile(upper_quantile)
    lower = grouped_data_frame.value.quantile(lower_quantile)

    source = ColumnDataSource(data=dict(base=group_values, upper=upper, lower=lower))

    error = Whisker(base="base",
                    upper="upper",
                    lower="lower",
                    source=source,
                    level="annotation",
                    line_width=2)

    error.upper_head.size = 20
    error.lower_head.size = 20

    plot.add_layout(error)

    plot.circle(jitter(group_by_name, 0.3, range=plot.x_range),
                "value",
                source=data_frame,
                alpha=0.5,
                size=5,
                line_color="white")

    if output_file_parent_directory:
        output_file_path = f'{output_file_parent_directory}/{stack}.alignment_errors.html'
        output_file(output_file_path)
        print(f'writing plot to {output_file_path}')

    show(plot)


if __name__ == '__main__':
    if len(sys.argv) == 6:
        plot_stack_errors(sys.argv[1], sys.argv[2], float(sys.argv[3]), float(sys.argv[4]), sys.argv[5])
    elif len(sys.argv) == 5:
        plot_stack_errors(sys.argv[1], sys.argv[2], float(sys.argv[3]), float(sys.argv[4]))
    else:
        print(f'USAGE: {sys.argv[0]} <error_json_path> <stack> <upper_quantile> <lower_quantile>'
              f' [output_file_parent_directory]')
        sys.exit(1)
        # plot_stack_errors("/Users/trautmane/Desktop/errors2.json.gz",
        #                   "c143_s232_v01_align_fix_run1",
        #                   0.99,
        #                   0.10,
        #                   "/Users/trautmane/Desktop")
