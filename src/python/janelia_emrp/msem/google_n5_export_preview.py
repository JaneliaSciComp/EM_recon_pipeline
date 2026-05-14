#!/usr/bin/env python3
"""
google_n5_export_preview.py – Generate a zoomed-out XY preview image from a multiscale n5 volume on GCS.

Usage:
    python google_n5_export_preview.py
    python google_n5_export_preview.py --wafer 60 --min-project-number 80 --max-project-number 100 --slab-suffix _gc_par_crc_align_ic2d___mask
    python google_n5_export_preview.py --slab-suffix _gc_par_crc_align_ic2d___norm-layer
    python google_n5_export_preview.py --slab-suffix _gc_par_crc_align_ic2d___norm-layer-hist

Generated with assistance from Claude (claude.ai), Anthropic's AI assistant.
"""

import argparse
import json
from datetime import datetime
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont
import tensorstore as ts
from google.cloud import storage
from google.auth.credentials import AnonymousCredentials


# ---------------------------------------------------------------------------
# Path construction
# ---------------------------------------------------------------------------

def build_gs_path(base_path: str, wafer: int, slab_number: int, region: str, slab_suffix: str) -> tuple[str, str]:
    """
    Build the gs:// path from its components.
    Returns (gs_path, project) tuple.

    Examples:
        wafer=61, slab_number=71, region='r00' -> .../w61_serial_070_to_079/w61_s071_r00_gc_par_crc_align_ic2d___pixel
        wafer=60, slab_number=101, region='r00' -> .../w60_serial_100_to_109/w60_s101_r00_gc_par_crc_align_ic2d___pixel
    """
    decade_start = (slab_number // 10) * 10
    decade_end = decade_start + 9
    project = f"w{wafer}_serial_{decade_start:03d}_to_{decade_end:03d}"
    volume = f"w{wafer}_s{slab_number:03d}_{region}{slab_suffix}"
    return f"{base_path.rstrip('/')}/{project}/{volume}", project


# ---------------------------------------------------------------------------
# GCS helpers
# ---------------------------------------------------------------------------

def _bucket(gs_path: str) -> str:
    return gs_path.replace("gs://", "").split("/")[0]


def _prefix(gs_path: str) -> str:
    return "/".join(gs_path.replace("gs://", "").split("/")[1:])


def _gcs_client(anonymous: bool = True) -> storage.Client:
    if anonymous:
        return storage.Client(credentials=AnonymousCredentials(), project="dummy")
    return storage.Client()  # uses GOOGLE_APPLICATION_CREDENTIALS


# ---------------------------------------------------------------------------
# Core logic
# ---------------------------------------------------------------------------

def open_scale(gs_path: str, s_level: str, anonymous: bool = True) -> ts.TensorStore:
    """
    Open the specified scale level of a multiscale n5 volume.

    Args:
        gs_path:    Full gs:// path to the n5 dataset (no trailing slash)
        s_level:    Scale level to open (e.g. 's10')
        anonymous:  Use anonymous GCS access (set False for private buckets)
    """
    client = _gcs_client(anonymous=anonymous)
    bucket_name = _bucket(gs_path)
    prefix = _prefix(gs_path)
    bucket = client.bucket(bucket_name)

    # Read top-level attributes.json
    attr_blob = bucket.blob(f"{prefix}/attributes.json")
    attrs = json.loads(attr_blob.download_as_text())
    print(f"  → attributes.json: {json.dumps(attrs, indent=2)[:300]}...")

    # Read scale-level attributes.json
    scale_attr_blob = bucket.blob(f"{prefix}/{s_level}/attributes.json")
    scale_attrs = json.loads(scale_attr_blob.download_as_text())
    dims = scale_attrs.get("dimensions", scale_attrs.get("size", []))
    print(f"  → {s_level} dimensions: {dims}")

    full_path = f"{gs_path}/{s_level}"
    print(f"  → Using scale: {s_level}  ({full_path})")

    spec = {
        "driver": "n5",
        "kvstore": {
            "driver": "gcs",
            "bucket": _bucket(full_path),
            "path": _prefix(full_path),
        },
    }
    return ts.open(spec, read=True, write=False).result()


def equalize_histogram(arr: np.ndarray, percentile: float) -> np.ndarray:
    """
    Normalize and histogram-equalize a float32 array to uint8.

    Steps:
      1. Clip to [percentile_low, percentile_high] to remove outliers.
      2. Build a cumulative distribution function (CDF) over the clipped values.
      3. Map pixel values through the CDF to stretch contrast across 0–255.
    """
    lo = float(np.percentile(arr, 100 - percentile))
    hi = float(np.percentile(arr, percentile))
    if hi <= lo:
        return np.zeros(arr.shape, dtype=np.uint8)

    arr_clipped = np.clip(arr, lo, hi)

    # Compute CDF from a 256-bin histogram over the clipped range
    hist, bin_edges = np.histogram(arr_clipped, bins=256, range=(lo, hi))
    cdf = hist.cumsum()
    cdf = cdf / cdf[-1]  # normalize to [0, 1]

    # Map each pixel through the CDF using the bin edges as lookup points
    bin_centers = (bin_edges[:-1] + bin_edges[1:]) / 2
    equalized = np.interp(arr_clipped, bin_centers, cdf)

    return (equalized * 255).astype(np.uint8)


def read_slab_image(
        gs_path: str,
        s_level: str,
        z_index: int | None,
        percentile: float,
        anonymous: bool,
) -> tuple[Image.Image, int, int]:
    """
    Read one slab at the given scale level and return a (normalized grayscale PIL Image, actual_z, max_z) tuple.
    """
    store = open_scale(gs_path, s_level=s_level, anonymous=anonymous)
    shape = store.domain.shape
    print(f"  → Shape at {s_level}: {shape}")

    ndim = len(shape)
    if ndim == 3:
        nx, ny, nz = shape
        zi = nz // 2 if z_index is None else min(z_index, nz - 1)
        print(f"  → Reading Z slice {zi}/{nz}")
        arr = store[:, :, zi].read().result()
    elif ndim == 4:
        nx, ny, nz = shape[1], shape[2], shape[3]
        zi = nz // 2 if z_index is None else min(z_index, nz - 1)
        print(f"  → Reading Z slice {zi}/{nz} (channel 0)")
        arr = store[0, :, :, zi].read().result()
    else:
        raise ValueError(f"Unexpected ndim={ndim}, shape={shape}")

    arr = np.array(arr, dtype=np.float32)
    img_data = equalize_histogram(arr, percentile).T  # transpose: n5 x,y → image row,col
    return Image.fromarray(img_data, mode="L"), zi, nz


def load_project_row(
        base_path: str,
        wafer: int,
        project_number: int,
        region: str,
        slab_suffix: str,
        s_level: str,
        z_index: int | None,
        percentile: float,
        anonymous: bool,
) -> tuple[list[Image.Image], list[int], list[int], list[int]]:
    """
    Load all slab images for one project decade.
    Returns (slab_images, successful_slab_numbers, actual_z_indices, max_z_values).
    """
    decade_start = (project_number // 10) * 10
    slab_images: list[Image.Image] = []
    successful_slabs: list[int] = []
    actual_z_indices: list[int] = []
    max_z_values: list[int] = []

    for slab_number in range(decade_start, decade_start + 10):
        gs_path, _ = build_gs_path(base_path, wafer, slab_number, region, slab_suffix)
        print(f"\nProcessing slab {slab_number}: {gs_path}")
        try:
            img, zi, nz = read_slab_image(gs_path, s_level, z_index, percentile, anonymous)
            slab_images.append(img)
            successful_slabs.append(slab_number)
            actual_z_indices.append(zi)
            max_z_values.append(nz)
            print(f"  → Slab {slab_number} image size: {img.size[0]}×{img.size[1]} px")
        except Exception as e:
            print(f"  WARNING: skipping slab {slab_number}: {e}")

    return slab_images, successful_slabs, actual_z_indices, max_z_values


def build_row_image(
        slab_images: list[Image.Image],
        successful_slabs: list[int],
        actual_z_indices: list[int],
        max_z_values: list[int],
        target_cell_width: int,
        target_cell_height: int,
        label_height: int,
        font: ImageFont.FreeTypeFont | ImageFont.ImageFont,
) -> Image.Image:
    """
    Stitch one project's slab images into a single horizontal strip with labels.
    Each slab is centered in a cell of (target_cell_width x target_cell_height)
    with black padding. Labels (e.g. 's070 z44/89') are drawn above each cell.
    """
    n = len(slab_images)
    row = Image.new("L", (target_cell_width * n, target_cell_height + label_height))
    draw = ImageDraw.Draw(row)

    for i, (img, slab_number, zi, nz) in enumerate(zip(slab_images, successful_slabs, actual_z_indices, max_z_values)):
        w, h = img.size
        x_offset = i * target_cell_width + (target_cell_width - w) // 2
        y_offset = label_height + (target_cell_height - h) // 2
        row.paste(img, (x_offset, y_offset))
        label = f"s{slab_number:03d} z{zi}/{nz}"
        draw.text((i * target_cell_width + 4, 2), label, fill=255, font=font)

    return row


def make_preview(
        base_path: str,
        wafer: int,
        project_numbers: list[int],
        region: str,
        slab_suffix: str,
        out_path: str,
        s_level: str = "s10",
        z_index: int | None = None,
        percentile: float = 99.5,
        anonymous: bool = True,
) -> None:
    """
    Generate a preview image with one row per project decade, each row being a
    horizontal strip of 10 slab images. Slabs are kept at native s_level resolution
    and centered with black padding. Labels (e.g. 's070 z44/89') are drawn above each
    slab. A header at the top shows the run parameters.

    Args:
        base_path:       Base gs:// path
        wafer:           Wafer number
        project_numbers: List of decade starts (e.g. [70, 80, 90])
        region:          Region string (e.g. 'r00')
        slab_suffix:     Slab name suffix
        out_path:        Where to write the PNG
        s_level:         Scale level to use (e.g. 's10')
        z_index:         Which Z slice to use (default: middle slice)
        percentile:      Upper percentile for contrast normalization
        anonymous:       Use anonymous GCS access
    """
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 16)
        header_font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 28)
    except OSError:
        font = ImageFont.load_default()
        header_font = font

    label_height = 20
    row_gap = 30  # empty pixels above each slab row

    # Load all rows first so we can compute a globally consistent cell size
    all_rows: list[tuple[list[Image.Image], list[int], list[int], list[int]]] = []
    for project_number in project_numbers:
        print(f"\n{'='*60}")
        decade_start = (project_number // 10) * 10
        decade_end = decade_start + 9
        print(f"Loading project: w{wafer}_serial_{decade_start:03d}_to_{decade_end:03d}")
        print(f"{'='*60}")
        slab_images, successful_slabs, actual_z_indices, max_z_values = load_project_row(
            base_path, wafer, project_number, region, slab_suffix,
            s_level, z_index, percentile, anonymous,
        )
        if slab_images:
            all_rows.append((slab_images, successful_slabs, actual_z_indices, max_z_values))
        else:
            print(f"  WARNING: no slabs loaded for project {project_number}, skipping row.")

    if not all_rows:
        raise RuntimeError("No slab images could be loaded for any project.")

    # Global cell size: max slab width and height across all projects
    all_images = [img for slab_images, _, _, _ in all_rows for img in slab_images]
    cell_width = max(img.size[0] for img in all_images)
    cell_height = max(img.size[1] for img in all_images)
    print(f"\nGlobal cell size: {cell_width}×{cell_height} px")

    # Build each row and stack vertically
    row_images = [
        build_row_image(slab_images, successful_slabs, actual_z_indices, max_z_values,
                        cell_width, cell_height, label_height, font)
        for slab_images, successful_slabs, actual_z_indices, max_z_values in all_rows
    ]

    # Build header image with run parameters
    header_lines = [
        f"base-path: {base_path}",
        f"wafer: {wafer}    region: {region}    slab-suffix: {slab_suffix}    level: {s_level}",
    ]
    row_width = max(row.size[0] for row in row_images)
    header_row_height = 40
    header_height = header_row_height * len(header_lines) + 4
    header = Image.new("L", (row_width, header_height))
    header_draw = ImageDraw.Draw(header)
    for i, line in enumerate(header_lines):
        header_draw.text((4, 2 + i * header_row_height), line, fill=255, font=header_font)

    total_width = row_width
    total_height = header_height + sum(row.size[1] for row in row_images) + row_gap * len(row_images)
    final = Image.new("L", (total_width, total_height))
    final.paste(header, (0, 0))
    y_offset = header_height
    for row in row_images:
        y_offset += row_gap
        final.paste(row, (0, y_offset))
        y_offset += row.size[1]

    Path(out_path).parent.mkdir(parents=True, exist_ok=True)
    final.save(out_path)
    print(f"\n→ Saved preview ({len(all_rows)} rows, {len(all_images)} slabs total): "
          f"{out_path}  ({final.size[0]}×{final.size[1]} px)")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Generate zoomed-out XY preview PNGs from multiscale n5 volumes on GCS."
    )
    parser.add_argument("--base-path", default="gs://janelia-spark-test/hess_wafers_60_61_export/render",
                        help="base gs:// path (default: gs://janelia-spark-test/hess_wafers_60_61_export/render)")
    parser.add_argument("--wafer", type=int, default=61,
                        help="wafer number (default: 61)")
    parser.add_argument("--min-project-number", type=int, default=60,
                        help="first project decade start, inclusive (default: 70)")
    parser.add_argument("--max-project-number", type=int, default=70,
                        help="last project decade start, inclusive (default: 150)")
    parser.add_argument("--region", default="r00",
                        help="region string (default: r00)")
    parser.add_argument("--slab-suffix", default="_gc_par_crc_align_ic2d___pixel",
                        help="slab suffix (default: _gc_par_crc_align_ic2d___pixel)")
    parser.add_argument("--output-dir", default="~/Desktop",
                        help="output directory for preview PNG (default: ~/Desktop)")
    parser.add_argument("--level", default="s10",
                        help="scale level to use (default: s10)")
    parser.add_argument("--z", type=int, default=None,
                        help="Z slice index (default: middle)")
    parser.add_argument("--no-anon", action="store_true",
                        help="disable anonymous access (use GOOGLE_APPLICATION_CREDENTIALS)")
    args = parser.parse_args()

    anonymous = not args.no_anon

    # Build project number list: one entry per decade from min to max, inclusive
    min_decade = (args.min_project_number // 10) * 10
    max_decade = (args.max_project_number // 10) * 10
    project_numbers = list(range(min_decade, max_decade + 10, 10))

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    out_dir = Path(args.output_dir).expanduser()
    out_path = str(out_dir / f"w{args.wafer}_serial_{min_decade:03d}_to_{max_decade:03d}_{args.region}{args.slab_suffix}.{timestamp}.png")

    print(f"Wafer:    {args.wafer}")
    print(f"Projects: {project_numbers}")
    print(f"Region:   {args.region}")
    print(f"Output:   {out_path}")

    make_preview(
        base_path=args.base_path,
        wafer=args.wafer,
        project_numbers=project_numbers,
        region=args.region,
        slab_suffix=args.slab_suffix,
        out_path=out_path,
        s_level=args.level,
        z_index=args.z,
        anonymous=anonymous,
    )


if __name__ == "__main__":
    main()