"""Reports the review data of one or more slabs.

The review array documents non-nominal acquired data at MFOV granularity.
A review strategy maps each set of ReviewFlags to a ReviewAction.
See the janelia_emrp.msem.ingestion_ibeammsem.review package.

This script only reads and prints; it changes nothing in the xlog or in render.
Use it to see what msem_to_render.py --review_strategy would do before importing.
"""
import argparse
import logging
import sys
import traceback
from pathlib import Path
from typing import List

import xarray

from janelia_emrp.msem.ingestion_ibeammsem.assembly import get_effective_scans
from janelia_emrp.msem.ingestion_ibeammsem.id import get_magc_ids, get_serial_ids
from janelia_emrp.msem.ingestion_ibeammsem.review.review import (
    get_excluded_scans, get_review, get_review_action, get_unique_flag_sets
)
from janelia_emrp.msem.ingestion_ibeammsem.review.reviewaction import ReviewAction
from janelia_emrp.msem.ingestion_ibeammsem.review.reviewerror import FlagSetWithNoActionError
from janelia_emrp.msem.ingestion_ibeammsem.review.reviewflag import ReviewFlag
from janelia_emrp.msem.ingestion_ibeammsem.review.reviewstrategy import REVIEW_STRATEGY
from janelia_emrp.msem.ingestion_ibeammsem.roi import get_mfovs
from janelia_emrp.msem.ingestion_ibeammsem.xdim import XDim
from janelia_emrp.msem.ingestion_ibeammsem.xvar import XVar
from janelia_emrp.root_logger import init_logger

program_name = "review_report.py"

logger = logging.getLogger(__name__)

# standard location of the wafer xlogs, e.g. for wafer 60:
#   /groups/hess/hesslab/ibeammsem/system_02/wafers/wafer_60/xlog/xlog_wafer_60.zarr
WAFER_XLOG_PATH_PATTERN = \
    "/groups/hess/hesslab/ibeammsem/system_02/wafers/wafer_{wafer_id}/xlog/xlog_wafer_{wafer_id}.zarr"


# Scans already excluded from import for each wafer.
# These are the known bad scans we account for when running 01_msem_to_render.sh,
# so the review data for them is not a new problem.
# NOTE: keep in sync with the WAFER_EXCLUDED_SCAN_ARG values in
#       src/scripts/msem_60_61/01_msem_to_render.sh
WAFER_EXCLUDED_SCANS: dict[str, List[int]] = {
    "60": [0, 1, 2, 3, 7, 19],
    "61": [0, 1, 2, 3, 17],
}

# number of slabs to process between progress messages
SLAB_PROGRESS_INTERVAL = 5


def build_wafer_xlog_path(wafer_id: str) -> Path:
    """Returns the standard xlog path for a wafer id."""
    return Path(WAFER_XLOG_PATH_PATTERN.format(wafer_id=wafer_id))


def format_flag_set(flag_set: frozenset[ReviewFlag]) -> str:
    """Returns a readable name list for a set of review flags."""
    if len(flag_set) == 0:
        return "{} (no flags set)"
    return "{" + ", ".join(sorted(flag.name for flag in flag_set)) + "}"


def format_mfov_list(mfovs: List[int], max_shown: int = 8) -> str:
    """Returns a readable mfov list, truncated when long."""
    if len(mfovs) > max_shown:
        shown = ", ".join(str(mfov) for mfov in mfovs[:max_shown])
        return f"[{shown}, ... {len(mfovs) - max_shown} more]"
    return "[" + ", ".join(str(mfov) for mfov in mfovs) + "]"


def format_mfov_count(mfovs: List[int],
                      slab_mfov_count: int,
                      with_mfov_list: bool) -> str:
    """Returns a readable mfov count, listing the mfovs only when that adds information.

    The mfov ids are omitted for the nominal USE action and whenever an action
    covers every mfov of the slab, since neither case identifies specific mfovs.
    """
    count_phrase = f"{len(mfovs)} mfov{'s' if len(mfovs) > 1 else ''}"
    if len(mfovs) == slab_mfov_count:
        return f"all {count_phrase}"
    if not with_mfov_list:
        return count_phrase
    return f"{count_phrase} {format_mfov_list(mfovs)}"


def find_undefined_review_flags(xlog: xarray.Dataset) -> List[int]:
    """Returns the review flag values in the xlog that ReviewFlag does not define.

    The acquisition side can add flags to the xlog before ReviewFlag knows about them,
    which makes ReviewFlag(value) raise a ValueError for those flags.
    """
    defined_flag_values = {flag.value for flag in ReviewFlag}
    return [int(flag_value)
            for flag_value in xlog[XVar.REVIEW][XDim.REVIEW_FLAG].values
            if int(flag_value) not in defined_flag_values]


def report_slab(xlog: xarray.Dataset,
                magc_slab: int,
                review_strategy: int,
                show_all_scans: bool,
                exclude_scan_list: List[int],
                problems_only: bool) -> List[int]:
    """Prints the review flags and resulting actions for one slab.

    The scan and mfov dimensions of the xlog are over-dimensioned, so this
    restricts the report to the effective scans and mfovs of the slab.
    Padded items have no flags set and have no action in any strategy.

    Scans in exclude_scan_list are left out of the report entirely since they
    are already excluded from import.

    In problems_only mode, the flag sets and the nominal scans are not printed,
    leaving just the scans that have at least one non-USE action.

    Returns the scans that have at least one non-USE action.
    """
    func_name = "report_slab"

    excluded_scans = set(exclude_scan_list)
    effective_scans = get_effective_scans(xlog=xlog, slab=magc_slab)
    scans = [scan for scan in effective_scans if scan not in excluded_scans]
    mfovs = [int(mfov) for mfov in get_mfovs(xlog=xlog, slab=magc_slab)]

    if len(scans) == 0 or len(mfovs) == 0:
        logger.warning(f"{func_name}: magc slab {magc_slab} has {len(scans)} effective scans "
                       f"to report and {len(mfovs)} mfovs, skipping")
        return []

    review = get_review(xlog=xlog, slab=magc_slab, scan=scans, mfov=mfovs).load()

    serial_slab = get_serial_ids(xlog=xlog, magc_ids=[magc_slab])[0]
    slab_context = f"magc slab {magc_slab} (serial slab {serial_slab})"

    if not problems_only:
        excluded_count = len(effective_scans) - len(scans)
        logger.info(f"{func_name}: {slab_context} has {len(scans)} effective scans to report "
                    f"(first {scans[0]}, last {scans[-1]}, {excluded_count} excluded) "
                    f"and {len(mfovs)} mfovs")

        try:
            for flag_set in sorted(get_unique_flag_sets(review),
                                   key=lambda s: sorted(flag.value for flag in s)):
                logger.info(f"{func_name}: magc slab {magc_slab} contains flag set {format_flag_set(flag_set)}")
        except ValueError as e:
            # the xlog contains a review flag value that ReviewFlag does not define
            logger.warning(f"{func_name}: cannot list the flag sets of magc slab {magc_slab} "
                           f"because the xlog has an undefined review flag ({e})")

    problem_scans: List[int] = []
    nominal_scan_count = 0
    for scan in scans:
        mfovs_for_action: dict[str, List[int]] = {}
        for mfov in mfovs:
            try:
                action_name = get_review_action(review_flag=review,
                                                scan=scan,
                                                slab=magc_slab,
                                                mfov=mfov,
                                                review_strategy=review_strategy).name
            except FlagSetWithNoActionError as e:
                # get_review_action raises with the set of flags that has no action
                undefined_flags = e.args[0] if e.args and isinstance(e.args[0], (set, frozenset)) else None
                action_name = "UNDEFINED_ACTION_FOR_" + (format_flag_set(frozenset(undefined_flags))
                                                         if undefined_flags is not None else str(e))
            except ValueError as e:
                # ReviewFlag(value) raises for review flags the xlog has but this code does not define
                action_name = f"UNDEFINED_REVIEW_FLAG ({e})"
            mfovs_for_action.setdefault(action_name, []).append(mfov)

        is_nominal_scan = list(mfovs_for_action) == [ReviewAction.USE.name]
        if not is_nominal_scan:
            problem_scans.append(scan)

        if is_nominal_scan and (problems_only or not show_all_scans):
            nominal_scan_count += 1
            continue

        action_summary_list = []
        # sort the nominal USE action last so that the actions of interest come first
        for action_name, action_mfovs in sorted(mfovs_for_action.items(),
                                                key=lambda item: (item[0] == ReviewAction.USE.name,
                                                                  item[0])):
            # naming specific mfovs only helps for the non-nominal actions
            mfov_count = format_mfov_count(mfovs=action_mfovs,
                                           slab_mfov_count=len(mfovs),
                                           with_mfov_list=action_name != ReviewAction.USE.name)
            action_summary_list.append(f"{action_name}: {mfov_count}")

        summary = ", ".join(action_summary_list)
        logger.info(f"{func_name}: {slab_context} scan {scan}: {summary}")

    if nominal_scan_count > 0 and not problems_only:
        logger.info(f"{func_name}: magc slab {magc_slab} has {nominal_scan_count} scans with all mfovs USE "
                    f"(not listed above, use --show_all_scans to see them)")

    return problem_scans


def resolve_magc_slabs(xlog: xarray.Dataset,
                       magc_slab_list: List[int],
                       serial_slab_list: List[int]) -> List[int]:
    """Returns the magc ids to report, resolving any serial ids to magc ids.

    Duplicates are dropped, keeping the order in which the slabs were specified.
    """
    func_name = "resolve_magc_slabs"

    resolved_magc_slabs = list(magc_slab_list)

    if len(serial_slab_list) > 0:
        # raises ValueError for serial ids outside the effective slab range
        for serial_slab, magc_slab in zip(serial_slab_list,
                                          get_magc_ids(xlog=xlog, serial_ids=serial_slab_list)):
            logger.info(f"{func_name}: serial slab {serial_slab} has magc id {magc_slab}")
            resolved_magc_slabs.append(magc_slab)

    # dict preserves insertion order, so this drops duplicates without sorting
    return list(dict.fromkeys(resolved_magc_slabs))


def report_review(wafer_xlog_path: Path,
                  magc_slab_list: List[int],
                  serial_slab_list: List[int],
                  review_strategy: int,
                  show_all_scans: bool,
                  report_excluded_scans: bool,
                  exclude_scan_list: List[int],
                  problems_only: bool):

    func_name = "report_review"

    if len(magc_slab_list) == 0 and len(serial_slab_list) == 0 and not report_excluded_scans:
        raise RuntimeError("nothing to report, specify --magc_slab, --serial_slab, "
                           "--serial_slab_range, and/or --report_excluded_scans")

    logger.info(f"{func_name}: opening {wafer_xlog_path}")

    if not wafer_xlog_path.exists():
        raise RuntimeError(f"cannot find wafer xlog: {wafer_xlog_path}")

    xlog = xarray.open_zarr(wafer_xlog_path)

    if XVar.REVIEW not in xlog:
        raise RuntimeError(f"{wafer_xlog_path} has no '{XVar.REVIEW}' variable, "
                           f"so the acquisition review has not been added to this xlog")

    logger.info(f"{func_name}: using review strategy {review_strategy} with "
                f"{len(REVIEW_STRATEGY[review_strategy])} defined flag sets")

    undefined_review_flags = find_undefined_review_flags(xlog=xlog)
    if len(undefined_review_flags) > 0:
        logger.warning(f"{func_name}: the xlog has review flag values {undefined_review_flags} that "
                       f"ReviewFlag does not define (it defines 0 to "
                       f"{max(flag.value for flag in ReviewFlag)}), so mfovs with those flags get "
                       f"reported as UNDEFINED_REVIEW_FLAG.  NOTE: msem_to_render.py fails outright "
                       f"for these, so ReviewFlag needs to be updated before importing.")

    logger.info(f"{func_name}: ignoring the {len(exclude_scan_list)} scans already excluded "
                f"from import: {sorted(exclude_scan_list)}")

    slabs_to_report = resolve_magc_slabs(xlog=xlog,
                                         magc_slab_list=magc_slab_list,
                                         serial_slab_list=serial_slab_list)

    serial_slab_for_magc_slab = dict(zip(slabs_to_report,
                                         get_serial_ids(xlog=xlog, magc_ids=slabs_to_report)))

    problem_scans_for_slab: dict[int, List[int]] = {}
    for slab_index, magc_slab in enumerate(slabs_to_report):

        if slab_index % SLAB_PROGRESS_INTERVAL == 0:
            batch = slabs_to_report[slab_index:slab_index + SLAB_PROGRESS_INTERVAL]
            batch_serial_slabs = [serial_slab_for_magc_slab[slab] for slab in batch
                                  if serial_slab_for_magc_slab[slab] is not None]
            if len(batch_serial_slabs) > 0:
                logger.info(f"{func_name}: reading review data for serial slabs "
                            f"{min(batch_serial_slabs)} to {max(batch_serial_slabs)} "
                            f"({slab_index + len(batch)} of {len(slabs_to_report)} slabs)")
            else:
                logger.info(f"{func_name}: reading review data for magc slabs {batch} "
                            f"({slab_index + len(batch)} of {len(slabs_to_report)} slabs)")

        problem_scans = report_slab(xlog=xlog,
                                    magc_slab=magc_slab,
                                    review_strategy=review_strategy,
                                    show_all_scans=show_all_scans,
                                    exclude_scan_list=exclude_scan_list,
                                    problems_only=problems_only)
        if len(problem_scans) > 0:
            problem_scans_for_slab[magc_slab] = problem_scans

    if len(slabs_to_report) > 0:
        if len(problem_scans_for_slab) == 0:
            logger.info(f"{func_name}: found no scans with non-USE actions in the "
                        f"{len(slabs_to_report)} reported slabs")
        else:
            problem_scan_count = sum(len(scans) for scans in problem_scans_for_slab.values())
            logger.info(f"{func_name}: found {problem_scan_count} scans with non-USE actions in "
                        f"{len(problem_scans_for_slab)} of the {len(slabs_to_report)} reported slabs")
            for magc_slab, problem_scans in problem_scans_for_slab.items():
                serial_slab = serial_slab_for_magc_slab[magc_slab]
                logger.info(f"{func_name}:   magc slab {magc_slab} (serial slab {serial_slab}) "
                            f"scans {problem_scans}")

    if report_excluded_scans:
        # NOTE: this loads the review array for the entire wafer, so it is slow
        logger.info(f"{func_name}: loading review array for the entire wafer to find excluded scans ...")
        excluded_scans = get_excluded_scans(xlog=xlog, review_strategy=review_strategy)
        logger.info(f"{func_name}: review strategy {review_strategy} excludes "
                    f"{len(excluded_scans)} scans for the entire wafer: {sorted(excluded_scans)}")


def main(arg_list: List[str]):
    parser = argparse.ArgumentParser(
        description="Report the acquisition review data and resulting ingestion actions for one or more slabs."
    )
    parser.add_argument(
        "--wafer_id",
        help="Wafer ID, e.g. '60' or 'B13', used to derive the standard wafer xlog path "
             f"({WAFER_XLOG_PATH_PATTERN})",
        type=str,
    )
    parser.add_argument(
        "--path_xlog",
        help="Path of the wafer xarray (e.g. /groups/hess/hesslab/ibeammsem/system_02/wafers/wafer_60/xlog/xlog_wafer_60.zarr).  "
             "Only needed for xlogs outside the standard location, otherwise use wafer_id.",
    )
    parser.add_argument(
        "--magc_slab",
        help="Report review data for slabs with these magc ids (e.g. 399 174)",
        type=int,
        nargs='+',
        default=[]
    )
    parser.add_argument(
        "--serial_slab",
        help="Report review data for slabs with these serial ids (e.g. 296 297), "
             "which get converted to magc ids using the xlog.  Can be used instead of (or with) magc_slab.",
        type=int,
        nargs='+',
        default=[]
    )
    parser.add_argument(
        "--serial_slab_range",
        help="Report review data for all slabs in this inclusive range of serial ids (e.g. 70 89)",
        type=int,
        nargs=2,
        metavar=("FIRST", "LAST"),
    )
    parser.add_argument(
        "--exclude_scan",
        help="Leave these scans out of the report since they are already excluded from import "
             f"(e.g. 0 1 2 3 17).  Defaults to the known scans for the wafer {WAFER_EXCLUDED_SCANS}.  "
             "Specify with no values to report every scan.",
        type=int,
        nargs='*',
        default=None
    )
    parser.add_argument(
        "--problems_only",
        help="Only report the scans that have at least one non-USE action, "
             "to highlight problems not accounted for when importing",
        default=False,
        action="store_true"
    )
    parser.add_argument(
        "--review_strategy",
        help="strategy for edge cases documented in review array.",
        type=int,
        default=0,
        choices=list(REVIEW_STRATEGY),
    )
    parser.add_argument(
        "--show_all_scans",
        help="Include scans whose mfovs are all ReviewAction.USE (they are summarized by default)",
        default=False,
        action="store_true"
    )
    parser.add_argument(
        "--report_excluded_scans",
        help="Also report the scans excluded for the entire wafer (loads the full review array, slow)",
        default=False,
        action="store_true"
    )
    args = parser.parse_args(args=arg_list)

    if args.path_xlog is not None:
        wafer_xlog_path = Path(args.path_xlog)
        if args.wafer_id is not None:
            logger.warning(f"ignoring wafer_id {args.wafer_id} since path_xlog was specified")
    elif args.wafer_id is not None:
        wafer_xlog_path = build_wafer_xlog_path(wafer_id=args.wafer_id)
    else:
        parser.error("specify --wafer_id or --path_xlog")

    serial_slab_list = list(args.serial_slab)
    if args.serial_slab_range is not None:
        first_serial_slab, last_serial_slab = args.serial_slab_range
        if last_serial_slab < first_serial_slab:
            parser.error(f"serial_slab_range {first_serial_slab} {last_serial_slab} is not an increasing range")
        serial_slab_list.extend(range(first_serial_slab, last_serial_slab + 1))

    if args.exclude_scan is not None:
        exclude_scan_list = args.exclude_scan
    elif args.wafer_id in WAFER_EXCLUDED_SCANS:
        exclude_scan_list = WAFER_EXCLUDED_SCANS[args.wafer_id]
    else:
        exclude_scan_list = []
        if args.problems_only:
            wafer_context = "no wafer_id was specified" if args.wafer_id is None \
                else f"wafer {args.wafer_id} has no known excluded scans"
            logger.warning(f"{wafer_context}, so scans already excluded from import may show up "
                           f"as problems, use --exclude_scan to leave them out")

    report_review(wafer_xlog_path=wafer_xlog_path,
                  magc_slab_list=args.magc_slab,
                  serial_slab_list=serial_slab_list,
                  review_strategy=args.review_strategy,
                  show_all_scans=args.show_all_scans,
                  report_excluded_scans=args.report_excluded_scans,
                  exclude_scan_list=exclude_scan_list,
                  problems_only=args.problems_only)


if __name__ == '__main__':
    # NOTE: to fix module not found errors, export PYTHONPATH="/.../EM_recon_pipeline/src/python"

    # setup logger since this module is the main program
    init_logger(__file__)

    # noinspection PyBroadException
    try:
        main(sys.argv[1:])
    except Exception as e:
        # ensure exit code is a non-zero value when Exception occurs
        traceback.print_exc()
        sys.exit(1)
