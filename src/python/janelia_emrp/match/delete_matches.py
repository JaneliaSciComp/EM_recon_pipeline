from janelia_emrp.render.web_service_request import MatchRequest


def main():
    host = "em-services-1.int.janelia.org:8080"
    owner = "hess_wafer_53"
    collection_names = [
        "c000_s095_v01_match", "c001_s145_v01_match", "c002_s019_v01_match", "c003_s364_v01_match",
        "c004_s009_v01_match", "c005_s255_v01_match", "c006_s293_v01_match", "c007_s338_v01_match",
        "c008_s341_v01_match", "c009_s310_v01_match"
    ]

    for collection_name in collection_names:
        
        match_request = MatchRequest(host=host,
                                     owner=owner,
                                     collection=collection_name)
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
