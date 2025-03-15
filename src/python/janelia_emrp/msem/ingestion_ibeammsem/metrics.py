"""Image metrics."""

from __future__ import annotations

from datetime import datetime
from typing import TYPE_CHECKING

import numpy as np
from janelia_emrp.msem.ingestion_ibeammsem.xvar import XVar
from janelia_emrp.msem.ingestion_ibeammsem.xdim import XDim

if TYPE_CHECKING:
    import xarray as xr


def get_raw_average(
    xlog: xr.Dataset, scan: int, slab: int, mfov: int, sfov: int
) -> float:
    """Returns the raw intensity average of all pixels of a SFOV.

    There is no pixel exclusion.
    """
    histogram = (
        xlog[XVar.HISTOGRAM].sel(scan=scan, slab=slab, mfov=mfov, sfov=sfov).values
    )
    return np.sum(histogram * np.arange(256)) / np.sum(histogram)


def get_raw_stdev(
    xlog: xr.Dataset, scan: int, slab: int, mfov: int, sfov: int
) -> float:
    """Returns the raw intensity stdev of all pixels of a SFOV.

    There is no pixel exclusion.
    """
    selection = dict(scan=scan, slab=slab, mfov=mfov, sfov=sfov)
    histogram = xlog[XVar.HISTOGRAM].sel(selection).values
    return np.sqrt(
        np.sum(
            np.square(np.arange(256) - get_raw_average(**(selection | dict(xlog=xlog))))
            * histogram
        )
        / np.sum(histogram)
    )


def get_timestamp(xlog: xr.Dataset, scan: int, slab: int, mfov: int) -> datetime | None:
    """Returns the acquisition timestamp of an MFOV."""
    _timestamp = (
        xlog[XVar.ACQUISITION].sel(scan=scan, slab=slab, mfov=mfov).values.item()
    )
    return None if np.isnan(_timestamp) else datetime.fromtimestamp(_timestamp)


def get_resin_mask(
    xlog: xr.Dataset,
    scan: int,
    slab: int,
    mfov: int,
    n_pixels_low: int = 50**2,
    n_pixels_high: int = 50**2,
    threshold_width: int = 35,
    threshold_sharpness: float = 8,
) -> xr.DataArray:
    r"""Mask of blank resin SFOVs: True for resin, False for tissue.
    
    n_pixels_low/high: to compute the width of the histogram,
        we find the low intensity
        such that n_pixels_low  have a lower  intensity
        we find the high intensity
        such that n_pixels_high have a higher intensity
        
        |       __
        |      /  \
        |     /    \
        |    /     ^\
        |   / ^    ^ \
        +------------------
              ^    ^  
             low  high --> n_pixels_high have a higher intensity than 'high'
              ^     ^ 
              <-----> = width of the histogram
    threshold_width/sharpness:
        mask = (width < threshold_width) * (sharpness < threshold_sharpness)
    """
    sel = dict(scan=scan, slab=slab, mfov=mfov)
    cumulative_histogram = xlog[XVar.HISTOGRAM].sel(sel).cumulative(XDim.BIN).sum()

    n_pixels = cumulative_histogram.isel(sfov=0, bin=-1).values.item()
    threshold_low = n_pixels_low
    threshold_high = n_pixels - n_pixels_high

    low = (cumulative_histogram > threshold_low).idxmax(XDim.BIN)
    high = (cumulative_histogram > threshold_high).idxmax(XDim.BIN)
    width = high - low

    average = xlog[XVar.AVERAGE].sel(sel)
    normalized_sharpness = 100 * xlog[XVar.SHARPNESS].sel(sel) / average

    return (width < threshold_width) * (normalized_sharpness < threshold_sharpness)
