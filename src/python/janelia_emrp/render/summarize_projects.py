#!/usr/bin/env python
import re
from typing import Optional

from requests import HTTPError

from janelia_emrp.render.web_service_request import RenderRequest


tile_id_pattern = re.compile(r"(\d\d-\d\d-\d\d)_.*_0-(\d)-(\d)\..*")  # "tileId": "23-01-24_000020_0-0-0.1.0"


def build_summary(owner: str,
                  project: str,
                  stack: Optional[str],
                  issue_url: str):

    render_request = RenderRequest(host="em-services-1.int.janelia.org:8080",
                                   owner=owner,
                                   project=project)

    stack_ids = render_request.get_stack_ids()
    stack_count = len(stack_ids)

    if stack is None:
        acquire_stacks = sorted([e["stack"] for e in stack_ids
                                 if e["stack"].endswith("acquire") or e["stack"].endswith("acquire_trimmed")])
        stack = acquire_stacks[-1]

    stack_metadata = render_request.get_stack_metadata(stack)
    stack_stats = stack_metadata["stats"]
    max_tile_size = f"{stack_stats['maxTileWidth']}x{stack_stats['maxTileHeight']}"
    tile_count = stack_stats['tileCount']

    first_layer_tile_bounds = render_request.get_tile_bounds_for_z(stack, stack_stats["stackBounds"]["minZ"])
    first_image_date = "?"
    max_row = 0
    max_column = 0
    for tile_bounds in first_layer_tile_bounds:
        search_result = tile_id_pattern.search(tile_bounds["tileId"])
        first_image_date = f"20{search_result.group(1)}"
        row = int(search_result.group(2))
        column = int(search_result.group(3))
        max_row = max(row, max_row)
        max_column = max(column, max_column)

    try:
        restart_tiles = render_request.get_resolved_restart_tiles(stack)
        restart_tile_count = len(restart_tiles['tileIdToSpecMap'])
    except HTTPError:
        restart_tile_count = 0

    patched_tile_ids = render_request.get_tile_ids_with_pattern(stack, "patch")
    patched_tile_count = len(patched_tile_ids)

    summary = f"{project}\t{issue_url}\t{first_image_date}\t{max_row+1}x{max_column+1}\t" \
              f"{tile_count}\t{max_tile_size}\t{restart_tile_count}\t{patched_tile_count}\t{stack_count}"
    return summary, first_image_date


def main():
    github_issues_render_data = [
        {"owner": "flyem", "project": "Z0419_25_Alpha3", "stack": "v3_acquire", "matchCollection": "Z0419_25_Alpha3_v1"},
        {"owner": "cellmap", "project": "aic_desmosome_1", "stack": "v2_acquire", "matchCollection": "aic_desmosome_1_v2"},
        {"owner": "cellmap", "project": "aic_desmosome_2", "stack": "v1_acquire", "matchCollection": "aic_desmosome_2_v2"},
        {"owner": "cellmap", "project": "MouseliverD121520_1", "stack": "v1_acquire", "matchCollection": "MouseliverD121520_1_v1"},
        {"owner": "cellmap", "project": "MousekidneyD121520_3", "stack": "v1_acquire", "matchCollection": "MousekidneyD121520_3_v1"},
        {"ignore": "not a project"},  # 6
        {"owner": "cellmap", "project": "jrc_mus_lung_covid", "stack": "v1_acquire", "matchCollection": "jrc_mus_lung_covid_v1"},
        {"owner": "cellmap", "project": "jrc_mus_lung_ctrl", "stack": "v1_acquire", "matchCollection": "jrc_mus_lung_ctrl_v1"},
        {"owner": "cellmap", "project": "aic_desmosome_3", "stack": "v2_acquire", "alignStack": "v2_acquire_align", "matchCollection": "aic_desmosome_3_v2"},
        {"ignore": "not a project"},  # 10
        {"ignore": "not a project"},  # 11
        {"owner": "Z0421_19", "project": "simulans_08nm_06Mhz", "stack": "v1_acquire", "matchCollection": "simulans_08nm_06Mhz_v1"},
        {"owner": "Z0421_19", "project": "simulans_08nm_10Mhz", "stack": "v1_acquire", "matchCollection": "simulans_08nm_10Mhz_v1"},
        {"owner": "Z0421_19", "project": "simulans_10nm_10Mhz", "stack": "v1_acquire", "matchCollection": "simulans_10nm_10Mhz_v1"},
        {"owner": "Z0721_04C", "project": "female_01_day_08nm", "stack": "v1_acquire", "matchCollection": "female_01_day_08nm_v1"},
        {"owner": "Z0521_31", "project": "yakuba_08nm_06Mhz", "stack": "v1_acquire", "matchCollection": "yakuba_08nm_06Mhz_v1"},
        {"owner": "Z0521_31", "project": "yakuba_08nm_10Mhz", "stack": "v1_acquire", "matchCollection": "yakuba_08nm_10Mhz_v1"},
        {"owner": "Z0521_31", "project": "yakuba_10nm_10Mhz", "stack": "v1_acquire", "matchCollection": "yakuba_10nm_10Mhz_v1"},
        {"owner": "Z0721_13", "project": "female_01_day_red_eye", "stack": "v1_acquire", "matchCollection": "female_01_day_red_eye_v1"},
        {"owner": "flyem", "project": "NIH_J1", "stack": "v1_acquire", "matchCollection": "NIH_J1_v1"},
        {"owner": "cellmap", "project": "NIH20210519_1", "stack": "v1_acquire", "matchCollection": "NIH20210519_1_v1"},
        {"owner": "flyem", "project": "Z1221_05", "stack": "v3_acquire", "matchCollection": "Z1221_05_v1"},
        {"owner": "flyem", "project": "Z1221_19", "stack": "v1_acquire", "matchCollection": "Z1221_19_v1"},
        {"owner": "cellmap", "project": "jrc_cos7_1", "stack": "v1_acquire_part1_trimmed", "matchCollection": "jrc_cos7_1_v1"},
        # {"owner": "cellmap", "project": "jrc_cos7_1", "stack": "v1_acquire_part2", "matchCollection": "jrc_cos7_1_v1"},
        {"ignore": "flyem", "project": "Z0422_17_VNC_1", "stack": "v7_acquire_preview_trimmed", "matchCollection": "Z0422_17_VNC_1_v7"},
        {"owner": "cellmap", "project": "jrc_mus_liv_zon_1", "stack": "v3_acquire", "matchCollection": "jrc_mus_liv_zon_1_v1"},
        {"owner": "cellmap", "project": "jrc_mus_epididymus_1", "stack": "v1_acquire", "matchCollection": "jrc_mus_epididymus_1_v1"},
        {"owner": "cellmap", "project": "jrc_mus_epididymus_2", "stack": "v1_acquire", "matchCollection": "jrc_mus_epididymus_2_v1"},
        {"owner": "reiser", "project": "Z0422_05_Ocellar", "stack": "v9_acquire", "matchCollection": "Z0422_05_Ocellar_v1"},
        {"owner": "cellmap", "project": "jrc_zf_cardiac_1", "stack": "v4_acquire", "matchCollection": "jrc_zf_cardiac_1_v1"},
        {"owner": "cellmap", "project": "jrc_mus_liv_zon_2", "stack": "v3_acquire", "matchCollection": "jrc_mus_liv_zon_2_v1"},
        {"owner": "fibsem", "project": "Z0422_17_VNC_1", "stack": "v6_acquire_trimmed", "matchCollection": "Z0422_17_VNC_1_v2"},
        {"owner": "cellmap", "project": "jrc_mus_liver_2", "stack": "v2_acquire", "matchCollection": "jrc_mus_liver_2_v1"},
        {"owner": "stern", "project": "jrc_22ak351_leaf_3m", "stack": "v2_acquire", "matchCollection": "jrc_22ak351_leaf_3m_v1"},
        {"owner": "stern", "project": "jrc_22ak351_leaf_3r", "stack": "v3_acquire", "matchCollection": "jrc_22ak351_leaf_3r_v1"},
        {"owner": "stern", "project": "jrc_22ak351_leaf_2l", "stack": "v1_acquire", "matchCollection": "jrc_22ak351_leaf_2l_v1"},
        {"owner": "fibsem", "project": "DRAQ5_S1A3_6min", "stack": "v1_acquire_trimmed", "matchCollection": "DRAQ5_S1A3_6min_v1"},
        {"owner": "cellmap", "project": "jrc_mus_kidney_2", "stack": "v2_acquire", "matchCollection": "jrc_mus_kidney_2_v1"},
        {"ignore": "fibsem", "project": "Z0422_17_VNC_1b", "stack": "v1_acquire_trimmed", "matchCollection": "Z0422_17_VNC_1b_v1"},
        {"owner": "cellmap", "project": "jrc_zf_cardiac_2", "stack": "v3_acquire", "matchCollection": "jrc_zf_cardiac_2_v1"},
        {"owner": "cellmap", "project": "jrc_mus_kidney_glomerulus_1", "stack": "v1_acquire", "matchCollection": "jrc_mus_kidney_glomerulus_1_v1"}
    ]

    results = []
    first_image_date_to_result_indexes = {}
    for i in range(60, len(github_issues_render_data)):
        render_data = github_issues_render_data[i]
        if "owner" in render_data:

            issue_url = f"https://github.com/JaneliaSciComp/recon_fibsem/issues/{i+1}"

            summary, first_image_date = build_summary(owner=render_data["owner"],
                                                      project=render_data["project"],
                                                      stack=render_data["stack"],
                                                      issue_url=issue_url)

            if first_image_date in first_image_date_to_result_indexes:
                first_image_date_to_result_indexes[first_image_date].append(i)
            else:
                first_image_date_to_result_indexes[first_image_date] = [i]

            results.append(summary)

        else:
            results.append("")

    flyem_results = []
    owner = "Z0720_07m_BR"
    issue_ids = [
        34, 35, 36, 37, 38,
        45, 46, 41, 42, 40, 39, 29, 28, 27, 31,
        32, 30, 26, 25, 24,  1, 12, 16, 17, 15,
        14, 10,  2, 13, 11,  3,  4,  5,  6, 51
    ]
    for tab_number in range(6, 41):
        project = f"Sec{tab_number:02d}"
        issue_url = f"https://github.com/JaneliaSciComp/Z0720_07m_recon/issues/{issue_ids[tab_number-6]}"
        summary, first_image_date = build_summary(owner=owner,
                                                  project=project,
                                                  stack=None,
                                                  issue_url=issue_url)
        flyem_results.append(f"{owner}: {summary}")

    owner = "Z0720_07m_VNC"
    issue_ids = [
        72, 71, 70, 73, 69,
        68, 67, 66, 64, 63, 62, 61, 60, 59, 58,
        65, 56,  7, 54, 57, 53, 48, 52, 43, 44,
         8,  9, 50, 47, 49, 33
    ]
    for tab_number in range (6, 37):
        project = f"Sec{tab_number:02d}"
        issue_url = f"https://github.com/JaneliaSciComp/Z0720_07m_recon/issues/{issue_ids[tab_number-6]}"
        summary, first_image_date = build_summary(owner=owner,
                                                  project=project,
                                                  stack=None,
                                                  issue_url=issue_url)
        flyem_results.append(f"{owner}: {summary}")

    print(f"\nFlyEM Summary:\n")
    for result in flyem_results:
        print(result)

    print("\nOther Summary:\n")
    for first_image_date in sorted(first_image_date_to_result_indexes.keys()):
        for i in first_image_date_to_result_indexes[first_image_date]:
            print(results[i])


if __name__ == '__main__':
    main()
