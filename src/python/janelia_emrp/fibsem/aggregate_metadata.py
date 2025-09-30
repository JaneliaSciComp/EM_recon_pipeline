import argparse
import logging
import sys
from collections import namedtuple
from pathlib import Path
from typing import Any, Sequence, Union
from urllib.parse import parse_qs, unquote, urlparse

import h5py
import pandas as pd
from scipy import stats
from bokeh.io import output_file, save
from bokeh.models import ColumnDataSource, OpenURL, Range1d, TapTool
from bokeh.plotting import figure

from janelia_emrp.render.web_service_request import RenderRequest


logger = logging.getLogger(__name__)

Tile = namedtuple("Tile", ["tile_id", "z", "image_url"])


def fetch_tiles(render_request: RenderRequest, stack: str) -> list[Tile]:
    """Load tile specs for the stack and build lightweight descriptors."""
    # Load all z values for the stack
    z_values = render_request.get_z_values(stack)
    z_values = z_values[:10]  # TODO: remove limit after initial testing

    # Request tile specs for each z value
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
                logger.warning("Missing expected field in tile spec at z=%s: %s", z, exc)
                continue

            tiles.append(tile)

    return tiles


def aggregate_metadata(tiles: list[Tile]) -> None:
    """Aggregate metadata from HDF5 datasets into a DataFrame."""
    metadata_rows = []
    for tile in tiles:
        print(tile.image_url)
        try:
            metadata = load_hdf5_metadata(tile.image_url)
            metadata["z"] = tile.z
        except (RuntimeError, FileNotFoundError, KeyError, ValueError, OSError) as exc:
            logger.warning("skipping tile %s: %s", tile.tile_id, exc)
            continue

        metadata_rows.append(metadata)

    return pd.DataFrame(metadata_rows)


def load_hdf5_metadata(image_url: str) -> dict[str, Union[int, float]]:
    """Resolve an HDF5-backed image URL and return structural metadata."""
    # Extract the file path from the image URL
    parsed_url = urlparse(image_url)
    if parsed_url.scheme != "file":
        raise ValueError(f"unsupported URL scheme for HDF5 access: {parsed_url.scheme}")
    file_path = unquote(parsed_url.path)

    # Extract the full dataset path from the query parameters
    query_params = parse_qs(parsed_url.query)
    position_and_mipmap = query_params.get("dataSet", [None])[0]
    if position_and_mipmap is None or not position_and_mipmap.strip():
        raise ValueError(f"imageUrl {image_url} does not include a dataSet query parameter")

    # Split off and parse position
    position = position_and_mipmap.split("/")[1]
    zyx = position.split("-")
    if len(zyx) != 3:
        raise ValueError(f"unexpected tile position format in dataSet: {position_and_mipmap}")

    # Read the dataset
    with h5py.File(file_path, "r") as h5_file:
        group = h5_file[position]
        attributes = dict(group.attrs.items())

    # Extract all attributes that we're interested in
    extracted_attributes = extract_attributes_of_interest(attributes)
    extracted_attributes["tile_x"] = int(zyx[2])
    extracted_attributes["tile_y"] = int(zyx[1])

    return extracted_attributes


def extract_attributes_of_interest(all_attributes: dict[str, Any]) -> dict[str, float]:
    """Hand-crafted extraction of selected attributes from HDF5 group attributes."""
    attributes_of_interest = {}

    # Easy attributes first
    for key in ["SEMStiX", "SEMStiY", "SEMShiftX", "SEMShiftY", "Temperature"]:
        attributes_of_interest[key] = float(all_attributes.get(key, "nan"))

    return attributes_of_interest


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
            print(
                f"Attribute '{attribute}' not found in dataframe; skipping plot generation."
            )
            continue

        attribute_df = (
            dataframe[["z", "image_url", attribute]].dropna().sort_values("z")
        )
        if attribute_df.empty:
            print(
                f"No valid values for attribute '{attribute}'; skipping plot generation."
            )
            continue

        z_values = attribute_df["z"].tolist()
        attr_values = attribute_df[attribute].tolist()
        image_urls = attribute_df["image_url"].tolist()

        slope, intercept, low_slope, high_slope = stats.theilslopes(z_values, attr_values)

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

        source = ColumnDataSource(
            data=dict(z=z_values, value=attr_values, url=image_urls)
        )
        regression_source = ColumnDataSource(
            data=dict(z=regression_x, value=regression_y)
        )

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

        plot.circle(
            source=source, x="z", y="value", size=6, line_color="navy", fill_alpha=0.6
        )
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
        help="Directory where HTML files for plots will be written.",
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] = None) -> None:
    """Main entry point for CLI."""
    if argv is None:
        argv = sys.argv[1:]
    args = parse_args(argv)

    # Get tile specs for the stack
    render_request = RenderRequest(
        host=args.base_data_url,
        owner=args.owner,
        project=args.project,
    )
    tiles = fetch_tiles(render_request, args.stack)

    # Load and aggregate metadata from the HDF5 datasets
    metadata = aggregate_metadata(tiles)
    print(metadata)

    # Generate plots for selected attributes

if __name__ == "__main__":
    # main()
    main(
        [
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
        ]
    )
