import re

from bokeh.io import show
from bokeh.models import Range1d, ColumnDataSource
from bokeh.plotting import figure

from janelia_emrp.render.web_service_request import RenderRequest


def main():
    owner = "fibsem"
    project = "Z0422_17_VNC_1"
    stack = "v6_acquire_trimmed_align"
    min_z = 59300
    max_z = 67392
    render_request = RenderRequest(host="em-services-1.int.janelia.org:8080",
                                   owner=owner,
                                   project=project)

    tile_id_pattern = re.compile(r".*_.*_0-0-0\..*")  # 23-01-15_212316_0-0-0.2200.0

    plot_zs = []
    plot_z_distances = []
    tile_ids = []

    min_distance = 999999
    max_distance = -999999

    for z in range(min_z, max_z + 1):
        resolved_tiles = render_request.get_resolved_tiles_for_z(stack, z)
        for tile_id, tile_spec in resolved_tiles["tileIdToSpecMap"].items():
            if tile_id_pattern.match(tile_id):
                plot_zs.append(z)
                distance_z = tile_spec["layout"]["distanceZ"]
                tile_ids.append(tile_id)
                plot_z_distances.append(distance_z)
                min_distance = min(min_distance, distance_z)
                max_distance = max(max_distance, distance_z)

    tooltips = [("z", "@x"), ("z_distance", "@y"), ("tile_id", "@tile_id")]

    p = figure(title=f'{project} {stack} 0-0-0 z-distances',
               x_axis_label='z',
               y_axis_label='z_distance',
               tooltips=tooltips,
               tools='pan,box_zoom,wheel_zoom,save,reset',
               plot_width=2000, plot_height=400,
               y_range=Range1d(min_distance, max_distance))

    data_source = ColumnDataSource(data=dict(x=plot_zs, y=plot_z_distances, tile_id=tile_ids))
    p.circle(source=data_source)

    show(p)


if __name__ == '__main__':
    main()
