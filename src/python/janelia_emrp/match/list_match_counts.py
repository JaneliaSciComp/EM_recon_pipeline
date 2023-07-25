from janelia_emrp.render.web_service_request import MatchRequest


def main():
    host = "em-services-1.int.janelia.org:8080"
    owner = "hess_wafer_53"
    collection_names = [
        "c000_s095_v01_match_agg",
        # "c001_s145_v01_match", "c002_s019_v01_match", "c003_s364_v01_match",
        # "c004_s009_v01_match", "c005_s255_v01_match", "c006_s293_v01_match", "c007_s338_v01_match",
        # "c008_s341_v01_match", "c009_s310_v01_match"
    ]

    max_values = [
        25, 50, 100, 200, 400, 10000
    ]

    collection_name_to_counts = {}

    for collection_name in collection_names:

        same_layer_match_counts = []
        cross_layer_match_counts = []
        for i in range(0, len(max_values)):
            same_layer_match_counts.append(0)
            cross_layer_match_counts.append(0)

        match_request = MatchRequest(host=host,
                                     owner=owner,
                                     collection=collection_name)

        group_ids = sorted(match_request.get_p_group_ids(), key=float)

        for group_id in group_ids:
            match_pairs = match_request.get_pairs_with_match_counts_for_group(group_id)
            for pair in match_pairs:
                match_count = pair["matchCount"]
                if pair["pGroupId"] == pair["qGroupId"]:
                    for i in range(0, len(max_values)):
                        if match_count < max_values[i]:
                            same_layer_match_counts[i] += 1
                            break
                else:
                    for i in range(0, len(max_values)):
                        if match_count < max_values[i]:
                            cross_layer_match_counts[i] += 1
                            break

        collection_name_to_counts[collection_name] = (same_layer_match_counts, cross_layer_match_counts)

    for collection_name in collection_names:
        (same_layer_match_counts, cross_layer_match_counts) = collection_name_to_counts[collection_name]
        
        print(f'\nfor collection {collection_name}:')
        min_val = 1
        for i in range(0, len(max_values)):
            max_val = max_values[i]

            print(f'  number of pairs with {min_val:4d} to {max_val-1:4d} match points '
                  f'in same layer: {same_layer_match_counts[i]:7d}, '
                  f'and across layers: {cross_layer_match_counts[i]:7d}')
            min_val = max_val


if __name__ == '__main__':
    main()
