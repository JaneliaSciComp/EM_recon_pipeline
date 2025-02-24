import argparse
import logging
import sys
import traceback
from typing import List

from janelia_emrp.render.web_service_request import MatchRequest
from janelia_emrp.root_logger import init_logger


program_name = "delete_match_pairs.py"

logger = logging.getLogger(__name__)


def csv_list(string):
    return string.split(',')


def main(arg_list: List[str]):
    parser = argparse.ArgumentParser(
        description="Delete match pairs of the specified pair_type with weights less than min_keep_weight"
    )
    parser.add_argument(
        "--render_host",
        help="Render web services host (e.g. em-services-1.int.janelia.org)",
        required=True
    )
    parser.add_argument(
        "--match_owner",
        help="Owner for all match collections",
        required=True
    )
    parser.add_argument(
        "--match_collections",
        help="Comma separated match collection names, e.g. s001_m239_match,s002_m395_match",
        type=csv_list,
        required=True
    )
    parser.add_argument(
        "--pair_type",
        help="Type of pairs to delete: within or outside.  "
             "If within, delete pairs where both tiles are in the same group.  "
             "If outside, delete pairs where tiles are in different groups.",
        choices=["within", "outside"],
        required=True
    )
    parser.add_argument(
        "--min_keep_weight",
        help="Only delete pairs where the first match point has a weight less than this value.  "
             "Normal weight is 1.0, sameLayerDerivedMatchWeight is 0.15, "
             "crossLayerDerivedMatchWeight is 0.1, and secondPassDerivedMatchWeight is 0.05.",
        type=float,
        required=True
    )
    parser.add_argument(
        "--explain",
        help="If set, print the number of pairs that would be deleted without actually deleting them",
        action='store_true',
        default=False
    )

    args = parser.parse_args(args=arg_list)

    action = "would delete" if args.explain else "deleted"

    for collection_name in args.match_collections:
        
        match_request = MatchRequest(host=args.render_host,
                                     owner=args.match_owner,
                                     collection=collection_name)

        group_ids = sorted(match_request.get_p_group_ids(), key=float)

        for group_id in group_ids:

            if args.pair_type == "within":
                match_pairs = match_request.get_match_pairs_within_group(group_id=group_id)
            elif args.pair_type == "outside":
                match_pairs = match_request.get_match_pairs_outside_group(group_id=group_id)
            else:
                raise ValueError(f"invalid pair type: {args.pair_type}")

            count = 0
            for pair in match_pairs:
                if pair["matches"]["w"][0] < args.min_keep_weight:
                    if not args.explain:
                        match_request.delete_match_pair(p_group_id=pair["pGroupId"],
                                                        p_id=pair["pId"],
                                                        q_group_id=pair["qGroupId"],
                                                        q_id=pair["qId"])
                    count += 1

            logger.info(f"{action} {count} pairs {args.pair_type} group {group_id}")

    logger.info("Done!")


if __name__ == '__main__':
    # NOTE: to fix module not found errors, export PYTHONPATH="/.../EM_recon_pipeline/src/python"

    # setup logger since this module is the main program (and set render python logging level to DEBUG)
    init_logger(__file__)

    # noinspection PyBroadException
    try:
        main(sys.argv[1:])
        # main(["--render_host", "em-services-1.int.janelia.org:8080",
        #       "--match_owner", "hess_wafers_60_61",
        #       "--match_collections", "w60_s360_r00_d20_gc_match",
        #       "--pair_type", "within",
        #       "--min_keep_weight", "0.20"])
    except Exception as e:
        # ensure exit code is a non-zero value when Exception occurs
        traceback.print_exc()
        sys.exit(1)
