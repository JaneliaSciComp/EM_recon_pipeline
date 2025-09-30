"""Utilities to aggregate render stack metadata.

Prototype CLI fetches tile specs for a stack, prints each
`mipmapLevels/0/imageUrl`, and attempts to read lightweight metadata from the
referenced HDF5 dataset.
"""

from __future__ import annotations

import argparse
import logging
import sys
from collections import namedtuple
from pathlib import Path
import posixpath
from typing import Any, Sequence
from urllib.parse import parse_qs, unquote, urlparse

from janelia_emrp.render.web_service_request import RenderRequest

try:
    import h5py
except ImportError:  # pragma: no cover - optional dependency at runtime
    h5py = None  # type: ignore

try:
    import pandas as pd
except ImportError:  # pragma: no cover - optional dependency at runtime
    pd = None  # type: ignore

try:
    from scipy import stats
except ImportError:  # pragma: no cover - optional dependency at runtime
    stats = None  # type: ignore

from bokeh.io import output_file, save
from bokeh.models import ColumnDataSource, OpenURL, Range1d, TapTool
from bokeh.plotting import figure

Tile = namedtuple("Tile", ["tile_id", "z", "image_url"])

logger = logging.getLogger(__name__)

ATTRIBUTES_TO_PLOT = ["attr1", "attr2", "attr3"]


def fetch_tiles(render_request: RenderRequest, stack: str) -> list[Tile]:
    """Load tile specs for the stack and build lightweight descriptors."""
    z_values = render_request.get_z_values(stack)
    z_values = z_values[:10]  # TODO: remove limit after initial testing
    tiles = []
    for z in z_values:
        resolved_tiles = render_request.get_resolved_tiles_for_z(stack, z)
        for tile_spec in resolved_tiles.get("tileIdToSpecMap", {}).values():
            try:
                tile = Tile(
                    tile_id=tile_spec["tileId"],
                    z=z,
                    image_url=tile_spec["mipmapLevels"]["0"]["imageUrl"],
                )
            except KeyError as exc:
                logger.warning("missing expected field in tile spec at z=%s: %s", z, exc)
                continue
            tiles.append(tile)
    return tiles


def print_tile_spec_image_urls(
    base_data_url: str,
    owner: str,
    project: str,
    stack: str,
    output_dir: Path,
) -> None:
    """Fetch tile specs and print each mipmap level 0 image URL."""
    render_request = RenderRequest(
        host=base_data_url,
        owner=owner,
        project=project,
    )

    tiles = fetch_tiles(render_request, stack)
    metadata_rows: list[dict[str, Any]] = []
    for tile in tiles:
        print(tile.image_url)
        try:
            metadata = load_hdf5_metadata(tile.image_url)
        except (RuntimeError, FileNotFoundError, KeyError, ValueError, OSError) as exc:
            print(f"  unable to load HDF5 metadata: {exc}")
            continue

        print(f"  dataset: {metadata['dataset']}")
        print(f"  shape: {metadata['shape']}")
        print(f"  dtype: {metadata['dtype']}")
        print(f"  group: {metadata['group']}")
        group_attrs = metadata["group_attrs"]
        if group_attrs:
            print("  group attrs:")
            for key, value in group_attrs.items():
                print(f"    {key}: {value}")

        metadata_rows.append(
            {
                "tile_id": tile.tile_id,
                "z": tile.z,
                "image_url": tile.image_url,
                "dataset": metadata["dataset"],
                "shape": metadata["shape"],
                "dtype": metadata["dtype"],
                "group": metadata["group"],
                "group_attrs": metadata["group_attrs"],
            }
        )

    dataframe = build_metadata_dataframe(metadata_rows)
    dataframe = augment_dataframe_with_attributes(dataframe, ATTRIBUTES_TO_PLOT)

    print(f"Aggregated metadata rows: {len(dataframe)}")
    if not dataframe.empty:
        print(dataframe.head())

    generate_attribute_plots(
        dataframe=dataframe,
        attributes=ATTRIBUTES_TO_PLOT,
        output_dir=output_dir,
        owner=owner,
        project=project,
        stack=stack,
    )


def load_hdf5_metadata(image_url: str) -> dict[str, Any]:
    """Resolve an HDF5-backed image URL and return structural metadata."""
    if h5py is None:  # pragma: no cover - dependency check
        raise RuntimeError("h5py is not installed; install it to read HDF5 metadata")

    parsed_url = urlparse(image_url)
    if parsed_url.scheme != "file":
        raise ValueError(f"unsupported URL scheme for HDF5 access: {parsed_url.scheme}")

    file_path = unquote(parsed_url.path)
    query = parse_qs(parsed_url.query)
    dataset_path = query.get("dataSet", [None])[0]
    if dataset_path is None:
        raise ValueError("imageUrl does not include a dataSet query parameter")

    normalized_dataset_path = _normalize_dataset_path(dataset_path)

    return _read_hdf5_metadata(file_path, normalized_dataset_path)


def _read_hdf5_metadata(file_path: str, dataset_path: str) -> dict[str, Any]:
    assert h5py is not None  # pragma: no cover - guarded by caller

    normalized_dataset_path = dataset_path.rstrip("/") or "/"
    group_path = posixpath.dirname(normalized_dataset_path) or "/"

    with h5py.File(file_path, "r") as h5_file:
        dataset = h5_file[normalized_dataset_path]
        group = h5_file[group_path]
        group_attrs = dict(group.attrs)

    return {
        "file_path": file_path,
        "dataset": normalized_dataset_path,
        "group": group_path,
        "shape": tuple(int(dim) for dim in dataset.shape),
        "dtype": str(dataset.dtype),
        "group_attrs": group_attrs,
    }


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description="Fetch all tile specs for a render stack and print each 0th mipmap image URL."
    )
    parser.add_argument(
        "--base-data-url",
        required=True,
        help="Render web services host (e.g. em-services-1.int.janelia.org:8080).",
    )
    parser.add_argument(
        "--owner",
        required=True,
        help="Render owner for the project.",
    )
    parser.add_argument(
        "--project",
        required=True,
        help="Render project name.",
    )
    parser.add_argument(
        "--stack",
        required=True,
        help="Render stack to query for tile specs.",
    )
    parser.add_argument(
        "--output-dir",
        default=".",
        help="Directory where standalone plot HTML files will be written.",
    )
    return parser.parse_args(argv)


def build_metadata_dataframe(metadata_rows: list[dict[str, Any]]):
    if pd is None:  # pragma: no cover - dependency check
        raise RuntimeError("pandas is not installed; install it to build the metadata dataframe")

    columns = [
        "tile_id",
        "z",
        "image_url",
        "dataset",
        "shape",
        "dtype",
        "group",
        "group_attrs",
    ]

    if not metadata_rows:
        return pd.DataFrame(columns=columns)

    return pd.DataFrame(metadata_rows, columns=columns)


def augment_dataframe_with_attributes(dataframe, attribute_names: list[str]):
    if pd is None:  # pragma: no cover - dependency check
        raise RuntimeError("pandas is not installed; install it to build the metadata dataframe")

    if dataframe.empty:
        return dataframe

    df = dataframe[[
        "tile_id",
        "z",
        "image_url",
        "dataset",
        "shape",
        "dtype",
        "group",
        "group_attrs",
    ]].copy()

    def extract_attribute(attrs: Any, attr_name: str):
        if isinstance(attrs, dict):
            return attrs.get(attr_name)
        return None

    for attribute_name in attribute_names:
        df[attribute_name] = df["group_attrs"].apply(
            lambda attrs, name=attribute_name: extract_attribute(attrs, name)
        )
        df[attribute_name] = pd.to_numeric(df[attribute_name], errors="coerce")

    return df


def _normalize_dataset_path(dataset_path: str) -> str:
    normalized = dataset_path.strip()
    if not normalized:
        raise ValueError("dataSet query parameter is empty")

    normalized = normalized.rstrip("/")
    if not normalized:
        return "/"

    if not normalized.startswith("/"):
        normalized = f"/{normalized}"

    return normalized


def generate_attribute_plots(
    dataframe,
    attributes: list[str],
    output_dir: Path,
    owner: str,
    project: str,
    stack: str,
) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)

    for attribute in attributes:
        if attribute not in dataframe.columns:
            print(f"Attribute '{attribute}' not found in dataframe; skipping plot generation.")
            continue

        attribute_df = dataframe[["z", "image_url", attribute]].dropna().sort_values("z")
        if attribute_df.empty:
            print(f"No valid values for attribute '{attribute}'; skipping plot generation.")
            continue

        z_values = attribute_df["z"].tolist()
        attr_values = attribute_df[attribute].tolist()
        image_urls = attribute_df["image_url"].tolist()

        slope, intercept = theil_sen_regression(z_values, attr_values)

        x_min = min(z_values)
        x_max = max(z_values)
        if x_min == x_max:
            x_min -= 0.5
            x_max += 0.5

        y_min = min(attr_values)
        y_max = max(attr_values)
        if y_min == y_max:
            delta = 1 if y_min == 0 else abs(y_min) * 0.1
            y_min -= delta
            y_max += delta

        padding = max((y_max - y_min) * 0.05, 1e-6)

        regression_x = [x_min, x_max]
        regression_y = [slope * x + intercept for x in regression_x]

        source = ColumnDataSource(data=dict(z=z_values, value=attr_values, url=image_urls))
        regression_source = ColumnDataSource(data=dict(z=regression_x, value=regression_y))

        title = f"{project} / {stack} — {attribute} over z"
        tooltips = [("z", "@z"), (attribute, "@value"), ("image", "@url")]

        plot = figure(
            title=title,
            x_axis_label="z",
            y_axis_label=attribute,
            tooltips=tooltips,
            tools="tap,pan,box_zoom,wheel_zoom,save,reset",
            plot_width=1200,
            plot_height=400,
            y_range=Range1d(y_min - padding, y_max + padding),
        )

        plot.circle(source=source, x="z", y="value", size=6, line_color="navy", fill_alpha=0.6)
        plot.line(source=source, x="z", y="value", line_color="gray", line_alpha=0.3)
        plot.line(
            source=regression_source,
            x="z",
            y="value",
            line_width=2,
            line_color="tomato",
            legend_label="Robust fit",
        )

        plot.legend.location = "top_left"
        plot.legend.click_policy = "hide"

        tap_tool = plot.select_one(TapTool)
        if tap_tool is None:
            tap_tool = TapTool()
            plot.add_tools(tap_tool)
        tap_tool.callback = OpenURL(url="@url")

        output_path = output_dir / f"{attribute}_over_z.html"
        output_file(str(output_path), title=title)
        save(plot)
        print(f"Wrote {output_path}")


def theil_sen_regression(
    x_values: list[float], y_values: list[float]
) -> tuple[float, float]:
    if stats is None:  # pragma: no cover - dependency check
        raise RuntimeError("scipy is not installed; install it to compute theilslopes")

    if not x_values or not y_values or len(x_values) != len(y_values):
        raise ValueError("Input values for regression must be non-empty and of equal length")

    if len(x_values) == 1:
        return 0.0, y_values[0]

    slope, intercept, _, _ = stats.theilslopes(y_values, x_values)
    return float(slope), float(intercept)


def main(argv: Sequence[str] | None = None) -> None:
    """Main entry point for CLI."""
    if argv is None:
        argv = sys.argv[1:]
    args = parse_args(argv)
    output_dir = Path(args.output_dir).expanduser().resolve()
    print_tile_spec_image_urls(base_data_url=args.base_data_url,
                               owner=args.owner,
                               project=args.project,
                               stack=args.stack,
                               output_dir=output_dir)


if __name__ == "__main__":
    # main()
    main([
        "--base-data-url",
        "em-services-1.int.janelia.org:8080",
        "--owner",
        "cellmap",
        "--project",
        "jrc_mus_heart_4",
        "--stack",
        "imaging_preview",
        "--output-dir",
        "./plots",
    ])
