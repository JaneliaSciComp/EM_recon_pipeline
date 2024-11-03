"""Path methods."""

from __future__ import annotations

from pathlib import Path
from typing import TYPE_CHECKING

from constant import N_BEAMS
from xvar import XVar

if TYPE_CHECKING:
    import xarray as xr


def get_slab_path(xlog: xr.Dataset, scan: int, slab: int) -> Path:
    """Gets the slab path.

    Slab paths are stored as UNC paths.

    It is important to use this method
        instead of assuming that the root storage path
        stays the same throughout the wafer experiment.
    """
    return Path(xlog[XVar.PATH].sel(scan=scan, slab=slab).values.item())


def get_mfov_path(slab_path: Path, mfov: int) -> Path:
    """Returns the path of the MFOV given the slab path.

    mfov is 0-indexed.
    """
    return slab_path / "mfovs" / f"mfov_{mfov:04}"


def get_sfov_path(slab_path: Path, mfov: int, sfov: int) -> Path:
    """Returns the path of the SFOV given the slab path.

    mfov is 0-indexed.
    sfov is 0-indexed.
        The microscope numbering is 1-indexed:
            the sfov with ID=0 points to sfov_001.png
    """
    return get_mfov_path(slab_path=slab_path, mfov=mfov) / f"sfov_{sfov+1:03}.png"


def get_thumbnail_path(slab_path: Path, mfov: int, sfov: int) -> Path:
    """Returns the path of the SFOV thumbnail given the slab path."""
    return get_mfov_path(slab_path=slab_path, mfov=mfov) / f"thumbnail_{sfov+1:03}.png"


def get_image_paths(
    slab_path: Path, mfovs: list[int], *, thumbnail: bool = True
) -> list[Path]:
    """Returns SFOV or thumbnail paths of MFOVs in a slab."""
    get_path = get_thumbnail_path if thumbnail else get_sfov_path
    return [
        get_path(slab_path=slab_path, mfov=mfov, sfov=sfov)
        for mfov in mfovs
        for sfov in range(N_BEAMS)
    ]
