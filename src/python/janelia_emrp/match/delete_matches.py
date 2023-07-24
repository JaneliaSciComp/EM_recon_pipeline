from janelia_emrp.render.web_service_request import MatchRequest


def main():
    host = "em-services-1.int.janelia.org:8080"
    owner = "hess_wafer_53"
    match_request = MatchRequest(host=host,
                                 owner=owner,
                                 collection=f"c002_s019_v01_match")
    min_match_weight = 0.2

    group_ids = sorted(match_request.get_p_group_ids(), key=float)

    for group_id in group_ids:

        match_pairs = match_request.get_match_pairs_within_group(group_id=group_id)

        deleted_count = 0
        for pair in match_pairs:
            if pair["matches"]["w"][0] < min_match_weight:
                match_request.delete_match_pair(p_group_id=pair["pGroupId"],
                                                p_id=pair["pId"],
                                                q_group_id=pair["qGroupId"],
                                                q_id=pair["qId"])
                deleted_count += 1

        print(f"deleted {deleted_count} pairs from group {group_id}")

    print("Done!")


if __name__ == '__main__':
    main()
