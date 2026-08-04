"""
Build a beam correction xlog container for Google storage
by copying the variables needed for beam correction out of a wafer's acquisition xlog
and replacing each array's blosc compressor with gzip.
Gzip compression allows java n5-zarr readers to decode arrays without a native library.

Only the variables needed for beam correction are copied, see DATA_VARS.

Usage:
    ./build_google_beam_correction_xlog.py <wafer: 60 or 61>

For example:
    ./build_google_beam_correction_xlog.py 61

Then upload:
    gsutil -m rsync -r /groups/hess/hesslab/render/xlog/beam_correction/xlog_wafer_61.zarr \
                       gs://janelia-spark-test/library/xlog_wafer_61.zarr
"""

from __future__ import annotations

import sys
from pathlib import Path
from typing import TYPE_CHECKING

import xarray as xr
import zarr
from janelia_emrp.msem.ingestion_ibeammsem.xvar import XVar
from numcodecs import GZip

if TYPE_CHECKING:
    from numcodecs.abc import Codec

DATA_VARS = (
    XVar.BEAM_HOMOGENIZATION,
    XVar.DISTANCE_ROI,
    XVar.ID_SERIAL,
)

GZIP_LEVEL = 5

WAFERS = ("60", "61")


def copy_variables(
    source: Path, target: Path, variables: tuple[XVar, ...], codec: Codec
) -> None:
    """Copies the variables from source to target xarrays, compressed with codec."""
    subset = xr.open_zarr(source)[list(variables)]
    for variable in subset.variables.values():
        variable.encoding["compressor"] = codec
    subset.to_zarr(target)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)

    wafer = sys.argv[1]
    if wafer not in WAFERS:
        sys.exit(f"invalid wafer '{wafer}'\n{__doc__}")

    if zarr.__version__.split(".")[0] != "2":
        sys.exit(
            f"this script uses the zarr v2 API but found zarr {zarr.__version__}; "
            f"install with: pip install 'zarr<3'"
        )

    source = Path(
        f"/groups/hess/hesslab/ibeammsem/system_02/wafers/wafer_{wafer}/xlog/xlog_wafer_{wafer}.zarr"
    )
    target = Path(
        f"/groups/hess/hesslab/render/xlog/beam_correction/xlog_wafer_{wafer}.zarr"
    )

    if not source.is_dir():
        sys.exit(f"container {source=!s} does not exist")

    # to_zarr(mode="w") would silently replace an existing container
    if target.exists():
        sys.exit(
            f"container {target=!s} already exists, remove it before running this script"
        )

    codec = GZip(GZIP_LEVEL)
    print(f"copying {', '.join(DATA_VARS)} from {source} to {target} using {codec}")
    copy_variables(source=source, target=target, variables=DATA_VARS, codec=codec)
    print(f"wrote {target}")

    print("verifying")
    xr.testing.assert_identical(
        xr.open_zarr(source)[list(DATA_VARS)], xr.open_zarr(target)
    )
    print("all arrays match")


if __name__ == "__main__":
    main()
