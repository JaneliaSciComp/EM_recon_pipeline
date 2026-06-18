from __future__ import annotations

from enum import IntEnum


class ReviewFlag(IntEnum):
    """Review of the acquired data prior to ingestion.

    The xarray contains a variable REVIEW.
    This enum defines the values of this variable.
    """

    NOMINAL = 0
    """nominal data"""
    NO_FILE = 1
    """the file is missing"""
    OFFSET_SALVAGEABLE = 2
    """data can be salvaged by applying an unusual spatial offset.

    The stage can suffer from lost step events.
    After a lost step event, for all stage move requests to (x,y)
        the stage moves to (x + dx, y + dy) instead of (x,y)
        with the following properties:
            1. either dx or dy is non-zero
            2. (dx,dy) remains constant until
                the lost step event is fixed
                or until another lost step event occurs.
    In most cases, the acquisition pipeline
        1. notices the events
        2. fixes the issue
        3. re-acquires affected items
        so that the end data is not affected.

    In rare cases, some of the 3 items above have failed.

    We classify the symptoms at the MFOV level:
        OFFSET_SALVAGEABLE
        OFFSET_LOSS

    The drawings below show an example slab containing 3 MFOVs.
    The imagery of interest is represented by ABCDEFGHIJKLM.
    The drawing on the left shows the nominal case.
    The drawing on the right shows the problem.

    MFOV #1 is labeled as OFFSET_LOSS: there is no useful data

    MFOVs #2 and #3 are labeled as OFFSET_SALVAGEABLE:
        there is useful data
        an unusually large spatial offset is needed
            to align the data.

    The MFOVs do not cover the sample part "LM": it is a true data loss.

     MFOV#1  MFOV#2  MFOV#3     MFOV#1  MFOV#2  MFOV#3 
    +------++------++------+   +------++------++------+
    |  ABCD||EFGHIJ||KLM   |-->|      || ABCDE||FGHIJK|LM
    |      ||      ||      |   |      ||      ||      |
    +------++------++------+   +------++------++------+
    """
    OFFSET_LOSS = 3
    """There is no data to salvage from this item.

    See OFFSET_SALVAGEABLE.
    OFFSET_LOSS corresponds to MFOV#1 in the example drawing.
    """
    DISTORTION_Y_LINEAR_MILD = 4
    """data has a mild y-axis linear distortion.

    Due to a failure of the scan amplifier of the microscope.
    Applying linear transforms should fix the distortion.
    There might be some true lost data between SFOVs
        because they do not overlap.
    """
    DISTORTION_Y_LINEAR_SEVERE = 5
    """data has a severe y-axis linear distortion."""
    DISTORTION_Y_LINEAR_SEVERE_LATER_RETAKEN = 6
    """data has a severe y-axis linear distortion and has been retaken later."""
    REDEPOSITED_MATERIAL = 7
    """image of redeposited material which is not of interest.

    The electron irradiation step of IBEAM-MSEM
    produces redeposited material at the surface of slabs.
    The redeposited material is not part of the final dataset.
    This flag is typically present in the early scans of an experiment,
    e.g. scans [0,1,2].
    """
    DEPLETED = 8
    """IBEAM depleted the slab of material of interest.

    When IBEAM depleted a slab of its material of interest
        and IBEAM-MSEM operators determined that the slab is finished,
        they stop acquiring data for that slab.
    This determination is made at the slab level, e.g.,
        one slab is still being acquired while another one is not acquired any more.
    Several factors influence why some slabs require more scans than others.

    The determination from IBEAM-MSEM operators may be too conservative:
        more scans of a slab were acquired than necessary, e.g.,
        starting from scan #75 onwards, the scans of a slab do not contain useful data.
        The IBEAM-MSEM operators may, but do not have to,
        flag the acquired data after scan #75 as DEPLETED.
    """
    NO_SAMPLE_IN_SLAB_NO_LOSS = 9
    """the sample is missing from the slab but there is no lost data.

    For example, when mechanical sectioning of the sample block
    is stopped to collect on a new wafer, 
    the first cut slab after the interruption might be partial,
    e.g. slab #1 in drawing below.
    That is, only one part of the slab is present
    and the rest is physically missing.
    The IBEAM-MSEM operator might decide
        to still acquire the part that seems missing
        in case there is some sample in the apparently missing slab part
        that could not be seen in the light micrograph overview.

    The missing thickness does not necessarily rebalance at the next slab,
    intead, the missing thickness might rebalance smoothly over several slabs.

    Side view of slabs:

    -----A-----------A-----     slab #0 scan #0
    -----B-----------B-----     slab #0 scan #1
    -----C-----------C-----
    -----D-----------D-----
    -----E-----------E-----

    -----F-----                 slab #1 is partial
    -----G-----

    -----H-----------F-----     slab #2
    -----I-----------G-----
    -----J-----------H-----
               (-----I----) the missing thickness does not
               (-----J----) necessarily rebalance at the next slab
    """
    TEST = 10
    """IBEAM-MSEM operators acquired some test data."""
    DISTORTION_Y_NONLINEAR_MAYBE = 11
    """It is possible that data has a y-axis non-linear distortion.

    Flag likely specific to Janelia wafers #60/#61 only.
    A nonlinear distortion along the y axis affected some MFOVs during some scans.
    The distortion occurred approximately randomly,
    but is restricted to specific scans only.
    All SFOVs of an affected MFOV show the same distortion.
    """
