"""ROI functions."""

from __future__ import annotations

from typing import TYPE_CHECKING

import matplotlib.pyplot as plt
import numpy as np
from janelia_emrp.msem.ingestion_ibeammsem.constant import N_BEAMS
from janelia_emrp.msem.ingestion_ibeammsem.metrics import get_resin_mask
from janelia_emrp.msem.ingestion_ibeammsem.xdim import XDim
from janelia_emrp.msem.ingestion_ibeammsem.xvar import XVar

if TYPE_CHECKING:
    import xarray as xr


def get_distance_to_roi(xlog: xr.Dataset, slab: int, mfov: int, sfov: int) -> float:
    """Returns the distance between an SFOV center and the nearest ROI boundary."""
    return xlog[XVar.DISTANCE_ROI].sel(slab=slab, mfov=mfov, sfov=sfov).values.item()


def plot_distance_roi(xlog: xr.Dataset, slab: int, mfov: int | None = None) -> None:
    """Plots the distance between SFOV centers and the nearest ROI boundary."""
    scatter = (
        xlog[[XVar.X_REFERENCE, XVar.Y_REFERENCE, XVar.DISTANCE_ROI]]
        .sel(slab=slab, mfov=mfov or slice(0, None))
        .plot.scatter(
            x=XVar.X_REFERENCE, y=XVar.Y_REFERENCE, hue=XVar.DISTANCE_ROI, cmap="jet"
        )
    )
    scatter.figure.suptitle("Distance transform of the ROI")
    plt.show()


def get_roi_sfovs(
    xlog: xr.Dataset,
    slab: int,
    mfov: int,
    dilation: float = 15,
    exclude_resin: bool = False,
    scan: int | None = None,
) -> list[int]:
    """Returns SFOV IDs of an MFOV that are inside the dilated ROI boundaries.

    The boundary grows outwards with a positive dilation.
    The boundary grows inwards  with a negative dilation.

    Raises:
        RuntimeError: scan is needed if exclude_resin is True
    """
    mask = xlog[XVar.DISTANCE_ROI].sel(slab=slab, mfov=mfov) < dilation

    if exclude_resin:
        if scan is None:
            raise RuntimeError("scan is required if exclude_resin is True")
        mask *= get_resin_mask(xlog=xlog, scan=scan, slab=slab, mfov=mfov).__invert__()

    return mask.where(mask).dropna(XDim.SFOV)[XDim.SFOV].astype(int).values


def plot_tissue_sfovs(
    xlog: xr.Dataset,
    slab: int,
    mfovs: list[int] | np.ndarray | None = None,
    dilation: float = 15,
    marker_size: float | None = None,
    fixed_color: str | None = None,
    off_by: int | None = None,
) -> None:
    """Plots the ROI distance transform of SFOVs that are inside the dilated ROI.

    If mfovs is None, then use all MFOVs of the slab.
    If fixed_color provided, then tissue SFOVs are colorized with the same color.
        If not, then they are colorized with their distance to nearest ROI boundary.

    off_by: if provided, rolls the SFOV IDs by "off_by".
        used for debugging to simulate e.g. off-by-one ID errors
    """
    mfovs = np.asarray(mfovs) if mfovs is not None else None
    xy_variables = dict(x=XVar.X_REFERENCE, y=XVar.Y_REFERENCE)
    distance = xlog[[*xy_variables.values(), XVar.DISTANCE_ROI]].sel(
        slab=slab, mfov=mfovs if mfovs is not None else slice(0, None)
    )
    mask_tissue = distance[XVar.DISTANCE_ROI] < dilation
    if off_by is not None:
        mask_tissue = mask_tissue.roll(shifts={XDim.SFOV: off_by})
    params_plot = dict(s=marker_size, marker="s")
    scatter = distance.where(mask_tissue).plot.scatter(
        **xy_variables,
        hue=XVar.DISTANCE_ROI if fixed_color is None else None,
        c=fixed_color,
        cmap="jet",
        alpha=0.5,
        **params_plot,
    )
    distance.where(np.invert(mask_tissue)).plot.scatter(
        **xy_variables,
        ax=scatter.axes,
        c="none",
        edgecolors="k",
        alpha=0.3,
        **params_plot,
    )
    scatter.axes.set_aspect(1)
    scatter.axes.invert_xaxis()
    scatter.axes.invert_yaxis()
    scatter.figure.suptitle(
        f"Distance transform of tissue SFOVs and excluded non-tissue SFOVs"
        f" | ROI dilation {dilation:.2f} micron"
    )
    plt.show()


def get_effective_slabs(xlog: xr.Dataset, scan: int) -> np.ndarray:
    """Returns the IDs of effective slabs in a scan.

    The number of effective slabs in a scan can be smaller
        than the total number of slabs physically present on a wafer:
        1. some slabs do not have any tissue to be imaged.
            For example, slabs were cut and collected
            before the ROI starts,
            or after the ROI ends.
            These slabs are never part of the effective slabs,
            regardless of the scan.
        2. some slabs have been entirely milled and they are not imaged any more
            That is, starting from a given scan,
                these slabs are not effective slabs any more.
    """
    return (
        xlog[XVar.ACQUISITION]
        .sel(scan=scan, mfov=slice(0, None))
        .sum(XDim.MFOV, min_count=1)
        .dropna(XDim.SLAB)[XDim.SLAB]
        .values.astype(int)
    )


def get_n_slabs(xlog: xr.Dataset, scan: int) -> np.ndarray:
    """Returns the number of effective slabs in a scan. See get_effective_slabs."""
    return (
        xlog[XVar.ACQUISITION]
        .sel(scan=scan, mfov=slice(0, None))
        .sum(XDim.MFOV, min_count=1)
        .dropna(XDim.SLAB)[XDim.SLAB]
        .size
    )


def get_n_mfovs(xlog: xr.Dataset, scan: int) -> int:
    """Returns the total number of MFOVs in a scan.

    We count how many MFOVs have a non-nan acquisition time.
    """
    return (
        xlog[XVar.ACQUISITION].sel(scan=scan, mfov=slice(0, None)).count().values.item()
    )


def get_max_mfovs_per_slab(xlog: xr.Dataset) -> int:
    """Gets the maximum number of MFOVs per slab.

    The xlog is dimensioned along XDim.MFOV to fit the slab with the most MFOVs.
    E.g.: if the largest slab has 24 MFOVs,
        then the positive labels of the XDim.MFOV are [0,...,23].

    Note that MFOVs with strictly negative IDs exist,
        but are internals of the IBEAM-MSEM acquisition
        and are not part of the final dataset.
    """
    return 1 + xlog[XDim.MFOV].max().values.item()


def get_mfovs(xlog: xr.Dataset, slab: int) -> np.ndarray:
    """Returns the effective MFOV IDs of a slab.

    A slab may have 12 MFOVs, and another may have 27 MFOVs.

    The maximum index value of the MFOV dimension of the xarray
        is the number of MFOVs (-1) in the slab with the most MFOVs.
        E.g., if the largest slab has 57 MFOVs,
            then the xarray MFOV indexes go up to 56.

    The xarray contains MFOVs with a negative index value.
        These are used internally in the MSEM acquisition code.
        They are not returned by this function.

    To get the effective MFOV IDs of a slab,
        we exclude the MFOVs that lack metrics such as acquisition timestamp.
    """
    return (
        xlog[XVar.ACQUISITION]
        .sel(scan=0, slab=slab, mfov=slice(0, None))
        .dropna(XDim.MFOV)[XDim.MFOV]
        .values
    )


def get_percentage_tissue(xlog: xr.Dataset, scan: int, dilation: float = 15) -> float:
    """Returns the percentage of all SFOVs that are inside the dilated ROIs.

    It gives an idea of how much process/storage can be avoided
        if we exclude the non-tissue SFOVs.
    """
    return (
        100
        * (xlog[XVar.DISTANCE_ROI].sel(mfov=slice(0, None)) < dilation)
        .sum()
        .values.item()
        / get_n_mfovs(xlog=xlog, scan=scan)
        / N_BEAMS
    )


def plot_histogram_mfovs_per_slab(xlog: xr.Dataset) -> None:
    """Plots the histogram of number of MFOVs per slab."""
    xlog[XVar.X_REFERENCE].sel(mfov=slice(0, None), sfov=0).notnull().sum(
        XDim.MFOV
    ).rename("number of MFOVs per slab").plot.hist(bins=xlog[XDim.MFOV].size)
    plt.show()
