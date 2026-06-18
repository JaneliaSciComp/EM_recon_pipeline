"""Beam intensity homogenization.

The correction parameters are in the xlog variable XVar.BEAM_HOMOGENIZATION.

The reference level is a single common value for wafers 60,61,
stored in the attributes of the variable XVar.BEAM_HOMOGENIZATION.
See get_reference_level.

We apply beam homogenization with the formula
reference_level + gain * (image - correction_surface)
where surface is the polynomial intensity correction.

For large-scale compute, build each surface once per (scan,slab) and reuse it across mfovs:

    reference_level = get_reference_level(xlog)
    for scan in scans:
        for slab in slabs:
            for beam in beams:
                parameters = HomogenizeParameters.from_xlog(xlog, scan, slab, beam)
                gain = parameters.gain
                surface = create_surface(parameters.get_coefficients(max_degree=5), image_shape)
                for mfov in mfovs:
                    correct_image(sfov, gain, surface, reference_level).astype(uint8)
"""

from __future__ import annotations

from functools import cache
from pathlib import Path
from typing import TYPE_CHECKING

import cv2
import numpy as np
from janelia_emrp.msem.ingestion_ibeammsem.assembly import (
    get_xys_sfov_and_paths,
    open_sfovs,
)
from janelia_emrp.msem.ingestion_ibeammsem.homogenizeparameters import (
    MAX_DEGREE,
    HomogenizeParameters,
)
from janelia_emrp.msem.ingestion_ibeammsem.xvar import XVar

if TYPE_CHECKING:
    import xarray as xr

GRID_NX, GRID_NY = 96, 84
"""size of the interpolation evaluation grid"""
_GRID_X, _GRID_Y = np.meshgrid(
    np.linspace(-1, 1, GRID_NX),
    np.linspace(-1, 1, GRID_NY),
)
"""the interpolation grid"""
DTYPE_IMAGE = np.uint8
IMAGE_MIN = np.iinfo(DTYPE_IMAGE).min
IMAGE_MAX = np.iinfo(DTYPE_IMAGE).max
ID_MAGNETIC_RESIN_MFOV = -1
MAX_OUTPUT_WIDTH = 4000
"""limit the saved MFOV preview to this width in pixels"""


def correct_sfov(
    image: np.ndarray,
    coefficients: np.ndarray,
    gain: float,
    reference_level: float,
) -> np.ndarray | None:
    """Apply the correction to one full-resolution SFOV image, or None.

    This method shows the general flow
    and should not be used as is for large scale compute.
    See the module docstring for the large-scale compute flow.

    Returns None if the beam has no correction.
    """
    if np.isnan(coefficients).all():
        return None
    surface = create_surface(coefficients, image.shape)
    return correct_image(
        image=image,
        gain=gain,
        surface=surface,
        reference_level=reference_level,
    ).astype(DTYPE_IMAGE)


def create_surface(coefficients: np.ndarray, shape: tuple[int, int]) -> np.ndarray:
    """Full-resolution correction surface from coefficients, resized to shape.

    The coefficients are evaluated on the coarse 84x96 grid,
    then resized to shape.
    """
    coarse = (_design_matrix() @ coefficients).reshape(_GRID_X.shape)
    return cv2.resize(
        coarse.astype(np.float32), shape[::-1], interpolation=cv2.INTER_LINEAR
    )


@cache
def _design_matrix() -> np.ndarray:
    """Monomial design matrix on the interpolation grid, evaluated once."""
    return _design(_GRID_X.ravel(), _GRID_Y.ravel(), MAX_DEGREE)


def _design(x: np.ndarray, y: np.ndarray, degree: int) -> np.ndarray:
    """Total-degree monomial design matrix."""
    return np.column_stack(
        [x**i * y ** (d - i) for d in range(degree + 1) for i in range(d + 1)]
    )


def correct_image(
    image: np.ndarray, gain: float, surface: np.ndarray, reference_level: float
) -> np.ndarray:
    """Correct image using the gain, correction surface and reference intensity level."""
    return np.clip(reference_level + gain * (image - surface), IMAGE_MIN, IMAGE_MAX)


def get_reference_level(xlog: xr.Dataset) -> float:
    """The reference intensity level.

    After correction, it is the gray intensity
    of the resin annulus of detected magnetic beads.
    Typically around 70.
    """
    return xlog[XVar.BEAM_HOMOGENIZATION].attrs["b_ref"]


def correct_mfov(
    xlog: xr.Dataset,
    scan: int,
    slab: int,
    mfov: int = ID_MAGNETIC_RESIN_MFOV,
    max_degree: int = MAX_DEGREE,
) -> np.ndarray:
    """Correct every SFOV of one MFOV, roughly assemble them, and save MFOV to disk.

    Sanity check method to quickly correct an MFOV.
    We save in current working directory.
    """
    reference_level = get_reference_level(xlog)
    paths, xys = get_xys_sfov_and_paths(xlog=xlog, scan=scan, slab=slab, mfov=mfov)
    sfovs = open_sfovs(paths)
    xys = (xys - xys.min(axis=0)).round().astype(int)
    image_size = np.flip(sfovs[0].shape)
    assembly = np.zeros(
        np.flip(np.max(xys, axis=0) + image_size).astype(int), dtype=DTYPE_IMAGE
    )
    corners = np.pad(image_size[np.newaxis], ((1, 0), (0, 0))) + xys[:, np.newaxis]
    for sfov in range(len(sfovs)):
        corner, image = corners[sfov], sfovs[sfov]
        parameters = HomogenizeParameters.from_xlog(
            xlog=xlog, scan=scan, slab=slab, sfov=sfov
        )
        corrected = correct_sfov(
            image=image,
            coefficients=parameters.get_coefficients(max_degree),
            gain=parameters.gain,
            reference_level=reference_level,
        )
        assembly[slice(*corner[:, 1]), slice(*corner[:, 0])] = (
            image if corrected is None else corrected
        )
    output = f"correct_mfov_scan{scan}_slab{slab}_mfov{mfov}_deg{max_degree}.png"
    height, width = assembly.shape
    if width > MAX_OUTPUT_WIDTH:
        assembly = cv2.resize(
            assembly,
            (MAX_OUTPUT_WIDTH, round(height * MAX_OUTPUT_WIDTH / width)),
            interpolation=cv2.INTER_AREA,
        )
    cv2.imwrite(output, assembly)
    print(f"saved {Path(output).resolve()}")
    return assembly


r"""
homogenize.py "...\xlog_wafer_61.zarr" 30 351 -1 5
"""
if __name__ == "__main__":
    import sys

    import xarray as xr

    correct_mfov(
        xlog=xr.open_zarr(sys.argv[1], chunks=None),
        scan=int(sys.argv[2]),
        slab=int(sys.argv[3]),
        mfov=int(sys.argv[4]) if len(sys.argv) > 4 else ID_MAGNETIC_RESIN_MFOV,
        max_degree=int(sys.argv[5]) if len(sys.argv) > 5 else MAX_DEGREE,
    )
