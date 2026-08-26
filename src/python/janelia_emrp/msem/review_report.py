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
from janelia_emrp.msem.ingestion_ibeammsem.review.reviewerror import FlagSetWithNoActionError
from janelia_emrp.msem.ingestion_ibeammsem.review.reviewflag import ReviewFlag
from janelia_emrp.msem.ingestion_ibeammsem.review.reviewstrategy import REVIEW_STRATEGY
from janelia_emrp.msem.ingestion_ibeammsem.roi import get_mfovs
from janelia_emrp.msem.ingestion_ibeammsem.xvar import XVar
from janelia_emrp.root_logger import init_logger

program_name = "review_report.py"

logger = logging.getLogger(__name__)

# standard location of the wafer xlogs, e.g. for wafer 60:
#   /groups/hess/hesslab/ibeammsem/system_02/wafers/wafer_60/xlog/xlog_wafer_60.zarr
WAFER_XLOG_PATH_PATTERN = \
    "/groups/hess/hesslab/ibeammsem/system_02/wafers/wafer_{wafer_id}/xlog/xlog_wafer_{wafer_id}.zarr"


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


def report_slab(xlog: xarray.Dataset,
                magc_slab: int,
                review_strategy: int,
                show_all_scans: bool):
    """Prints the review flags and resulting actions for one slab.

    The scan and mfov dimensions of the xlog are over-dimensioned, so this
    restricts the report to the effective scans and mfovs of the slab.
    Padded items have no flags set and have no action in any strategy.
    """
    func_name = "report_slab"

    scans = get_effective_scans(xlog=xlog, slab=magc_slab)
    mfovs = [int(mfov) for mfov in get_mfovs(xlog=xlog, slab=magc_slab)]

    if len(scans) == 0 or len(mfovs) == 0:
        logger.warning(f"{func_name}: magc slab {magc_slab} has {len(scans)} effective scans "
                       f"and {len(mfovs)} mfovs, skipping")
        return

    review = get_review(xlog=xlog, slab=magc_slab, scan=scans, mfov=mfovs).load()

    serial_slab = get_serial_ids(xlog=xlog, magc_ids=[magc_slab])[0]
    logger.info(f"{func_name}: magc slab {magc_slab} (serial slab {serial_slab}) has {len(scans)} "
                f"effective scans (first {scans[0]}, last {scans[-1]}) and {len(mfovs)} mfovs")

    for flag_set in sorted(get_unique_flag_sets(review),
                           key=lambda s: sorted(flag.value for flag in s)):
        logger.info(f"{func_name}: magc slab {magc_slab} contains flag set {format_flag_set(flag_set)}")

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
            mfovs_for_action.setdefault(action_name, []).append(mfov)

        if not show_all_scans and list(mfovs_for_action) == ["USE"]:
            nominal_scan_count += 1
            continue

        summary = ", ".join(f"{action_name}: {len(action_mfovs)} mfovs {format_mfov_list(action_mfovs)}"
                            for action_name, action_mfovs in sorted(mfovs_for_action.items()))
        logger.info(f"{func_name}: magc slab {magc_slab} scan {scan}: {summary}")

    if nominal_scan_count > 0:
        logger.info(f"{func_name}: magc slab {magc_slab} has {nominal_scan_count} scans with all mfovs USE "
                    f"(not listed above, use --show_all_scans to see them)")


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
                  report_excluded_scans: bool):

    func_name = "report_review"

    if len(magc_slab_list) == 0 and len(serial_slab_list) == 0 and not report_excluded_scans:
        raise RuntimeError("nothing to report, specify --magc_slab, --serial_slab, "
                           "and/or --report_excluded_scans")

    logger.info(f"{func_name}: opening {wafer_xlog_path}")

    if not wafer_xlog_path.exists():
        raise RuntimeError(f"cannot find wafer xlog: {wafer_xlog_path}")

    xlog = xarray.open_zarr(wafer_xlog_path)

    if XVar.REVIEW not in xlog:
        raise RuntimeError(f"{wafer_xlog_path} has no '{XVar.REVIEW}' variable, "
                           f"so the acquisition review has not been added to this xlog")

    logger.info(f"{func_name}: using review strategy {review_strategy} with "
                f"{len(REVIEW_STRATEGY[review_strategy])} defined flag sets")

    slabs_to_report = resolve_magc_slabs(xlog=xlog,
                                         magc_slab_list=magc_slab_list,
                                         serial_slab_list=serial_slab_list)

    for magc_slab in slabs_to_report:
        report_slab(xlog=xlog,
                    magc_slab=magc_slab,
                    review_strategy=review_strategy,
                    show_all_scans=show_all_scans)

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

    report_review(wafer_xlog_path=wafer_xlog_path,
                  magc_slab_list=args.magc_slab,
                  serial_slab_list=args.serial_slab,
                  review_strategy=args.review_strategy,
                  show_all_scans=args.show_all_scans,
                  report_excluded_scans=args.report_excluded_scans)


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
