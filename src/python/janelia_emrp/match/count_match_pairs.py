from janelia_emrp.render.web_service_request import MatchRequest


def main():
    host = "em-services-1.int.janelia.org:8080"
    owner = "hess_wafer_53b"
    match_collection_name_suffix = "_match"
    owner_match_request = MatchRequest(host=host,
                                       owner=owner,
                                       collection='not_applicable')

    collection_summaries = [(c["collectionId"]["name"], c["pairCount"])
                            for c in owner_match_request.get_all_match_collections_for_owner()]

    collection_count = 0
    total_pair_count = 0
    for (name, pair_count) in sorted(collection_summaries):
        if name.endswith(match_collection_name_suffix):
            print(f"{name} has {pair_count:,} tile pairs")
            collection_count += 1
            total_pair_count += pair_count
            
    print(f"found {collection_count} collections with {total_pair_count:,} total tile pairs")


if __name__ == '__main__':
    main()
