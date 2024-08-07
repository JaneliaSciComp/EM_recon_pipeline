import re

from bokeh.io import show
from bokeh.models import Range1d, ColumnDataSource, TapTool, OpenURL
from bokeh.plotting import figure

from janelia_emrp.render.web_service_request import MatchRequest


def main():
    owner = "cellmap"
    project = "jrc_mus_liver_zon_3"
    stack = "v2_acquire"
    match_request = MatchRequest(host="em-services-1.int.janelia.org:8080",
                                 owner=owner,
                                 collection=f"{project}_v1")

    id_pattern = re.compile(r".*_.*_0-0-0\..*")  # "pId": "23-01-24_000020_0-0-0.1.0"

    group_ids = []
    for z in range(13500, 13799):
        group_ids.append(f"{z}.0")

    plot_group_ids = []
    plot_counts = []
    pair_parameters = []

    min_count = 999999
    max_count = 0
    bad_index = -1

    for group_id in group_ids:
        match_pairs = match_request.get_pairs_with_match_counts_for_group(group_id)
        for pair in match_pairs:
            delta_z = int(float(pair["qGroupId"])) - int(float(pair["pGroupId"]))
            if delta_z == 1 and \
                    id_pattern.match(pair["pId"]) and \
                    id_pattern.match(pair["qId"]):

                if pair["matchCount"] < 360:
                    bad_index = 0
                elif -1 < bad_index < 3:
                    bad_index += 1
                else:
                    bad_index = -1

                if bad_index > -1:
                    plot_group_ids.append(pair["pGroupId"])

                    match_count = pair["matchCount"]
                    plot_counts.append(match_count)
                    min_count = min(min_count, match_count)
                    max_count = max(max_count, match_count)

                    pair_parameters.append(f"pId={pair['pId']}&qId={pair['qId']}")

    tap_help = "to view matches"
    base_url = "http://renderer.int.janelia.org:8080/render-ws/view/tile-pair.html"
    render_parameters = f"renderStackOwner={owner}&renderStackProject={project}&renderStack={stack}&renderScale=0.05"
    match_parameters = f"matchOwner={match_request.owner}&matchCollection={match_request.collection}"
    tap_url = f"{base_url}?@pp&{render_parameters}&{match_parameters}"

    tooltips = [("groupId", "@x"), ("matchCount", "@y"), (tap_help, "click point")]

    p = figure(title=f'{match_request.collection} 0-0-0 to 0-0-1 match counts',
               x_axis_label='groupId',
               y_axis_label='matchCount',
               tooltips=tooltips,
               tools='tap,pan,box_zoom,wheel_zoom,save,reset',
               plot_width=2000, plot_height=400,
               y_range=Range1d(min_count, max_count))

    data_source = ColumnDataSource(data=dict(x=plot_group_ids, y=plot_counts, pp=pair_parameters))
    p.circle(source=data_source)

    tap_tool = p.select(type=TapTool)
    tap_tool.callback = OpenURL(url=tap_url)

    show(p)


if __name__ == '__main__':
    main()
