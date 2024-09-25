"""XVar."""

from enum import StrEnum, auto


class XVar(StrEnum):
    """Main variables of the xarray relevant for data ingestion.

    To access a xarray variable:
        xlog[XVar.PATH] == xlog["path"] == xlog.path
    """

    PATH = auto()
    """UNC path of a slab. See methods in path module.

    Note that the root storage has a slab granularity.
    That is, scan=12/slab=10 might be stored in A
        and  scan=12/slab=11 might be stored in B.
    """
    X = auto()
    """X-axis coordinate of the center of the SFOV

    Unit: full-resolution pixel.
    Space: local.
    In the local space, all slabs are aligned
        using the slab-to-slab transforms
        computed with the light microscopy image of the wafer.
        Every SFOV of a given slab
            must be rotated around its center by the same rotation.
            See ROTATION variable.
    """
    Y = auto()
    """Y-axis coordinate of the center of the SFOV

    Unit: full-resolution pixel.
    Space: local. See X above.
    """
    ROTATION_SLAB = auto()
    """Rotation of a slab, in degrees.

    Physical slabs are deposited with MagC onto silicon wafers with random orientations.
    The rotation of slabs is computed with the light microscopy image of the wafer.
    """
    ID_SERIAL = auto()
    """Serial ID of a slab used for the conversion from MagC order to serial order.

    The serial order of the cut slabs collected with MagC is temporarily lost.
    During that period, slabs are assigned a random ID called the MagC ID.
        The MagC ID is not guaranteed to be contiguous.
            That is, an experiment may contain 4 slabs with IDs [0,1,3,4]:
                the ID #2 does not exist.

    The ID_SERIAL variable enables the conversion from the MagC ID to the serial ID.
    See get_serial_ids.
    """
    ID_REGION_LAYOUT = auto()
    """The region ID of MFOVs in a slab.

    The internal dimension hierarchy in the MSEM acquisition code is:
        slab -> region -> MFOV

    All MFOVs within a region have an overlapping neighbor MFOV
        (except for regions with a single MFOV).

    MFOVs belonging to different regions are guaranteed to have no overlap.

    Think of regions as two distant optic lobes in a Drosophila CNS.

    The region dimension has been removed from the xarray dimensions for simplicity.
    """
    MINIMUM = auto()
    """minimum pixel intensity of a SFOV"""
    MAXIMUM = auto()
    """maximum pixel intensity of a SFOV"""
    N_LINE_BLANK = auto()
    """number of blank lines in a SFOV.

    A line is blank all its pixels have intensities below a certain threshold.
    The threshold is station-dependent, typically around 15-20.
    """
    AVERAGE = auto()
    """Average intensity of the non-substrate pixels of an SFOV.

    A pixel is a substrate pixel if its intensity is greater than a threshold.
    The threshold is typically around 140.

    If you need the raw average of all SFOV pixels without any exclusion,
        then use get_raw_average.
    """
    STDEV = auto()
    """Standard deviation of the non-substrate pixels of an SFOV.

    See AVERAGE for definition of substrate pixels.
    Use get_raw_stdev if you need the raw stdev without any exclusion.
    """
    ACQUISITION = auto()
    """POSIX timestamp of the acquisition of a MFOV. See get_timestamp."""
    DISTANCE_ROI = auto()
    """Distance between an SFOV center and the nearest ROI boundary. In microns.

    The distance is negative if the SFOV center is inside  the ROI.
    The distance is positive if the SFOV center is outside the ROI.
    This variable is the discretized distance transform of the ROI.
    This variable can help remove unnecessary, guaranteed non-ROI SFOVs.
    """
    HISTOGRAM = auto()
    """8-bit intensity histogram of all pixels of a SFOV"""

    SUBSTRATE = auto()
    BEAM_BLANK = auto()
    RESIN = auto()

    SHARPNESS = auto()
    SUBSTRATE_SCAN = auto()
    SCALE_AFFINE_X = auto()
    SCALE_AFFINE_Y = auto()
    SHEAR_AFFINE_X = auto()
    SHEAR_AFFINE_Y = auto()
    TRANSLATION_AFFINE_X = auto()
    TRANSLATION_AFFINE_Y = auto()
    ROTATION_SIMILARITY = auto()
    X_REFERENCE = auto()
    Y_REFERENCE = auto()
