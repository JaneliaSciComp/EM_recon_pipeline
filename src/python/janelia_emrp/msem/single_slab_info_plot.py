import sys
from pathlib import Path
from typing import Iterable, Collection

from matplotlib import pyplot as plt

from janelia_emrp.msem.single_slab_info import ScanMfov, load_single_slab_info


def plot_single_slab_mfovs(
        scan_mfovs: Iterable[ScanMfov],
        *,
        mfov_only: Collection[int] | None = None,
        min_sfov_number: int = 0,
        annotate: bool = False,
        center_fontsize: int = 11,
        show: bool = True,
        save_path: str | Path | None = None,
) -> None:
    mfov_set = set(mfov_only) if mfov_only is not None else None
    scan_mfovs = [sm for sm in scan_mfovs if (mfov_set is None or sm.mfov_number in mfov_set)]
    if not scan_mfovs:
        raise ValueError("No ScanMfov to plot after applying filters")

    fig, ax = plt.subplots(constrained_layout=True)

    overall_xs: list[float] = []
    overall_ys: list[float] = []
    added_sfov_legend = False

    for sm in scan_mfovs:
        # Filter and coerce to float to avoid unsigned/categorical surprises
        pts = [p for p in sm.sfov_list if p.sfov_number >= min_sfov_number]
        if pts:
            xs = [float(p.x) for p in pts]
            ys = [float(p.y) for p in pts]
            ax.scatter(xs, ys, s=20, color="blue",
                       label="SFOVs" if not added_sfov_legend else None)
            added_sfov_legend = True
            overall_xs.extend(xs)
            overall_ys.extend(ys)

        # centers (also coerced to float)
        cx = float(sm.center_x)
        cy = float(sm.center_y)
        overall_xs.append(cx)
        overall_ys.append(cy)
        ax.text(cx, cy, str(sm.mfov_number),
                color="red", fontsize=center_fontsize,
                ha="center", va="center", fontweight="bold", zorder=3)

        if annotate and pts:
            for p in pts:
                ax.annotate(str(p.sfov_number), (float(p.x), float(p.y)),
                            xytext=(3, 3), textcoords="offset points", fontsize=8)

    print("y sample:", overall_ys[:10], "min:", min(overall_ys), "max:", max(overall_ys))

    # Exact limits; flip Y (max at bottom, min at top) without changing data
    y_min, y_max = min(overall_ys), max(overall_ys)
    x_min, x_max = min(overall_xs), max(overall_xs)
    ax.set_xlim(x_min, x_max)
    ax.set_ylim(y_max, y_min)  # flip Y by swapping limits

    ax.set_aspect("equal", adjustable="box")
    ax.set_title("SFOV points across multiple MFOVs")
    ax.set_xlabel("x")
    ax.set_ylabel("y")
    if added_sfov_legend:
        ax.legend()

    if save_path is not None:
        fig.savefig(save_path, dpi=150, bbox_inches="tight")
    if show:
        plt.show()
    else:
        plt.close(fig)

def main(argv: list[str]):
    json_path = Path(argv[1])
    slab_info = load_single_slab_info(json_path)
    scan_to_mfov_list = slab_info.map_sfov_info_list()
    sorted_scan_list = sorted(scan_to_mfov_list.keys())
    for scan in sorted_scan_list:
        mfov_list = scan_to_mfov_list[scan]
        plot_single_slab_mfovs(scan_mfovs=mfov_list,
                               min_sfov_number=62,  # 0, 62, 80
                               mfov_only=None) # [9]  None


if __name__ == '__main__':
    if len(sys.argv) == 2:
        main(sys.argv)
    else:
        print("USAGE: single_slab_info_plot.py <json_path>")
        # main(["go", "/nrs/hess/Hayworth/DATA_Wafer66_ForRenderTest/full_image_coordinates.txt.json"])
