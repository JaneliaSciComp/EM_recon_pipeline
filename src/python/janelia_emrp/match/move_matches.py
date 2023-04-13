import re

from janelia_emrp.render.web_service_request import MatchRequest


def main():
    host = "em-services-1.int.janelia.org:8080"
    owner = "cellmap"
    from_match_request = MatchRequest(host=host,
                                      owner=owner,
                                      collection=f"jrc_zf_cardiac_2_v1")
    to_match_request = MatchRequest(host=host,
                                    owner=owner,
                                    collection=f"jrc_zf_cardiac_2_mask_100")

    # only move left-right same layer pairs
    p_id_pattern = re.compile(r".*_.*_0-[01]-0\..*")  # "pId": "23-01-24_000020_0-0-0.1.0"
    q_id_pattern = re.compile(r".*_.*_0-[01]-1\..*")  # "qId": "23-01-24_000020_0-0-1.1.0"

    group_ids = sorted(from_match_request.get_p_group_ids(), key=float)

    for group_id in group_ids:

        match_pairs = from_match_request.get_match_pairs_within_group(group_id)

        for pair in match_pairs:

            if pair["pGroupId"] == pair["qGroupId"] and \
                    p_id_pattern.match(pair["pId"]) and \
                    q_id_pattern.match(pair["qId"]):

                to_match_request.save_match_pairs(group_id=pair["pGroupId"],
                                                  match_pairs=[pair])

                from_match_request.delete_match_pair(p_group_id=pair["pGroupId"],
                                                     p_id=pair["pId"],
                                                     q_group_id=pair["qGroupId"],
                                                     q_id=pair["qId"])

    print("Done!")


if __name__ == '__main__':
    main()
