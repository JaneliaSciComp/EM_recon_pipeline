"""Constants."""

N_BEAMS = 91
"""the number of beams of the MSEM.

Some microscopes may have 61 beams.
Instead of defining N_BEAMS as a constant, it can be fetched from the xlog:
    N_BEAMS = xlog[XDim.SFOV].size
    range(N_BEAMS) = xlog[XDim.SFOV].values
"""
FACTOR_THUMBNAIL = 4
PIXEL_SIZE = 8 * 1e-3  # micron
