from janelia_emrp.render.web_service_request import MatchRequest


def main():
    host = "em-services-1.int.janelia.org:8080"
    owner = "hess_wafer_53"
    match_request = MatchRequest(host=host,
                                 owner=owner,
                                 collection=f"c003_s364_v01_match")

    same_layer_weight = 0.15
    cross_layer_weight = 0.1

    patched_from_same_layer = {}
    patched_from_cross_layers = {}

    group_ids = sorted(match_request.get_p_group_ids(), key=float)

    for group_id in group_ids:

        same_layer_list = []
        cross_layer_list = []

        match_pairs = match_request.get_match_pairs_within_group(group_id=group_id)

        for pair in match_pairs:
            first_match_weight = pair["matches"]["w"][0]
            if first_match_weight == same_layer_weight:
                same_layer_list.append(f'{pair["pId"]}::{pair["qId"]}::{first_match_weight}')
            elif first_match_weight == cross_layer_weight:
                cross_layer_list.append(f'{pair["pId"]}::{pair["qId"]}::{first_match_weight}')

        patched_from_same_layer[group_id] = same_layer_list
        patched_from_cross_layers[group_id] = cross_layer_list

        print(f'found {len(same_layer_list)} same layer and {len(cross_layer_list)} cross layer pairs in group {group_id}')

    for group_id in ["178.0"]:
        print(f"\nsame layer pairs for group {group_id}:\n")
        for p in patched_from_same_layer[group_id]:
            print(f"  {p}")
        print(f"\ncross layer pairs for group {group_id}:\n")
        for p in patched_from_cross_layers[group_id]:
            print(f"  {p}")


if __name__ == '__main__':
    main()
