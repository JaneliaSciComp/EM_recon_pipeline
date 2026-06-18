from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING

import numpy as np
from janelia_emrp.msem.ingestion_ibeammsem.xvar import XVar

if TYPE_CHECKING:
    import xarray as xr

MAX_DEGREE = 5
"""maximum interpolation degree of the correction"""
N_COEFFICIENTS = 21
"""number of degree-5 surface coefficients"""
GAIN_INDEX = N_COEFFICIENTS
"""index of the gain"""
DEG0_INDEX = GAIN_INDEX + 1
"""index of the degree-0 parameter"""
DEG1_SLICE = slice(GAIN_INDEX + 2, GAIN_INDEX + 5)
"""indexes of the degree-1 parameters"""


@dataclass
class HomogenizeParameters:
    """Beam homogenization parameters"""

    degree_5_or_less: np.ndarray
    """Coefficients of the polynomial correction.

    The polynomial may be of degree 5, 1, or 0.
    Nominal corrections are of degree 5.
    The detection of artefacts sometimes downgrades the correction to degrees 1 or 0.
    """
    gain: float
    """Gain of the beam"""
    degree_1: np.ndarray
    """Coefficients of the degree 1 polynomial correction."""
    degree_0: float
    """Coefficient of the degree 0 polynomial correction."""

    @classmethod
    def from_xlog(
        cls, xlog: xr.Dataset, scan: int, slab: int, sfov: int
    ) -> HomogenizeParameters:
        """Read HomogenizeParameters from the xlog."""
        parameters = (
            xlog[XVar.BEAM_HOMOGENIZATION].sel(scan=scan, slab=slab, sfov=sfov).values
        )
        return cls(
            degree_5_or_less=parameters[:N_COEFFICIENTS],
            gain=parameters[GAIN_INDEX],
            degree_1=parameters[DEG1_SLICE],
            degree_0=parameters[DEG0_INDEX],
        )

    def get_coefficients(self, max_degree: int = MAX_DEGREE) -> np.ndarray:
        """Polynomial coefficients.

        Returns a vector of length N_COEFFICIENTS with the polynomial coefficients.
        max_degree = 5 -> the degree_5_or_less coefficients
        max_degree = 1 -> the degree_1 coefficients
        max_degree = 0 -> the degree_0 coefficients
        """
        if max_degree >= MAX_DEGREE:
            return self.degree_5_or_less
        if max_degree == 1:
            return np.pad(self.degree_1, (0, N_COEFFICIENTS - self.degree_1.size))
        return np.pad([self.degree_0], (0, N_COEFFICIENTS - 1))
