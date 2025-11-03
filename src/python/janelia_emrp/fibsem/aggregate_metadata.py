import argparse
from enum import Enum
import html
import logging
import json
from collections import namedtuple
from pathlib import Path
from typing import Any, Sequence, Union
import urllib.parse as urlparse

import h5py
import pandas as pd
from bokeh.io import output_file, save
from bokeh.layouts import column, Column
from bokeh.models import ColumnDataSource, Div, LinearAxis, OpenURL, Range1d, TapTool
from bokeh.plotting import figure

from janelia_emrp.render.web_service_request import RenderRequest


logger = logging.getLogger(__name__)

Tile = namedtuple("Tile", ["tile_id", "z", "image_url"])


# Manually curated list of plot instructions for all known properties
class Category(str, Enum):
    """Category of property for plotting purposes."""
    IGNORED = "ignored"          # Do not plot
    CONSTANT = "constant"        # Print as constant
    Z_LAYER = "z_layer"          # Plot over z
    PER_TILE = "per_tile"        # Plot per tile (tile_x, tile_y)


PLOT_CATEGORIES: dict[str, Category] = {
    "z": Category.IGNORED,
    "tile_x": Category.IGNORED,
    "tile_y": Category.IGNORED,
    "AI1": Category.IGNORED,
    "AI2": Category.IGNORED,
    "AI3": Category.IGNORED,
    "AI4": Category.IGNORED,
    "BeamDump1I": Category.Z_LAYER,
    "BeamDump2I": Category.Z_LAYER,
    "BrightnessA": Category.CONSTANT,
    "BrightnessB": Category.CONSTANT,
    "ChamVac": Category.PER_TILE,
    "ChanNum": Category.IGNORED,
    "ContrastA": Category.CONSTANT,
    "ContrastB": Category.CONSTANT,
    "DecimatingFactor": Category.IGNORED,
    "DetA": Category.CONSTANT,
    "DetB": Category.CONSTANT,
    "DetC": Category.IGNORED,
    "DetD": Category.IGNORED,
    "Detmax": Category.IGNORED,
    "Detmin": Category.IGNORED,
    "EHT": Category.CONSTANT,
    "EightBit": Category.CONSTANT,
    "FIBAlnX": Category.Z_LAYER,
    "FIBAlnY": Category.Z_LAYER,
    "FIBCurr": Category.PER_TILE,
    "FIBFOV": Category.CONSTANT,
    "FIBFocus": Category.Z_LAYER,
    "FIBProb": Category.CONSTANT,
    "FIBRot": Category.CONSTANT,
    "FIBShiftX": Category.Z_LAYER,
    "FIBShiftY": Category.Z_LAYER,
    "FIBSliceNum": Category.IGNORED,
    "FIBSpecimenI": Category.IGNORED,
    "FIBStiX": Category.Z_LAYER,
    "FIBStiY": Category.Z_LAYER,
    "FaradayCupI": Category.Z_LAYER,
    "FileLength": Category.IGNORED,
    "FileMagicNum": Category.IGNORED,
    "FileType": Category.IGNORED,
    "FileVersion": Category.IGNORED,
    "FirstX": Category.IGNORED,
    "FirstY": Category.IGNORED,
    "FocusIndex": Category.PER_TILE,
    "FramelineRampdownRatio": Category.IGNORED,
    "GunVac": Category.Z_LAYER,
    "HighCurrent": Category.IGNORED,
    "MachineID": Category.CONSTANT,
    "Mag": Category.CONSTANT,
    "MillingI": Category.Z_LAYER,
    "MillingLineTime": Category.Z_LAYER,
    "MillingLinesPerImage": Category.CONSTANT,
    "MillingPIDD": Category.IGNORED,
    "MillingPIDI": Category.IGNORED,
    "MillingPIDMeasured": Category.IGNORED,
    "MillingPIDOn": Category.IGNORED,
    "MillingPIDP": Category.IGNORED,
    "MillingPIDTarget": Category.IGNORED,
    "MillingPIDTargetSlope": Category.IGNORED,
    "MillingULAng": Category.IGNORED,
    "MillingURAng": Category.IGNORED,
    "MillingXResolution": Category.CONSTANT,
    "MillingXSize": Category.CONSTANT,
    "MillingYResolution": Category.CONSTANT,
    "MillingYSize": Category.CONSTANT,
    "MillingYVoltage": Category.Z_LAYER,
    "Mode": Category.IGNORED,
    "Notes": Category.CONSTANT,
    "Oversampling": Category.CONSTANT,
    "PixelSize": Category.CONSTANT,
    "Restart": Category.Z_LAYER,
    "SEMAlnX": Category.IGNORED,
    "SEMAlnY": Category.IGNORED,
    "SEMApr": Category.CONSTANT,
    "SEMCurr": Category.CONSTANT,
    "SEMRot": Category.CONSTANT,
    "SEMShiftX": Category.CONSTANT,
    "SEMShiftY": Category.CONSTANT,
    "SEMSpecimenI": Category.IGNORED,
    "SEMSpecimenICurrent": Category.PER_TILE,
    "SEMStiX": Category.PER_TILE,
    "SEMStiY": Category.PER_TILE,
    "SWdate": Category.IGNORED,
    "SampleID": Category.CONSTANT,
    "Scaling": Category.IGNORED,
    "ScanRate": Category.Z_LAYER,
    "StageM": Category.IGNORED,
    "StageMove": Category.IGNORED,
    "StageR": Category.IGNORED,
    "StageT": Category.IGNORED,
    "StageX": Category.Z_LAYER,
    "StageY": Category.Z_LAYER,
    "StageZ": Category.Z_LAYER,
    "Temperature": Category.Z_LAYER,
    "TimeStep": Category.IGNORED,
    "WD": Category.PER_TILE,
    "XResolution": Category.Z_LAYER,
    "Xmax": Category.IGNORED,
    "Xmin": Category.IGNORED,
    "YResolution": Category.Z_LAYER,
    "ZeissScanSpeed": Category.CONSTANT,
    "dat_file_name": Category.IGNORED,
}


PAIRS_TO_PLOT = [
    # (attribute_x, attribute_y)
    ("BeamDump1I", "BeamDump2I"),
    ("FIBAlnX", "FIBAlnY"),
    ("FIBStiX", "FIBStiY"),
    ("SEMStiX", "SEMStiY"),
    ("XResolution", "YResolution"),
]


def main() -> None:
    """Main entry point for CLI."""
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
    args = parser.parse_args()

    # Get tile specs for the stack
    render_request = RenderRequest(
        host=args.base_data_url,
        owner=args.owner,
        project=args.project,
    )
    tiles = fetch_tiles(render_request, args.stack)
    logger.info("Fetched %d tiles for stack %s", len(tiles), args.stack)

    # Load and aggregate metadata from the HDF5 datasets
    metadata = aggregate_metadata(tiles)
    logger.info("Aggregated metadata for %d tiles", len(metadata))

    # Generate plots for selected attributes
    output_dir = Path(args.output_dir)
    plotted_attributes, paired_plots = generate_plots(
        render_request, args.stack, metadata, output_dir
    )
    logger.info("Wrote plots to %s", output_dir)

    # Create a landing page summarizing constants and linking to plots
    create_landing_page(
        render_request,
        args.stack,
        metadata,
        plotted_attributes,
        paired_plots,
        output_dir,
    )
    logger.info("Wrote landing page to %s", output_dir / "index.html")


def fetch_tiles(render_request: RenderRequest, stack: str) -> list[Tile]:
    """Load tile specs for the stack and build lightweight descriptors."""
    # Load all z values for the stack
    z_values = render_request.get_z_values(stack)

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
    parsed_url = urlparse.urlparse(image_url)
    if parsed_url.scheme != "file":
        raise ValueError(f"unsupported URL scheme for HDF5 access: {parsed_url.scheme}")
    file_path = urlparse.unquote(parsed_url.path)

    # Extract the full dataset path from the query parameters
    query_params = urlparse.parse_qs(parsed_url.query)
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

    # Extract all non-ignored attributes and convert to float if possible
    for key, value in all_attributes.items():
        category = PLOT_CATEGORIES.get(key, Category.IGNORED)
        if category == Category.IGNORED:
            continue

        try:
            attributes_of_interest[key] = float(value)
        except (ValueError, TypeError):
            attributes_of_interest[key] = value  # Keep as is if conversion fails

    return attributes_of_interest


def generate_plots(
    render_request: RenderRequest, stack: str, dataframe: pd.DataFrame, output_dir: Path
) -> tuple[list[tuple[str, Path]], list[tuple[str, Path]]]:
    """Generate Bokeh plots for selected attributes over z."""
    output_dir.mkdir(parents=True, exist_ok=True)
    tap_url = create_tap_link(render_request, stack)

    plotted_attributes: list[tuple[str, Path]] = []
    paired_plots: list[tuple[str, Path]] = []
    sorted_data = dataframe.sort_values(by=["tile_x", "tile_y", "z"])
    for attribute, category in PLOT_CATEGORIES.items():
        if category not in (Category.Z_LAYER, Category.PER_TILE):
            continue

        # Extract data for the attribute
        if attribute not in dataframe.columns:
            continue

        # Create plot with neuroglancer links on click
        layout = plot_values_over_z(sorted_data, attribute, tap_url, category == Category.PER_TILE)

        # Save plot to HTML file
        output_path = output_dir / f"{attribute}_over_z.html"
        output_file(str(output_path), title=attribute)
        save(layout)
        logger.info("Wrote %s", output_path)
        plotted_attributes.append((attribute, output_path))

    for attribute_x, attribute_y in PAIRS_TO_PLOT:
        if attribute_x not in dataframe.columns or attribute_y not in dataframe.columns:
            continue

        category_x = PLOT_CATEGORIES.get(attribute_x, Category.IGNORED)
        category_y = PLOT_CATEGORIES.get(attribute_y, Category.IGNORED)
        if category_x == Category.IGNORED or category_y == Category.IGNORED:
            continue

        per_tile = Category.PER_TILE in (category_x, category_y)
        layout = plot_attribute_pair_over_z(
            sorted_data, attribute_x, attribute_y, tap_url, per_tile
        )
        output_path = output_dir / f"{attribute_x}_and_{attribute_y}_over_z.html"
        output_file(str(output_path), title=f"{attribute_x} vs {attribute_y}")
        save(layout)
        logger.info("Wrote %s", output_path)
        paired_plots.append((f"{attribute_x} & {attribute_y}", output_path))

    return plotted_attributes, paired_plots


def plot_values_over_z(data: pd.DataFrame, attribute: str, tap_url: str, per_tile: bool) -> Column:
    """Placeholder for future plotting function."""
    # Extract data for the attribute
    data = data[["tile_x", "tile_y", "z", attribute]]
    grouped_by_tile = list(data.dropna().groupby(["tile_x", "tile_y"]))

    if per_tile:
        plot_specs = [
            (f"Tile x={tile_x}, y={tile_y}", group)
            for (tile_x, tile_y), group in grouped_by_tile
        ]
    else:
        first_group = grouped_by_tile[0][1]
        plot_specs = [("", first_group)]

    figures = []
    for title, attribute_frame in plot_specs:
        # Determine axes ranges
        z_values = attribute_frame["z"].tolist()
        attr_values = attribute_frame[attribute].tolist()
        x_min, x_max = range_with_padding(z_values, padding_fraction=0.05)
        y_min, y_max = range_with_padding(attr_values, padding_fraction=0.05)

        # Create plot with neuroglancer links on click
        tooltips = [("z", "@z"), ("value", "@value")]
        fig = figure(
            title=title,
            x_axis_label="z",
            y_axis_label=attribute,
            tooltips=tooltips,
            tools="tap,pan,box_zoom,wheel_zoom,save,reset",
            plot_width=2400,
            plot_height=400,
            x_range=Range1d(x_min, x_max),
            y_range=Range1d(y_min, y_max),
        )

        # Scatter plot of data
        source = ColumnDataSource({"z": z_values, "value": attr_values})
        circle_renderer = fig.circle(
            source=source,
            x="z",
            y="value",
            size=6,
            line_color="navy",
            fill_alpha=0.6
        )

        # Add clickable links to neuroglancer
        tap_tool = fig.select_one(TapTool)
        if tap_tool is not None:
            tap_tool.callback = OpenURL(url=tap_url)
            tap_tool.renderers = [circle_renderer]

        figures.append(fig)

    return column(
        Div(text=f"<h1>{html.escape(attribute)}</h1>"),
        *figures,
        sizing_mode="stretch_width",
    )


def plot_attribute_pair_over_z(
    data: pd.DataFrame,
    attribute_x: str,
    attribute_y: str,
    tap_url: str,
    per_tile: bool,
) -> Column:
    """Create paired attribute plots with synchronized dual y-axes."""
    required_columns = ["tile_x", "tile_y", "z", attribute_x, attribute_y]
    title = f"<h1>{html.escape(attribute_x)} &amp; {html.escape(attribute_y)}</h1>"
    if not all(column in data.columns for column in required_columns):
        return column(Div(text=title))

    pair_data = data[required_columns].dropna(subset=[attribute_x, attribute_y])
    grouped_by_tile = list(pair_data.groupby(["tile_x", "tile_y"]))

    if not grouped_by_tile:
        return column(Div(text=title + "<p>No data available.</p>"))

    if per_tile:
        plot_specs = [
            (f"Tile x={tile_x}, y={tile_y}", group)
            for (tile_x, tile_y), group in grouped_by_tile
        ]
    else:
        first_group = grouped_by_tile[0][1]
        plot_specs = [("", first_group)]

    figures = []
    for title, attribute_frame in plot_specs:
        # Determine axes ranges
        z_values = attribute_frame["z"].tolist()
        values_x = attribute_frame[attribute_x].tolist()
        values_y = attribute_frame[attribute_y].tolist()
        combined_values = values_x + values_y
        x_min, x_max = range_with_padding(z_values, padding_fraction=0.05)
        y_min, y_max = range_with_padding(combined_values, padding_fraction=0.05)

        # Create plot with neuroglancer links on click
        fig = figure(
            title=title,
            x_axis_label="z",
            y_axis_label=attribute_x,
            tooltips=[("z", "@z"), ("value", "@value")],
            tools="tap,pan,box_zoom,wheel_zoom,save,reset",
            plot_width=2400,
            plot_height=400,
            x_range=Range1d(x_min, x_max),
            y_range=Range1d(y_min, y_max),
        )

        # Scatter plot of data (left axis)
        left_source = ColumnDataSource({"z": z_values, "value": values_x})
        left_renderer = fig.circle(
            source=left_source,
            x="z",
            y="value",
            size=6,
            line_color="navy",
            fill_color="navy",
            fill_alpha=0.6,
            legend_label=attribute_x,
        )

        # Scatter plot of data (right axis)
        right_range_name = "right_axis"
        fig.extra_y_ranges = {right_range_name: Range1d(y_min, y_max)}
        fig.add_layout(LinearAxis(y_range_name=right_range_name, axis_label=attribute_y), "right")
        right_source = ColumnDataSource({"z": z_values, "value": values_y})
        right_renderer = fig.square(
            source=right_source,
            x="z",
            y="value",
            size=6,
            line_color="firebrick",
            fill_color="firebrick",
            fill_alpha=0.6,
            y_range_name=right_range_name,
            legend_label=attribute_y,
        )

        # Add clickable links to neuroglancer
        tap_tool = fig.select_one(TapTool)
        if tap_tool is not None:
            tap_tool.callback = OpenURL(url=tap_url)
            tap_tool.renderers = [left_renderer, right_renderer]

        fig.legend.location = "top_left"
        figures.append(fig)

    return column(
        Div(text=f"<h1>{title}</h1>"),
        *figures,
        sizing_mode="stretch_width",
    )


def create_tap_link(
    render_request: RenderRequest,
    stack: str,
    cross_section_scale: int = 16,
    projection_scale: int = 32768,
) -> str:
    """Create a neuroglancer link pointing to the specified stack."""
    owner = render_request.owner
    project = render_request.project

    # Fetch stack metadata for resolution and bounds
    stack_metadata = render_request.get_stack_metadata(stack)
    bounds = stack_metadata["stats"]["stackBounds"]
    stack_metadata = stack_metadata["currentVersion"]

    # Build the neuroglancer state and encode it for URL inclusion
    ng_source_url = f"render://http://renderer.int.janelia.org:8080/{owner}/{project}/{stack}"
    position_to_replace = 0.12345678987654321
    ng_state = {
        "dimensions": {
            "x": [stack_metadata["stackResolutionX"], "nm"],
            "y": [stack_metadata["stackResolutionY"], "nm"],
            "z": [stack_metadata["stackResolutionZ"], "nm"],
        },
        "position": [position_to_replace],
        "crossSectionScale": cross_section_scale,
        "projectionScale": projection_scale,
        "layers": [
            {
                "type": "image",
                "source": {
                    "url": ng_source_url,
                    "subsources": {"default": True, "bounds": True},
                    "enableDefaultSubsources": False,
                },
                "tab": "source",
                "name": stack,
            }
        ],
        "selectedLayer": {"layer": stack},
        "layout": "xy",
    }
    encoded_state = urlparse.quote(json.dumps(ng_state, separators=(",", ":")))

    # Replace the position placeholder with actual x,y center and @x for z (substituted by bokeh)
    # This needs to be done after URL encoding to avoid encoding the '@' character
    center_x = int(bounds["minX"] + (bounds["maxX"] - bounds["minX"]) / 2)
    center_y = int(bounds["minY"] + (bounds["maxY"] - bounds["minY"]) / 2)
    encoded_state = encoded_state.replace(str(position_to_replace), f"{center_x},{center_y},1")

    return f"http://renderer.int.janelia.org:8080/ng/#!{encoded_state}"


def range_with_padding(
    values: Sequence[float], padding_fraction: float = 0.1
) -> tuple[float, float]:
    """Compute min and max of a sequence with padding."""
    if not values:
        raise ValueError("cannot compute range of empty sequence")

    min_value = min(values)
    max_value = max(values)
    if min_value == max_value:
        padding = 1 if min_value == 0 else abs(min_value) * 0.1
    else:
        padding = (max_value - min_value) * padding_fraction

    return (min_value - padding, max_value + padding)


def create_landing_page(
    render_request: RenderRequest,
    stack: str,
    dataframe: pd.DataFrame,
    plotted_attributes: list[tuple[str, Path]],
    paired_plots: list[tuple[str, Path]],
    output_path: Path,
) -> None:
    """Write an HTML landing page summarizing constants and linking to plots."""
    constant_properties = [
        column
        for column, category in PLOT_CATEGORIES.items()
        if category == Category.CONSTANT
    ]
    constant_entries = collect_constant_entries(dataframe, constant_properties)
    output_path = output_path / "index.html"
    title = render_request.project + " metadata overview"
    owner = html.escape(render_request.owner)
    project = html.escape(render_request.project)
    stack_name = html.escape(stack)

    lines = [
        "<!DOCTYPE html>",
        "<html lang=\"en\">",
        "<head>",
        "<meta charset=\"utf-8\">",
        f"<title>{html.escape(title)}</title>",
        "<style>",
        "body { font-family: Arial, sans-serif; margin: 2rem; line-height: 1.5; }",
        "h1 { margin-bottom: 0.5rem; }",
        "h2 { margin-top: 1.5rem; }",
        "table { border-collapse: collapse; min-width: 40%; }",
        "th, td { border: 1px solid #ccc; padding: 0.4rem 0.6rem; text-align: left; }",
        "th { background-color: #f5f5f5; }",
        ".warning { color: #b44; font-size: 0.9em; margin-left: 0.4rem; }",
        "ul { padding-left: 1.2rem; }",
        ".summary-sections { display: flex; flex-wrap: wrap; gap: 2rem; align-items: flex-start; }",
        ".summary-block { flex: 1 1 320px; }",
        ".summary-block table { min-width: 100%; }",
        "</style>",
        "</head>",
        "<body>",
        f"<h1>{html.escape(title)}</h1>",
        f"<p><strong>Owner:</strong> {owner} &nbsp; <strong>Project:</strong> "
        f"{project} &nbsp; <strong>Stack:</strong> {stack_name}</p>",
    ]

    lines.append('<div class="summary-sections">')

    lines.append('<section class="summary-block constants">')
    lines.append("<h2>Dataset constants</h2>")
    lines.extend(
        [
            "<table>",
            "<thead><tr><th>Property</th><th>Value</th></tr></thead>",
            "<tbody>",
        ]
    )
    for attribute, value_text in constant_entries:
        lines.append(
            f"<tr><th>{html.escape(attribute)}</th><td>{html.escape(value_text)}</td></tr>"
        )
    lines.extend(["</tbody>", "</table>"])
    lines.append("</section>")

    lines.append('<section class="summary-block plots">')
    lines.append("<h2>Z-layer plots</h2>")
    lines.append("<ul>")
    for attribute, path in sorted(plotted_attributes, key=lambda item: item[0]):
        href = html.escape(path.name)
        label = html.escape(attribute)
        lines.append(f'<li><a href="{href}">{label}</a></li>')
    lines.append("</ul>")

    if paired_plots:
        lines.append("<h2>Paired plots</h2>")
        lines.append("<ul>")
        for attribute, path in sorted(paired_plots, key=lambda item: item[0]):
            href = html.escape(path.name)
            label = html.escape(attribute)
            lines.append(f'<li><a href="{href}">{label}</a></li>')
        lines.append("</ul>")
    lines.append("</section>")

    lines.append("</div>")

    lines.extend(["</body>", "</html>"])
    output_path.write_text("\n".join(lines), encoding="utf-8")


def collect_constant_entries(
    dataframe: pd.DataFrame, constant_properties: list[str]
) -> list[tuple[str, str]]:
    """Extract representative values for dataset-constant properties."""
    entries: list[tuple[str, str]] = []
    for attribute in constant_properties:
        if attribute not in dataframe.columns:
            continue

        series = dataframe[attribute].dropna()
        if series.empty:
            value_text = "N/A"
        else:
            value = series.iloc[0]
            normalized = value.item() if hasattr(value, "item") else value
            value_text = str(normalized)

        series_unique = series.unique()
        if len(series_unique) > 1:
            value_text += f' 🔴 WARNING: {len(series_unique)} unique values found'

        entries.append((attribute, value_text))

    return entries


if __name__ == "__main__":
    main()
