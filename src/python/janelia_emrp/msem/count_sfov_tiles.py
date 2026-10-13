#!/usr/bin/env python
"""
Counts the SFOV tile images acquired for one or more wafers, using their xlogs.

An MFOV was acquired for a scan and slab when its xlog acquisition timestamp is set.
Each acquired MFOV contributes N_BEAMS (91) SFOV tiles.

By default every acquired tile is counted.  With --review_strategy, the scans that
msem_to_render.py excludes for the entire wafer under that strategy are left out.
Per-mfov review actions within the remaining scans are not applied.

This script only reads and prints; it changes nothing in the xlog or in render.
"""
import argparse
import logging
import sys
import traceback
from pathlib import Path
from typing import List

import xarray

from janelia_emrp.msem.ingestion_ibeammsem.constant import N_BEAMS
from janelia_emrp.msem.ingestion_ibeammsem.review.review import get_excluded_scans, get_review
from janelia_emrp.msem.ingestion_ibeammsem.review.reviewstrategy import REVIEW_STRATEGY
from janelia_emrp.msem.ingestion_ibeammsem.xdim import XDim
from janelia_emrp.msem.ingestion_ibeammsem.xvar import XVar
from janelia_emrp.msem.review_report import build_wafer_xlog_path, WAFER_XLOG_PATH_PATTERN
from janelia_emrp.root_logger import init_logger

program_name = "count_sfov_tiles.py"

logger = logging.getLogger(__name__)


def count_wafer_sfov_tiles(wafer_xlog_path: Path,
                           review_strategy: int | None) -> int:
    """Returns the number of SFOV tiles acquired for the wafer, logging the details."""

    func_name = "count_wafer_sfov_tiles"

    logger.info(f"{func_name}: opening {wafer_xlog_path}")

    if not wafer_xlog_path.exists():
        raise RuntimeError(f"cannot find wafer xlog: {wafer_xlog_path}")

    xlog = xarray.open_zarr(wafer_xlog_path)

    # negative mfov indexes are used internally by the acquisition code, see roi.get_mfovs
    acquired = xlog[XVar.ACQUISITION].sel(scan=slice(0, None), mfov=slice(0, None)).notnull().compute()

    excluded_scans = []
    if review_strategy is not None:
        if XVar.REVIEW not in xlog:
            raise RuntimeError(f"{wafer_xlog_path} has no '{XVar.REVIEW}' variable, "
                               f"so the acquisition review has not been added to this xlog")
        review = get_review(xlog=xlog).load()
        excluded_scans = get_excluded_scans(review=review, review_strategy=review_strategy)
        logger.info(f"{func_name}: review strategy {review_strategy} excludes "
                    f"{len(excluded_scans)} scans: {sorted(excluded_scans)}")
        acquired = acquired.drop_sel({XDim.SCAN: excluded_scans}, errors="ignore")

    mfov_count = int(acquired.sum())
    sfov_count = mfov_count * N_BEAMS
    scan_count = int(acquired.any((XDim.SLAB, XDim.MFOV)).sum())
    slab_count = int(acquired.any((XDim.SCAN, XDim.MFOV)).sum())

    logger.info(f"{func_name}: {wafer_xlog_path.name} has {sfov_count:,} sfov tiles "
                f"({mfov_count:,} mfovs x {N_BEAMS} beams) in {scan_count} scans of {slab_count} slabs")

    return sfov_count


def main(arg_list: List[str]):
    parser = argparse.ArgumentParser(
        description="Count the SFOV tile images acquired for one or more wafers."
    )
    parser.add_argument(
        "--wafer_id",
        help="Wafer IDs, e.g. '60 61', used to derive the standard wafer xlog paths "
             f"({WAFER_XLOG_PATH_PATTERN})",
        type=str,
        nargs='+',
        default=[]
    )
    parser.add_argument(
        "--path_xlog",
        help="Paths of wafer xarrays outside the standard location.  Can be used instead of (or with) wafer_id.",
        nargs='+',
        default=[]
    )
    parser.add_argument(
        "--review_strategy",
        help="Leave out the scans that import excludes for the entire wafer with this review strategy.  "
             "By default, all acquired scans are counted.",
        type=int,
        choices=list(REVIEW_STRATEGY),
    )
    args = parser.parse_args(args=arg_list)

    wafer_xlog_paths = [build_wafer_xlog_path(wafer_id=wafer_id) for wafer_id in args.wafer_id]
    wafer_xlog_paths.extend(Path(path_xlog) for path_xlog in args.path_xlog)

    if len(wafer_xlog_paths) == 0:
        parser.error("specify --wafer_id and/or --path_xlog")

    total_sfov_count = 0
    for wafer_xlog_path in wafer_xlog_paths:
        total_sfov_count += count_wafer_sfov_tiles(wafer_xlog_path=wafer_xlog_path,
                                                   review_strategy=args.review_strategy)

    logger.info(f"main: {total_sfov_count:,} sfov tiles in {len(wafer_xlog_paths)} wafers")


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
