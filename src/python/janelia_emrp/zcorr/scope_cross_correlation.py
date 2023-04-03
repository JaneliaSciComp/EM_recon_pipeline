#!/usr/bin/env python

import gzip
import json
import statistics
from dataclasses import dataclass

import requests


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
    host = 'em-services-1.int.janelia.org:8080'
    url = f'http://{host}/render-ws/v1/owner/{owner}/project/{project}/stack/{stack}'
    response = requests.get(url)
    if response.status_code == 200:
        stack_metadata = response.json()
    else:
        raise Exception(f'status code {response.status_code} returned for {url}')

    return stack_metadata


@dataclass
class TabStats:
    tab: str
    first_z: int
    last_z: int
    ccMin: float
    ccMax: float
    ccMean: float
    ccMedian: float
    ccStdev: float
    plot_url: str
    first_z_url: str

    def __str__(self):
        cc_min_max = f'ccMin={self.ccMin:.5f}, ccMax={self.ccMax:.5f}'
        cc_other = f'ccMean={self.ccMean:.5f}, ccMedian={self.ccMedian:.5f}, ccStdev={self.ccStdev:.5f}'
        url_str = f'[plot_url]({self.plot_url}), [first_z_url]({self.first_z_url})'
        return f'`  {self.tab}: z {self.first_z:5} to {self.last_z:5}, {cc_min_max}, {cc_other}` {url_str}'


def derive_stats_for_middle_layers(project, stack, run, number_of_layers=5000):
    owner = "Z0720_07m_BR"

    stack_metadata = get_stack_metadata(owner, project, stack)
    bounds = stack_metadata["stats"]["stackBounds"]
    stack_version = stack_metadata["currentVersion"]

    middle_index = int((bounds["maxZ"] - bounds["minZ"]) / 2)
    start_index = middle_index - int(number_of_layers / 2)
    stop_index = start_index + number_of_layers

    cc_data_path = f'/nrs/flyem/render/z_corr/{owner}/{project}/{stack}/{run}/merged_cc_data.json.gz'

    # "layerCount" : 27499, "comparisonRange" : 10, "firstLayerOffset" : 0, "data" : [][]
    merged_cc_result = load_cross_correlation_file_data(cc_data_path)

    z_offset = int(bounds["minZ"] + merged_cc_result["firstLayerOffset"])
    data = merged_cc_result["data"]

    cc_with_next = []
    for i in range(start_index, stop_index):
        cc_with_next.append(data[i][0])

    plot_host = 'http://renderer-data4.int.janelia.org:8080'
    plot_url = f'{plot_host}/z_corr_plots/{owner}/{project}/{stack}/{run}/cc_with_next_plot.html'
    
    xp = int(bounds["minX"] + (bounds["maxX"] - bounds["minX"]) / 2) * stack_version["stackResolutionX"]
    yp = int(bounds["minY"] + (bounds["maxY"] - bounds["minY"]) / 2) * stack_version["stackResolutionY"]
    first_z = z_offset + start_index
    zp = first_z * stack_version["stackResolutionZ"]
    catmaid_base_url = 'http://renderer-catmaid.int.janelia.org:8000'
    catmaid_url = f'{catmaid_base_url}/?pid={owner}__{project}&sid0={stack}&tool=navigator&s0=5&xp={xp}&yp={yp}&zp={zp}'

    return TabStats(project,
                    first_z,
                    first_z + number_of_layers - 1,
                    min(cc_with_next),
                    max(cc_with_next),
                    statistics.mean(cc_with_next),
                    statistics.median(cc_with_next),
                    statistics.stdev(cc_with_next),
                    plot_url,
                    catmaid_url)


@dataclass
class TabInfo:
    tab: str
    scope: str
    stack: str
    run: str


def derive_stats_for_scopes():
    tab_info_list = [
        TabInfo("Sec06", "jeiss5", "v1_acquire_align", "run_20210822_183358_956_z_corr"),
        TabInfo("Sec07", "jeiss4", "v3_acquire_trimmed_align", "run_20210826_141922_272_z_corr"),
        TabInfo("Sec08", "jeiss5", "v1_acquire_trimmed_align", "run_20210825_181213_197_z_corr"),
        TabInfo("Sec09", "jeiss5", "v1_acquire_trimmed_align", "run_20210825_214907_378_z_corr"),
        TabInfo("Sec10", "jeiss8", "v1_acquire_trimmed_align", "run_20210826_084032_695_z_corr"),
        TabInfo("Sec11", "jeiss7", "v2_acquire_trimmed_align", "run_20210917_163530_496_z_corr"),
        TabInfo("Sec12", "jeiss8", "v2_acquire_trimmed_align", "run_20210917_193352_30_z_corr"),
        TabInfo("Sec13", "jeiss2", "v1_acquire_trimmed_align", "run_20210826_192811_645_z_corr"),
        TabInfo("Sec14", "jeiss9", "v4_acquire_trimmed_align", "run_20210827_101623_480_z_corr"),
        TabInfo("Sec15", "jeiss6", "v2_acquire_trimmed_align", "run_20210827_105518_74_z_corr"),
        TabInfo("Sec16", "jeiss3", "v1_acquire_trimmed_align", "run_20210826_130457_426_z_corr"),
        TabInfo("Sec17", "jeiss4", "v2_acquire_trimmed_align", "run_20210718_180319_219_z_corr"),
        TabInfo("Sec18", "jeiss3", "v2_acquire_trimmed_align", "run_20210718_113315_57_z_corr"),
        TabInfo("Sec19", "jeiss9", "v5_acquire_trimmed_align", "run_20210827_103820_391_z_corr"),
        TabInfo("Sec20", "jeiss8", "v5_acquire_trimmed_align", "run_20210806_204721_119_z_corr"),
        TabInfo("Sec21", "jeiss7", "v4_acquire_trimmed_align", "run_20210824_221638_208_z_corr"),
        TabInfo("Sec22", "jeiss6", "v3_acquire_trimmed_align", "run_20210824_221412_250_z_corr"),
        TabInfo("Sec23", "jeiss4", "v4_acquire_trimmed_align_2", "run_20210821_193513_897_z_corr"),
        TabInfo("Sec24", "jeiss7", "v5_acquire_trimmed_align_custom", "run_20210824_191054_172_z_corr"),
        TabInfo("Sec25", "jeiss5", "v5_acquire_trimmed_align", "run_20210708_064502_686_z_corr"),
        TabInfo("Sec26", "jeiss3", "v2_acquire_trimmed_align", "run_20210505_050824_279_z_corr"),
        TabInfo("Sec27", "jeiss6", "v5_acquire_trimmed_align", "run_20210510_205109_45_z_corr"),
        TabInfo("Sec28", "jeiss6", "v3_acquire_trimmed_align", "run_20210506_190404_767_z_corr"),
        TabInfo("Sec29", "jeiss8", "v3_acquire_trimmed_align", "run_20210504_211853_914_z_corr"),
        TabInfo("Sec30", "jeiss9", "v3_acquire_trimmed_align", "run_20210504_195823_63_z_corr"),
        TabInfo("Sec31", "jeiss2", "v2_acquire_trimmed_align", "run_20210501_142501_368_z_corr"),
        TabInfo("Sec32", "jeiss3", "v3_acquire_trimmed_align_5", "run_20210503_125408_415_z_corr"),
        TabInfo("Sec33", "jeiss2", "v1_acquire_trimmed_sp1_adaptive_3", "run_20210430_181157_476_z_corr"),
        TabInfo("Sec34", "jeiss5", "v2_acquire_trimmed_align", "run_20210501_065516_925_z_corr"),
        TabInfo("Sec35", "jeiss2", "v1_acquire_trimmed_align_4", "run_20210502_135915_443_z_corr"),
        TabInfo("Sec36", "jeiss4", "v2_acquire_trimmed_sp3_adaptive", "run_20210501_065258_755_z_corr"),
        TabInfo("Sec37", "jeiss5", "v2_acquire_trimmed_sp1_adaptive", "run_20210421_100627_129_z_corr"),
        TabInfo("Sec38", "jeiss9", "v3_acquire_trimmed_sp1_adaptive", "run_20210424_145621_444_z_corr"),
        TabInfo("Sec39", "jeiss2", "v1_acquire_trimmed_sp1", "run_20210420_224322_622_z_corr"),
        TabInfo("Sec40", "jeiss6", "v1_acquire_trimmed_align", "run_20211008_174347_975_z_corr"),
    ]

    print(f'parsing cc data for:')

    scope_to_tab_stats = {}
    for tab_info in tab_info_list:
        if tab_info.scope not in scope_to_tab_stats:
            scope_to_tab_stats[tab_info.scope] = []

        stats = derive_stats_for_middle_layers(tab_info.tab, tab_info.stack, tab_info.run)
        print(tab_info.tab)
        scope_to_tab_stats[tab_info.scope].append(stats)

    print('\n\nScope Stats:\n')
    
    for scope in sorted(scope_to_tab_stats.keys()):
        print(f'{scope}:')
        for stats in scope_to_tab_stats[scope]:
            print(stats)
        print()


if __name__ == '__main__':
    derive_stats_for_scopes()
        
