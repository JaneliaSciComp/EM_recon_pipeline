"""
Build a beam correction xlog container for Google storage by
copying the arrays needed for beam correction out of a wafer's acquisition xlog and
replacing each array's blosc compressor with gzip.
Switching to gzip compression allows java n5-zarr readers to decode arrays without a native library.

Only the datasets needed for beam correction are copied.
Large arrays that the beam correction process does not need like cost_x, cost_y, and histogram
are left out of the result.

Usage:
    ./build_google_beam_correction_xlog.py <wafer: 60 or 61>

For example:
    ./build_google_beam_correction_xlog.py 61

Then upload:
    gsutil -m rsync -r /groups/hess/hesslab/render/xlog/beam_correction/xlog_wafer_61.zarr \
                       gs://janelia-spark-test/library/xlog_wafer_61.zarr
"""

import json
import sys
from pathlib import Path

import numcodecs
import numpy as np
import zarr

DATASETS = (
    "beam_homogenization",
    "distance_roi",
    "id_serial",
    "scan",
    "sfov",
    "slab",
)

GZIP_LEVEL = 5

WAFERS = ("60", "61")


def read_zarray(array):
    """Returns the raw .zarray metadata for an array (for values zarr does not expose)."""
    key = f"{array.path}/.zarray" if array.path else ".zarray"
    raw = array.store[key]
    return json.loads(raw.decode("utf-8") if isinstance(raw, bytes) else raw)


def validate_datasets(source, names):
    """Exits with an error if any requested name is missing from the source or is not an array."""
    problems = []
    for name in names:
        if name not in source:
            problems.append(f"{name} is not in the source container")
        elif not isinstance(source[name], zarr.Array):
            problems.append(f"{name} is a group, not an array")
    if problems:
        available = sorted(name for name, _ in source.arrays())
        sys.exit("\n".join(problems) + f"\nsource arrays are: {available}")


def copy_array(source, dest_group, name, compressor):
    meta = read_zarray(source)

    dest = dest_group.create_dataset(
        name,
        shape=source.shape,
        chunks=source.chunks,
        dtype=source.dtype,
        compressor=compressor,
        filters=source.filters,
        order=source.order,
        fill_value=source.fill_value,
        dimension_separator=meta.get("dimension_separator", "."),
        overwrite=True,
    )

    # copy one chunk-row at a time so that large arrays are never fully resident
    if source.ndim == 0:
        dest[...] = source[...]
    else:
        step = source.chunks[0]
        for start in range(0, source.shape[0], step):
            stop = min(start + step, source.shape[0])
            dest[start:stop] = source[start:stop]

    dest.attrs.update(dict(source.attrs))

    print(f"  {source.path or '/'}: {meta.get('compressor')} -> "
          f"{dest.compressor.get_config() if dest.compressor else None}")

    return dest


def copy_datasets(source, dest, names, compressor):
    dest.attrs.update(dict(source.attrs))
    for name in names:
        if "/" in name:
            parent_path, array_name = name.rsplit("/", 1)
            parent = dest.require_group(parent_path)
        else:
            parent, array_name = dest, name
        copy_array(source[name], parent, array_name, compressor)


def verify(source_path, dest_path, names):
    source = zarr.open_group(source_path, mode="r")
    dest = zarr.open_group(dest_path, mode="r")

    failures = 0
    for name in names:
        expected = source[name][...]
        actual = dest[name][...]
        equal_nan = expected.dtype.kind == "f"
        if np.array_equal(expected, actual, equal_nan=equal_nan):
            print(f"  {name}: {expected.shape} {expected.dtype} values match")
        else:
            print(f"  {name}: VALUES DIFFER", file=sys.stderr)
            failures += 1
        if dict(source[name].attrs) != dict(dest[name].attrs):
            print(f"  {name}: ATTRIBUTES DIFFER", file=sys.stderr)
            failures += 1
    return failures


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)

    wafer = sys.argv[1]
    if wafer not in WAFERS:
        sys.exit(f"invalid wafer '{wafer}'\n{__doc__}")

    if zarr.__version__.split(".")[0] != "2":
        sys.exit(f"this script uses the zarr v2 API but found zarr {zarr.__version__}; "
                 f"install with: pip install 'zarr<3'")

    source_path = f"/groups/hess/hesslab/ibeammsem/system_02/wafers/wafer_{wafer}/xlog/xlog_wafer_{wafer}.zarr"
    dest_path = f"/groups/hess/hesslab/render/xlog/beam_correction/xlog_wafer_{wafer}.zarr"

    if not Path(source_path).is_dir():
        sys.exit(f"source container {source_path} does not exist")

    # zarr.open_group(dest_path, mode="w") would silently replace an existing container
    if Path(dest_path).exists():
        sys.exit(f"dest container {dest_path} already exists, remove it before running this script")

    compressor = numcodecs.GZip(GZIP_LEVEL)  # -> n5-zarr GzipCompression(level)
    datasets = list(DATASETS)

    print(f"copying {len(datasets)} datasets from {source_path} to {dest_path} using gzip")

    source = zarr.open_group(source_path, mode="r")
    validate_datasets(source, datasets)

    dest = zarr.open_group(dest_path, mode="w")
    copy_datasets(source, dest, datasets, compressor)

    zarr.consolidate_metadata(dest.store)
    print(f"wrote {dest_path} and consolidated its metadata")

    print("verifying")
    failures = verify(source_path, dest_path, datasets)
    if failures > 0:
        sys.exit(f"{failures} verification failure(s)")
    print("all arrays match")


if __name__ == "__main__":
    main()