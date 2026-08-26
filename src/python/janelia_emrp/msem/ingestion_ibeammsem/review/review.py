"""Review of IBEAM-MSEM data.

Before ingesting IBEAM-MSEM data,
the IBEAM-MSEM or data acquisition operators
may add a final review to document non-nominal items.

This review is contained in an array in the xlog.

The granularity level of the review array is XDim.MFOV.
Every MFOV has a set of one or more flags that describe the MFOV,
e.g. {Flag.NOMINAL}
or {Flag.DISTORTION_Y_LINEAR_MILD, Flag.OFFSET_SALVAGEABLE}.

The ingestion operators take actions about MFOVs.
The actions are defined in ReviewAction,
e.g., ReviewAction.USE or ReviewAction.NO_Z_DROP.

The mapping from a set of ReviewFlags to ReviewActions is called a review strategy.
It defines what ingestion action to take depending on the flags,
e.g. we ReviewAction.USE MFOVs with the flag {Flag.NOMINAL}
e.g. we ReviewAction.DROP_NO_Z MFOVs with the flags {Flag.TEST, Flag.DISTORTION_Y_LINEAR_MILD}

We can define different strategies.
Strategies are labeled with integers.
E.g., in strategy #0, we are conservative
    and decide to use only ReviewFlag.NOMINAL data
    and drop all the rest.
E.g., in strategy #1, we are less conservative and ingest more edge cases.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

import numpy as np
from janelia_emrp.msem.ingestion_ibeammsem.review.reviewaction import ReviewAction
from janelia_emrp.msem.ingestion_ibeammsem.review.reviewerror import (
    FlagSetWithNoActionError,
)
from janelia_emrp.msem.ingestion_ibeammsem.review.reviewflag import ReviewFlag
from janelia_emrp.msem.ingestion_ibeammsem.review.reviewstrategy import (
    REVIEW_STRATEGY,
    get_flag_sets_with_action,
)
from janelia_emrp.msem.ingestion_ibeammsem.xdim import XDim
from janelia_emrp.msem.ingestion_ibeammsem.xvar import XVar

if TYPE_CHECKING:
    import xarray as xr


def get_review(
    xlog: xr.Dataset,
    scan: int | list[int] | np.ndarray | slice = slice(0, None),
    slab: int | list[int] | np.ndarray | slice = slice(0, None),
    mfov: int | list[int] | np.ndarray | slice = slice(0, None),
) -> xr.DataArray:
    """Returns the review flags of MFOVs.

    Omit a dimension argument to select all items of the dimension.
    E.g. get_review(scan=12)
        returns the review flags of all MFOVs in all slabs in scan 12.
    """
    return xlog[XVar.REVIEW].sel(scan=scan, slab=slab, mfov=mfov)


def get_unique_flag_sets(review: xr.DataArray) -> set[frozenset[ReviewFlag]]:
    """Unique flag sets present in a review array."""
    flag_patterns = np.unique(
        review.stack(all_mfovs=tuple(set(review.dims) - {XDim.REVIEW_FLAG})).transpose(
            "all_mfovs", ...
        ),
        axis=0,
    )
    flag_values = review[XDim.REVIEW_FLAG].values
    return {
        frozenset(ReviewFlag(flag_value) for flag_value in flag_values[flag_pattern])
        for flag_pattern in flag_patterns
    }


def get_review_action(
    review_flag: xr.DataArray, scan: int, slab: int, mfov: int, review_strategy: int
) -> ReviewAction:
    """Gets the review action of an MFOV given a review flag array.

    The review flag array must contain the MFOV of interest.

    Possible use:
    review_flag_slab = get_review(slab=0).load()
    for scan in scans:
        for mfov in mfovs:
            action = get_review_action(review_flag_slab, scan=scan, slab=0, mfov=mfov)
            if action is Action.USE:
                ...
            elif action is Action.WITH_Z_MASK:
                ...
    """
    review_flag_mfov = review_flag.expand_dims(
        tuple({XDim.SCAN, XDim.SLAB, XDim.MFOV} - set(review_flag.dims))
    ).sel(scan=scan, slab=slab, mfov=mfov)
    key_flags = frozenset(
        ReviewFlag(flag_value)
        for flag_value in review_flag_mfov.where(review_flag_mfov)
        .dropna(XDim.REVIEW_FLAG)[XDim.REVIEW_FLAG]
        .values
    )
    if key_flags not in REVIEW_STRATEGY[review_strategy]:
        raise FlagSetWithNoActionError(set(key_flags))
    return REVIEW_STRATEGY[review_strategy][key_flags]


def has_flag(
    review: xr.DataArray, scan: int, slab: int, mfov: int, flag: ReviewFlag
) -> bool:
    """Whether the MFOV has the review flag."""
    return bool(
        review.expand_dims(tuple({XDim.SCAN, XDim.SLAB, XDim.MFOV} - set(review.dims)))
        .sel(scan=scan, slab=slab, mfov=mfov, review_flag=flag)
        .item()
    )


def check_review_strategy(xlog: xr.Dataset, review_strategy: int) -> None:
    """Checks that the review strategy covers all cases in the review array.

    Raises:
        FlagSetWithNoActionError:
            the review array contains flag sets without an action,
            add entries to the review strategy.
    """
    flag_sets_without_action = get_unique_flag_sets(get_review(xlog=xlog)) - set(
        REVIEW_STRATEGY[review_strategy].keys()
    )
    if flag_sets_without_action:
        raise FlagSetWithNoActionError(
            f"add actions to {review_strategy=}"
            f" for these flag sets: {flag_sets_without_action}"
        )


def get_excluded_scans(xlog: xr.Dataset, review_strategy: int) -> list[int]:
    """Scans that we exclude from ingestion.

    A scan is excluded
    if all its MFOVs map to ReviewAction.NO_Z_DROP
    under the review strategy.
    """
    no_z_drop_flag_sets = get_flag_sets_with_action(
        review_strategy=review_strategy, action=ReviewAction.NO_Z_DROP
    )
    review = get_review(xlog=xlog).load()
    return [
        scan.item()
        for scan in review[XDim.SCAN]
        if get_unique_flag_sets(review.sel(scan=scan)) <= no_z_drop_flag_sets
    ]
