"""Helpers and demo for the ingestion of IBEAMMSEM data.

Run this script to see an overview of the provided functions.
The functions in the neighbor modules show how to get data from the xarray.

See XVariable.ID_SERIAL for definition of MagC and serial orders.

Slab IDs are MagC IDs by default.
"""

from __future__ import annotations

import argparse

import matplotlib
import matplotlib.pyplot as plt
import numpy as np
import xarray as xr
from skimage.io import imshow

from assembly import (
    assemble_mfovs_straight,
    get_slab_rotation,
    get_xy_slab,
    plot_aligned_slab,
)
from constant import N_BEAMS
from id import get_all_magc_ids, get_magc_ids, get_region_ids, get_serial_ids
from metrics import get_raw_average, get_raw_stdev, get_timestamp
from path import get_mfov_path, get_sfov_path, get_slab_path, get_thumbnail_path
from roi import (
    get_distance_to_roi,
    get_mfovs,
    get_n_mfovs,
    get_n_slabs,
    get_percentage_tissue,
    get_roi_sfovs,
    get_slabs,
    plot_distance_roi,
    plot_tissue_sfovs,
)

matplotlib.use("tkagg")


def main(arguments) -> None:
    """See parse_arguments for the arguments."""
    xlog = xr.open_zarr(arguments.path_xlog)

    # id
    println(f"{get_all_magc_ids(xlog=xlog) = }")

    println(f"{get_serial_ids(xlog=xlog, magc_ids=[12]) = }")
    println(f"{get_serial_ids(xlog=xlog, magc_ids=np.arange(4)) = }")
    println(f"{get_serial_ids(xlog=xlog, magc_ids=get_all_magc_ids(xlog)) = }")

    println(f"{get_slabs(xlog=xlog, scan=2) = }")
    n_slabs = get_n_slabs(xlog=xlog, scan=2)
    println(f"{n_slabs = }")

    println(f"{get_magc_ids(xlog=xlog, serial_ids = np.arange(n_slabs)) = }")
    println(f"{get_region_ids(xlog=xlog,slab=2, mfovs=np.arange(50)) = }")

    #  path
    slab_path = get_slab_path(xlog=xlog, scan=1, slab=2)
    println(f"{get_mfov_path(slab_path=slab_path, mfov=3) = }")
    println(f"{get_sfov_path(slab_path=slab_path, mfov=3, sfov=0) = }")
    println(f"{get_thumbnail_path(slab_path=slab_path, mfov=3, sfov=0) = }")

    # metrics
    println(f"{get_raw_average(xlog=xlog, scan=3, slab=2, mfov=2, sfov=5) = :.2f}")
    println(f"{get_raw_stdev(xlog=xlog, scan=3, slab=2, mfov=2, sfov=5) = :.2f}")
    println(f"{get_timestamp(xlog=xlog, scan=3, slab=2, mfov=2)=}")

    # ROI
    println(f"{get_distance_to_roi(xlog=xlog, slab=2, mfov=2, sfov=5) = :.2f} microns")
    println(f"{get_roi_sfovs(xlog=xlog, slab=2, mfov=2, dilation=15) = }")
    println(f"{get_roi_sfovs(xlog=xlog, slab=2, mfov=31, dilation=10) = }")
    println(f"{get_roi_sfovs(xlog=xlog, slab=2, mfov=12, dilation=0) = }")
    println(f"{get_mfovs(xlog=xlog, slab=2) = }")
    println(f"{get_n_mfovs(xlog=xlog, scan=2) = }")

    n_sfovs = get_n_mfovs(xlog=xlog, scan=0) * N_BEAMS
    println(f"{n_sfovs = :_}")

    plot_distance_roi(xlog=xlog, slab=2)
    plot_distance_roi(xlog=xlog, slab=2, mfov=5)
    plot_tissue_sfovs(xlog=xlog, slab=2)

    println(f"{get_percentage_tissue(xlog=xlog, scan=3, dilation=10) = :.2f}%")
    println(f"{get_percentage_tissue(xlog=xlog, scan=3, dilation=20) = :.2f}%")

    # assembly
    println(f"{get_slab_rotation(xlog=xlog, scan=3, slab=2) = :.2f} degrees")
    println(f"{get_xy_slab(xlog=xlog, scan=2, slab=2).shape = }")

    println("assemble images | takes 5-20 seconds ...")
    mfov = assemble_mfovs_straight(
        xlog=xlog, scan=10, slab=7, mfovs=[10], thumbnail=True
    )
    imshow(mfov)

    mfov = assemble_mfovs_straight(
        xlog=xlog, scan=10, slab=7, mfovs=[10, 11], thumbnail=True
    )
    plt.figure()
    imshow(mfov)

    mfov = assemble_mfovs_straight(xlog=xlog, scan=10, slab=7, thumbnail=True)
    plt.figure()
    imshow(mfov)
    plt.show()

    println("assemble images | takes 5-20 seconds ...")
    plot_aligned_slab(xlog=xlog, scan=2, slab=7, thumbnail=True)


def println(t: str) -> None:
    print(f"{t}\n")


def parse_arguments():
    """Parse arguments."""
    parser = argparse.ArgumentParser(description="data ingestion for wafers 60/61")
    parser.add_argument("--path_xlog", help="path of the wafer xarray", required=True)
    return parser.parse_args()


if __name__ == "__main__":
    arguments = parse_arguments()
    main(arguments)
