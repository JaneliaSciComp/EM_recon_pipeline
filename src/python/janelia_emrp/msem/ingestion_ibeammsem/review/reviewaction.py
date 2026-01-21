"""ReviewAction."""

from enum import IntEnum


class ReviewAction(IntEnum):
    """Action about an item during data ingestion."""

    USE = 0
    """Use the item for the ingestion.
    
    It is the nominal action.
    """
    WITH_Z_MASK = 1
    """The item would have filled a Z-slice: mask it.

    WITH_Z means that a nominal image of the item is not available
    and it would have filled a Z-slice slot.
    """
    WITH_Z_INPAINT = 2
    """The item would have filled a Z-slice: inpaint it.
    
    WITH_Z means that a nominal image of the item is not available
    and it would have filled a Z-slice slot.
    """
    NO_Z_DROP = 3
    """The item would not have filled a Z-slice: drop it.

    We typically decide to NO_Z_DROP items with any of these ReviewFlag:
        REDEPOSITED_MATERIAL
        DEPLETED
        NO_SAMPLE_IN_SLAB_NO_LOSS
    
    The item is not meant to fill a Z-slice.
    """
