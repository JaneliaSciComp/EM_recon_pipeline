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

import numpy as np
import xarray as xr
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


def _get_flag_sets(
    review: xr.DataArray,
) -> tuple[list[frozenset[ReviewFlag]], np.ndarray]:
    """Unique flag sets of a review array and their inverse mapping.

    Returns the unique flag sets
    and for every MFOV the index of its flag set into the unique flag sets.
    The MFOVs are ordered by the review dimensions without review_flag.
    """
    review = review.transpose(..., XDim.REVIEW_FLAG)
    used_flags = review.any(tuple(set(review.dims) - {XDim.REVIEW_FLAG}))
    n_used_flags = used_flags.sum().item()

    if n_used_flags > np.iinfo(np.uint64).bits:
        raise NotImplementedError(f"{n_used_flags=} do not fit into uint64 codes")

    review = review.isel({XDim.REVIEW_FLAG: used_flags})
    flag_values = review[XDim.REVIEW_FLAG].values
    # encode flag patterns as integers
    values = review.values.reshape(-1, flag_values.size)
    weights = np.left_shift(np.uint64(1), np.arange(flag_values.size, dtype=np.uint64))
    _, first_indices, inverse = np.unique(
        values @ weights, return_index=True, return_inverse=True
    )
    flag_sets = [
        frozenset(ReviewFlag(flag_value) for flag_value in flag_values[pattern])
        for pattern in values[first_indices]
    ]
    return flag_sets, inverse


def get_unique_flag_sets(review: xr.DataArray) -> set[frozenset[ReviewFlag]]:
    """Unique flag sets present in a review array."""
    flag_sets, _ = _get_flag_sets(review)
    return set(flag_sets)


def get_review_actions(review: xr.DataArray, review_strategy: int) -> xr.DataArray:
    """Review actions of all MFOVs in the review array given a review strategy.

    Returns an array of ReviewAction integer values
    with dimensions scan, slab, and mfov.
    """
    flag_sets, inverse = _get_flag_sets(review)
    actions = np.array(
        [REVIEW_STRATEGY[review_strategy][flag_set] for flag_set in flag_sets]
    )
    template = review.isel({XDim.REVIEW_FLAG: 0}, drop=True)
    return template.copy(data=actions[inverse].reshape(template.shape))


def get_review_action(
    review: xr.DataArray, scan: int, slab: int, mfov: int, review_strategy: int
) -> ReviewAction:
    """Gets the review action of an MFOV given a review array.

    The review array must contain the MFOV of interest.

    Possible use:
    review_slab = get_review(slab=0).load()
    for scan in scans:
        for mfov in mfovs:
            action = get_review_action(review_slab, scan=scan, slab=0, mfov=mfov)
            if action is Action.USE:
                ...
            elif action is Action.WITH_Z_MASK:
                ...
    """
    review_mfov = review.expand_dims(
        tuple({XDim.SCAN, XDim.SLAB, XDim.MFOV} - set(review.dims))
    ).sel(scan=scan, slab=slab, mfov=mfov)
    key_flags = frozenset(
        ReviewFlag(flag_value)
        for flag_value in review_mfov.where(review_mfov)
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


def get_flag_sets_without_action(
    review: xr.DataArray, review_strategy: int
) -> dict[frozenset[ReviewFlag], list[int]]:
    """Flag sets of a review array that the review strategy does not cover.

    Returns a mapping
    from each flag set without an action
    to the sorted scans containing that flag set.
    """
    flag_sets, inverse = _get_flag_sets(review)
    flag_sets_without_action = [
        (index, flag_set)
        for index, flag_set in enumerate(flag_sets)
        if flag_set not in REVIEW_STRATEGY[review_strategy]
    ]
    if not flag_sets_without_action:
        return {}
    template = review.transpose(..., XDim.REVIEW_FLAG).isel(
        {XDim.REVIEW_FLAG: 0}, drop=True
    )
    inverse = inverse.reshape(template.shape)
    scan_axis = template.dims.index(XDim.SCAN)
    other_axes = tuple(axis for axis in range(inverse.ndim) if axis != scan_axis)
    return {
        flag_set: template[XDim.SCAN]
        .values[(inverse == index).any(other_axes)]
        .tolist()
        for index, flag_set in flag_sets_without_action
    }


def check_review_strategy(review: xr.DataArray, review_strategy: int) -> None:
    """Checks that the review strategy covers all cases in the review array.

    Raises:
        FlagSetWithNoActionError:
            the review array contains flag sets without an action,
            add entries to the review strategy.
    """
    flag_sets_without_action = get_flag_sets_without_action(
        review=review, review_strategy=review_strategy
    )
    if flag_sets_without_action:
        raise FlagSetWithNoActionError(
            f"add actions to {review_strategy=}"
            f" for these flag sets and the scans containing them:"
            f" {flag_sets_without_action}"
        )


def get_excluded_scans(review: xr.DataArray, review_strategy: int) -> list[int]:
    """Scans that we exclude from ingestion.

    A scan is excluded
    if all its MFOVs map to ReviewAction.NO_Z_DROP
    under the review strategy.
    The review array must cover all slabs and MFOVs of the wafer.
    """
    no_z_drop_flag_sets = get_flag_sets_with_action(
        review_strategy=review_strategy, action=ReviewAction.NO_Z_DROP
    )
    used_flags = review.any((XDim.SCAN, XDim.SLAB, XDim.MFOV))
    review = review.isel({XDim.REVIEW_FLAG: used_flags})
    used_values = set(review[XDim.REVIEW_FLAG].values.tolist())
    no_z_drop = xr.zeros_like(review.isel({XDim.REVIEW_FLAG: 0}, drop=True))
    for flag_set in no_z_drop_flag_sets:
        # a set requiring a flag that never occurs cannot match any cell
        if not flag_set <= used_values:
            continue
        flag_pattern = review[XDim.REVIEW_FLAG].isin(list(flag_set))
        no_z_drop = no_z_drop | (review == flag_pattern).all(XDim.REVIEW_FLAG)
    excluded = no_z_drop.all((XDim.SLAB, XDim.MFOV))
    return review[XDim.SCAN][excluded].values.tolist()
