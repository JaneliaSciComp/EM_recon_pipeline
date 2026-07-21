"""
For each multi-SEM MFOV, SFOV numbers start at 1 in the center and spiral counter-clockwise out to 91.
This list supports mapping an SFOV index to its render order
with the assumption that rendering should occur top-to-bottom, left-to-right within each MFOV.

This list was copied from
  https://github.com/saalfeldlab/render/blob/newsolver/render-ws-java-client/src/main/java/org/janelia/render/client/TileReorderingClient.java#L155-L165
"""

RENDER_SFOV_ORDER = [
    46, 47, 36, 35, 45, 56, 57, 48, 37, 27,  #  s1 to s10
    26, 25, 34, 44, 55, 65, 66, 67, 58, 49,  # s11 to s20
    38, 28, 19, 18, 17, 16, 24, 33, 43, 54,  # s21 to s30
    64, 73, 74, 75, 76, 68, 59, 50, 39, 29,  # s31 to s40
    20, 12, 11, 10,  9,  8, 15, 23, 32, 42,  # s41 to s50
    53, 63, 72, 80, 81, 82, 83, 84, 77, 69,  # s51 to s60
    60, 51, 40, 30, 21, 13,  6,  5,  4,  3,  # s61 to s70
     2,  1,  7, 14, 22, 31, 41, 52, 62, 71,  # s71 to s80
    79, 86, 87, 88, 89, 90, 91, 85, 78, 70,  # s81 to s90
    61                                       # s91
]


RENDER_SFOV_ORDER_JANELIA_IBEAMMSEM_60_61 = [
    57, 50, 46, 51, 60, 65, 59, 47, 42, 36, 
    43, 48, 54, 56, 69, 76, 72, 68, 55, 44,
    37, 31, 24, 32, 38, 18, 25, 33, 39, 64,
    71, 83, 79, 75, 70, 63, 52, 34, 26, 19,
    12,  7, 20, 27, 13,  8, 14, 21, 28, 35,
    45, 67, 78, 86, 88, 85, 82, 77, 66, 58,
    49, 29, 22, 15,  9,  3,  1,  4, 16, 10,
     5,  2,  6, 11, 17, 23, 30, 40, 62, 74,
    81, 90, 91, 89, 87, 84, 80, 73, 61, 53,
    41                                     
]


def render_sfov_order(wafer: str) -> list[int]:
    """SFOV render order of a wafer."""
    if wafer in ("60", "61"):
        return RENDER_SFOV_ORDER_JANELIA_IBEAMMSEM_60_61
    return RENDER_SFOV_ORDER