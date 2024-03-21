from janelia_emrp.render.web_service_request import MatchRequest


def main():
    host = "em-services-1.int.janelia.org:8080"
    owner = "hess_wafer_53b-update-this-and-make-sure-you-really-want-to-run-it"

    owner_match_request = MatchRequest(host=host,
                                       owner=owner,
                                       collection='not_applicable')

    collection_names = [c["collectionId"]["name"] for c in owner_match_request.get_all_match_collections_for_owner()]
    sorted_collection_names = sorted(collection_names)

    for collection_name in sorted_collection_names:
        match_request = MatchRequest(host=host,
                                     owner=owner,
                                     collection=collection_name)
        match_request.delete_collection()

    print("Done!")


if __name__ == '__main__':
    main()
