import argparse
from dataclasses import dataclass
import logging
import sys
import json
from collections import namedtuple
from pathlib import Path
from typing import Any, Sequence, Union
import urllib.parse as urlparse

import h5py
import pandas as pd
from scipy import stats
from bokeh.io import output_file, save
from bokeh.models import ColumnDataSource, OpenURL, Range1d, TapTool
from bokeh.plotting import figure

from janelia_emrp.render.web_service_request import RenderRequest


logger = logging.getLogger(__name__)

Tile = namedtuple("Tile", ["tile_id", "z", "image_url"])


# Manually curated list of plot instructions for all known properties
@dataclass(frozen=True)
class PlotSpec:
    """Specification for how to plot a property over z."""
    plot: bool = True
    constant: bool = False
    per_tile: bool = False
    regression: bool = True
    unit: str = ""


IGNORED = PlotSpec(plot=False)
PLOT_INSTRUCTIONS: dict[str, PlotSpec] = {
    "z": IGNORED,
    "tile_x": IGNORED,
    "tile_y": IGNORED,
    "AI1": IGNORED,
    "AI2": IGNORED,
    "AI3": IGNORED,
    "AI4": IGNORED,
    "BeamDump1I": PlotSpec(),
    "BeamDump2I": PlotSpec(),
    "BrightnessA": PlotSpec(constant=True),
    "BrightnessB": PlotSpec(constant=True),
    "ChamVac": PlotSpec(),
    "ChanNum": IGNORED,
    "ContrastA": PlotSpec(constant=True),
    "ContrastB": PlotSpec(constant=True),
    "DecimatingFactor": IGNORED,
    "DetA": PlotSpec(constant=True),
    "DetB": PlotSpec(constant=True),
    "DetC": IGNORED,
    "DetD": IGNORED,
    "Detmax": IGNORED,
    "Detmin": IGNORED,
    "EHT": PlotSpec(constant=True),
    "EightBit": PlotSpec(constant=True),
    "FIBAlnX": PlotSpec(),
    "FIBAlnY": PlotSpec(),
    "FIBCurr": PlotSpec(),
    "FIBFOV": PlotSpec(constant=True),
    "FIBFocus": PlotSpec(),
    "FIBProb": PlotSpec(constant=True),
    "FIBRot": PlotSpec(constant=True),
    "FIBShiftX": PlotSpec(),
    "FIBShiftY": PlotSpec(),
    "FIBSliceNum": IGNORED,
    "FIBSpecimenI": IGNORED,
    "FIBStiX": PlotSpec(per_tile=True),
    "FIBStiY": PlotSpec(per_tile=True),
    "FaradayCupI": PlotSpec(),
    "FileLength": IGNORED,
    "FileMagicNum": IGNORED,
    "FileType": IGNORED,
    "FileVersion": IGNORED,
    "FirstX": IGNORED,
    "FirstY": IGNORED,
    "FocusIndex": PlotSpec(),
    "FramelineRampdownRatio": IGNORED,
    "GunVac": PlotSpec(),
    "HighCurrent": IGNORED,
    "MachineID": PlotSpec(constant=True),
    "Mag": PlotSpec(constant=True),
    "MillingI": PlotSpec(),
    "MillingLineTime": PlotSpec(),
    "MillingLinesPerImage": PlotSpec(constant=True),
    "MillingPIDD": IGNORED,
    "MillingPIDI": IGNORED,
    "MillingPIDMeasured": IGNORED,
    "MillingPIDOn": IGNORED,
    "MillingPIDP": IGNORED,
    "MillingPIDTarget": IGNORED,
    "MillingPIDTargetSlope": IGNORED,
    "MillingULAng": IGNORED,
    "MillingURAng": IGNORED,
    "MillingXResolution": PlotSpec(constant=True),
    "MillingXSize": PlotSpec(constant=True),
    "MillingYResolution": PlotSpec(constant=True),
    "MillingYSize": PlotSpec(constant=True),
    "MillingYVoltage": PlotSpec(constant=True),
    "Mode": IGNORED,
    "Notes": PlotSpec(constant=True),
    "Oversampling": PlotSpec(constant=True),
    "PixelSize": PlotSpec(constant=True),
    "Restart": PlotSpec(),
    "SEMAlnX": IGNORED,
    "SEMAlnY": IGNORED,
    "SEMApr": PlotSpec(constant=True),
    "SEMCurr": PlotSpec(constant=True),
    "SEMRot": PlotSpec(constant=True),
    "SEMShiftX": PlotSpec(constant=True),
    "SEMShiftY": PlotSpec(constant=True),
    "SEMSpecimenI": IGNORED,
    "SEMSpecimenICurrent": PlotSpec(),
    "SEMStiX": PlotSpec(per_tile=True),
    "SEMStiY": PlotSpec(per_tile=True),
    "SWdate": IGNORED,
    "SampleID": PlotSpec(constant=True),
    "Scaling": IGNORED,
    "ScanRate": PlotSpec(),
    "StageM": IGNORED,
    "StageMove": IGNORED,
    "StageR": IGNORED,
    "StageT": IGNORED,
    "StageX": PlotSpec(),
    "StageY": PlotSpec(),
    "StageZ": PlotSpec(),
    "Temperature": PlotSpec(),
    "TimeStep": IGNORED,
    "WD": PlotSpec(),
    "XResolution": PlotSpec(),
    "Xmax": IGNORED,
    "Xmin": IGNORED,
    "YResolution": PlotSpec(),
    "ZeissScanSpeed": PlotSpec(constant=True),
    "dat_file_name": PlotSpec(constant=True),
}


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
        plot_spec = PLOT_INSTRUCTIONS.get(key, IGNORED)
        if not plot_spec.plot:
            continue

        try:
            attributes_of_interest[key] = float(value)
        except (ValueError, TypeError):
            attributes_of_interest[key] = value  # Keep as is if conversion fails

    return attributes_of_interest


def generate_plots(
    render_request: RenderRequest, stack: str, dataframe: pd.DataFrame, output_dir: Path
) -> None:
    """Generate Bokeh plots for selected attributes over z."""
    output_dir.mkdir(parents=True, exist_ok=True)
    z_layer_properties = [
        column
        for column, plot_spec in PLOT_INSTRUCTIONS.items()
        if plot_spec.plot and not plot_spec.constant and not plot_spec.per_tile
    ]

    tap_url = create_tap_link(render_request, stack)

    for attribute in z_layer_properties:
        attribute_frame = dataframe[["z", attribute]].dropna().sort_values(by="z")
        if attribute_frame.empty:
            logger.info("No data to plot for attribute %s", attribute)
            continue

        z_values = attribute_frame["z"].tolist()
        attr_values = attribute_frame[attribute].tolist()
        if not z_values or not attr_values:
            logger.info("Skipping attribute %s due to missing values", attribute)
            continue

        # Determine axes ranges
        x_min, x_max = range_with_padding(z_values, padding_fraction=0.05)
        y_min, y_max = range_with_padding(attr_values, padding_fraction=0.05)

        # Create plot with neuroglancer links on click
        tooltips = [("z", "@z"), ("value", "@value")]
        plot = figure(
            title=attribute,
            x_axis_label="z",
            y_axis_label=attribute,
            tooltips=tooltips,
            tools="tap,pan,box_zoom,wheel_zoom,save,reset",
            plot_width=2400,
            plot_height=400,
            x_range=Range1d(x_min, x_max),
            y_range=Range1d(y_min, y_max),
        )
        tap_tool = plot.select_one(TapTool)
        tap_tool.callback = OpenURL(url=tap_url)

        # Scatter plot of data
        source = ColumnDataSource({"z": z_values, "value": attr_values})
        plot.circle(
            source=source,
            x="z",
            y="value",
            size=6,
            line_color="navy",
            fill_alpha=0.6
        )

        # Add robust linear regression line
        if len(z_values) >= 2:
            slope, intercept, _, _ = stats.theilslopes(attr_values, z_values)
            regression_x = [x_min, x_max]
            regression_y = [slope * x + intercept for x in regression_x]
            regression_source = ColumnDataSource({"z": regression_x, "value": regression_y})

            plot.line(
                source=regression_source,
                x="z",
                y="value",
                line_width=2,
                line_color="tomato",
                legend_label=f"Linear regression: y={slope:.3f}x+{intercept:.3f}",
            )

        if plot.legend:
            plot.legend.location = "top_left"
            plot.legend.click_policy = "hide"

        # Save plot to HTML file
        output_path = output_dir / f"{attribute}_over_z.html"
        output_file(str(output_path), title=attribute)
        save(plot)
        logger.info("Wrote %s", output_path)


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

    # Generate plots for selected attributes
    generate_plots(render_request, args.stack, metadata, Path(args.output_dir))


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
