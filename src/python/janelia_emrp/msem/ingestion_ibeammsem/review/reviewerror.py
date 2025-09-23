"""ReviewError"""


class ReviewError(Exception):
    """ReviewError."""


class FlagSetWithNoActionError(ReviewError):
    """A set of flags is missing a defined action.

    You should add a new entry in the ReviewStrategy.
    """
