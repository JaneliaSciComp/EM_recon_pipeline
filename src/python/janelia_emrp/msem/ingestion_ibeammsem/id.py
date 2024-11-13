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


def get_magc_ids(
    xlog: xr.Dataset, serial_ids: list[int] | np.ndarray
) -> int | None | list[int | None]:
    """Returns the MagC IDs of slabs identified by their serial IDs.

    If a serial_id does not have a magc_id, then returns None.
    """
    n_slabs = get_n_slabs(xlog=xlog, scan=0)
    if np.any(np.asarray(serial_ids) > n_slabs):
        raise ValueError(
            f"a serial_id value provided is greater than the number of slabs {n_slabs}"
        )
    serial_values = xlog[XVar.ID_SERIAL].values
    sorter = np.argsort(serial_values)
    indices = sorter[np.searchsorted(serial_values, serial_ids, sorter=sorter)].tolist()
    return indices


def get_region_ids(
    xlog: xr.Dataset, slab: int, mfovs: list[int] | np.ndarray
) -> list[int | None]:
    """Returns the region ID of MFOVs."""
    _region_ids = xlog[XVar.ID_REGION_LAYOUT].sel(slab=slab, mfov=mfovs).values
    return [
        None if np.isnan(_region_id) or _region_id == -1 else int(_region_id)
        for _region_id in _region_ids
    ]
