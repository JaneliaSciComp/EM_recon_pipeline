import csv

from bokeh.io import output_file
from bokeh.models import ColumnDataSource, CategoricalColorMapper, BasicTickFormatter, Legend
from bokeh.palettes import d3
from bokeh.plotting import figure, show


def plot_section(section_name,
                 full_image_coordinates_path,
                 output_dir_path=None):

    data = {
        'mFOV': [],
        'sFOV': [],
        'x': [],
        'y': []
    }

    with open(full_image_coordinates_path, 'r') as data_file:
        # 000007\008_000007_055_2021-05-25T2146499297643.bmp      -372876.505     -123997.579     0
        for row in csv.reader(data_file, delimiter="\t"):
            data['mFOV'].append(row[0][11:17])
            data['sFOV'].append(row[0][18:21])
            data['x'].append(int(float(row[1])))
            data['y'].append(int(float(row[2])))

    tooltips = [("mFOV", "@mFOV"), ("sFOV", "@sFOV"), ("x", "@x"), ("y", "@y")]

    source = ColumnDataSource(data=data)

    distinct_groups = list(set(data['mFOV']))
    palette = d3['Category20'][len(distinct_groups)]
    color_map = CategoricalColorMapper(factors=distinct_groups,
                                       palette=palette)

    if output_dir_path:
        safe_section_name = section_name.replace(' ', '_').lower()
        output_file_path = f'{output_dir_path}/{safe_section_name}_tile_location_plot.html'
        output_file(output_file_path)
        print(f'writing plot to {output_file_path}')

    p = figure(title=section_name,
               x_axis_label='x',
               y_axis_label='y',
               tooltips=tooltips,
               plot_height=800,
               plot_width=1000)
    p.y_range.flipped = True
    p.xaxis.formatter = BasicTickFormatter(use_scientific=False)
    p.yaxis.formatter = BasicTickFormatter(use_scientific=False)
    p.add_layout(Legend(title='mFOV'), 'right')
    p.scatter(x='x',
              y='y',
              color={'field': 'mFOV', 'transform': color_map},
              legend_group='mFOV',
              source=source)

    show(p)


if __name__ == '__main__':
    plot_section('Section 4',
                 '/Volumes/hesslab/render/GCIBMSEM/data/Plate_13_20210525_21-38-12/008_s_4/full_image_coordinates.txt',
                 output_dir_path='/Users/trautmane/Desktop')