"""Image metrics."""

from __future__ import annotations

from datetime import datetime
from typing import TYPE_CHECKING

import numpy as np
from janelia_emrp.msem.ingestion_ibeammsem.xvar import XVar

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
