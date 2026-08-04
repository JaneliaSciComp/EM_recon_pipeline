"""XDim."""

from enum import StrEnum, auto


class XDim(StrEnum):
    """Main dimensions of the xarray relevant for data ingestion."""

    SCAN = auto()
    SLAB = auto()
    MFOV = auto()
    SFOV = auto()
    BIN = auto()
    """histogram bins. [0, ..., 255], inclusive."""
    X_SFOV = auto()
    """pixels of an SFOV along the X axis"""
    Y_SFOV = auto()
    """pixels of an SFOV along the Y axis"""
    HOMOGENIZATION_PARAMETER = auto()
    """26-length axis of BEAM_HOMOGENIZATION.

    Indices 0:20:  the polynomial degree-5 surface coefficients.
    Index 21:      the beam gain.
    Index 22:      the degree-0 flat level.
    Indices 23:25: the degree-1 coefficients.
    """
