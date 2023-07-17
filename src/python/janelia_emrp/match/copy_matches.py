from janelia_emrp.render.web_service_request import MatchRequest


def offset_section_id(section_id: str,
                      offset: int) -> str:
    offset_section_value = float(section_id) + offset
    return f"{offset_section_value:3.1f}"


def main():
    host = 'em-services-1.int.janelia.org:8080'
    owner = 'hess_wafer_53'
    from_collections = ['c001_s145_v01_match']
    to_collection = 'c001_s145_v01_match_try2'
    section_offset = 0
    excluded_group_ids = {}  # {"1.0"}
    min_group_id = None  # 59300.0
    max_group_id = None  # 59600.0

    to_match_request = MatchRequest(host, owner, to_collection)

    for from_collection in from_collections:
        from_match_request = MatchRequest(host, owner, from_collection)
        group_ids = from_match_request.get_p_group_ids()

        if min_group_id is not None:
            group_ids = [group_id for group_id in group_ids if float(group_id) >= min_group_id]

        if max_group_id is not None:
            group_ids = [group_id for group_id in group_ids if float(group_id) <= max_group_id]

        i = 0
        for group_id in group_ids:
            i += 1
            print(f"processing group {group_id} ({i} of {len(group_ids)}) ...")

            if group_id in excluded_group_ids:
                print(f"excluding group {group_id}")
                
            else:
                match_pairs = from_match_request.get_match_pairs_for_group(group_id)
                group_id_to_save = group_id

                if section_offset is not None and section_offset > 0:
                    group_id_to_save = offset_section_id(group_id, section_offset)
                    for pair in match_pairs:
                        pair["pGroupId"] = offset_section_id(pair["pGroupId"], section_offset)
                        pair["qGroupId"] = offset_section_id(pair["qGroupId"], section_offset)

                to_match_request.save_match_pairs(group_id_to_save, match_pairs)

    print("Done!")


if __name__ == '__main__':
    main()
