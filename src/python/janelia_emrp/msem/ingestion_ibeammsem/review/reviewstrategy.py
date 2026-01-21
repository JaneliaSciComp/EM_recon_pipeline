"""Strategy for ingestion depending on review.

A strategy is a mapping from a set of ReviewFlags to a ReviewAction:
dict[frozenset[Flag], Action]

An MFOV might have the flags
    {
        Flag.DISTORTION_Y_LINEAR_SEVERE_LATER_RETAKEN,
        Flag.DISTORTION_Y_NONLINEAR_MAYBE,
    }.
A strategy defines an action for MFOVs with such a set of flags.
"""

from janelia_emrp.msem.ingestion_ibeammsem.review.reviewflag import ReviewFlag as Flag
from janelia_emrp.msem.ingestion_ibeammsem.review.reviewaction import (
    ReviewAction as Action,
)

fset = frozenset

REVIEW_STRATEGY: dict[int, dict[frozenset[Flag], Action]] = {
    0: {
        # Action.USE
        fset({Flag.NOMINAL}): Action.USE,
        fset({Flag.DISTORTION_Y_LINEAR_MILD}): Action.USE,
        fset({Flag.DISTORTION_Y_NONLINEAR_MAYBE}): Action.USE,
        # Action.WITH_Z_MASK
        fset({Flag.NO_FILE}): Action.WITH_Z_MASK,
        fset({Flag.OFFSET_LOSS}): Action.WITH_Z_MASK,
        fset({Flag.OFFSET_SALVAGEABLE}): Action.WITH_Z_MASK,
        fset({Flag.DISTORTION_Y_LINEAR_SEVERE}): Action.WITH_Z_MASK,
        # Action.NO_Z_DROP
        fset({Flag.DISTORTION_Y_LINEAR_SEVERE_LATER_RETAKEN}): Action.NO_Z_DROP,
        fset(
            {
                Flag.DISTORTION_Y_LINEAR_SEVERE_LATER_RETAKEN,
                Flag.DISTORTION_Y_NONLINEAR_MAYBE,
            }
        ): Action.NO_Z_DROP,
        fset({Flag.REDEPOSITED_MATERIAL}): Action.NO_Z_DROP,
        fset(
            {Flag.REDEPOSITED_MATERIAL, Flag.DISTORTION_Y_NONLINEAR_MAYBE}
        ): Action.NO_Z_DROP,
        fset(
            {
                Flag.REDEPOSITED_MATERIAL,
                Flag.DISTORTION_Y_NONLINEAR_MAYBE,
                Flag.NO_SAMPLE_IN_SLAB_NO_LOSS,
            }
        ): Action.NO_Z_DROP,
        fset({Flag.DEPLETED}): Action.NO_Z_DROP,
        fset({Flag.NO_SAMPLE_IN_SLAB_NO_LOSS}): Action.NO_Z_DROP,
        fset({Flag.TEST}): Action.NO_Z_DROP,
    },
    # 1: add your custom strategy
}
