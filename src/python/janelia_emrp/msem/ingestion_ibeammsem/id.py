"""ID functions."""

from __future__ import annotations

from typing import TYPE_CHECKING

import numpy as np
from janelia_emrp.msem.ingestion_ibeammsem.roi import get_n_slabs
from janelia_emrp.msem.ingestion_ibeammsem.xdim import XDim
from janelia_emrp.msem.ingestion_ibeammsem.xvar import XVar

if TYPE_CHECKING:
    import xarray as xr


def get_all_magc_ids(xlog: xr.Dataset) -> np.ndarray:
    """Gets all MagC IDs of the wafer.

    Note that MagC IDs
        are not guaranteed to be contiguous, e.g., [0,1,3,5]
        and do not necessarily start at 0.
        Therefore use
            for magc_id in get_all_magc_ids(xlog)
        instead of
            for magc_id in range(len(get_all_magc_ids(xlog)))
    """
    return xlog[XDim.SLAB].values


def get_serial_ids(
    xlog: xr.Dataset, magc_ids: list[int] | np.ndarray
) -> list[int | None]:
    """Returns the serial IDs of slabs identified by their MagC IDs.

    If a magc_id does not have a serial ID, then returns None.
        e.g., a slab does not contain any tissue imaged during the experiment.
    """
    return [
        None if np.isnan(serial_id) else int(serial_id)
        for serial_id in xlog[XVar.ID_SERIAL].sel(slab=magc_ids).load()
    ]


def get_magc_ids(xlog: xr.Dataset, serial_ids: list[int] | np.ndarray) -> list[int]:
    """Returns the MagC IDs of slabs identified by their serial IDs.

    Raises ValueError if a serial_id is strictly negative
        or greater than the number of effective slabs.
    """
    n_slabs = get_n_slabs(xlog=xlog, scan=0)
    for serial_id in serial_ids:
        if serial_id >= n_slabs or serial_id < 0:
            raise ValueError(f"{serial_id} is not a valid serial ID")
    serial_values = xlog[XVar.ID_SERIAL].values
    sorter = np.argsort(serial_values)
    return sorter[np.searchsorted(serial_values, serial_ids, sorter=sorter)].tolist()


def get_region_ids(
    xlog: xr.Dataset, slab: int, mfovs: list[int] | np.ndarray
) -> list[int | None]:
    """Returns the region ID of MFOVs."""
    _region_ids = xlog[XVar.ID_REGION_LAYOUT].sel(slab=slab, mfov=mfovs).values
    return [
        None if np.isnan(_region_id) or _region_id == -1 else int(_region_id)
        for _region_id in _region_ids
    ]
