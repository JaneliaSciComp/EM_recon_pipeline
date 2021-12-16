#!/usr/bin/env python

import json
import re
import sys


def main(cluster_count_log_file_name):

    parsed_data = []

    # 07:41:54.080 [main] INFO  [org.janelia.render.client.ClusterCountClient] findConnectedClusters:
    # 129751 tile set with first tile 20-10-29_000021_0-0-0.1.0 and last tile 20-12-04_232703_0-0-1.44598.0
    line_pattern = re.compile(r'.*tile set with first tile .*0-0-(\d).(\d+).0 and last tile .*0-0-(\d).(\d+).0')
    with open(cluster_count_log_file_name, 'r') as cluster_count_log_file:
        for line in cluster_count_log_file:
            m = line_pattern.search(line)
            if m:
                min_col = m.group(1)
                min_z = m.group(2)
                max_col = m.group(3)
                max_z = m.group(4)

                parsed_data.append((min_col, max_col, int(min_z), int(max_z)))

    excluded_columns = []
    for (min_col, max_col, min_z, max_z) in sorted(parsed_data):
        excluded_columns.append({
            "columnNumbers": [min_col, max_col], "minZ": int(min_z), "maxZ": int(max_z)
        })

    print(json.dumps(excluded_columns, indent=True))


if __name__ == '__main__':
    main(sys.argv[1])

