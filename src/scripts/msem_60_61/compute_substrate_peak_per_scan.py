"""Per-slab substrate % inside the ROI vs scan, with peak/cutoff detection.

ROI = sfovs with signed distance_roi <= 0 (negative is inside).

Needs these datasets in each xlog.zarr: substrate, distance_roi, scan, id_serial.
"""
import argparse
import json
import warnings
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import zarr
from matplotlib.backends.backend_pdf import PdfPages

ROWS, COLS = 4, 5  # subplots per PDF page


def analyze(path, wafer, threshold):
    """Mean substrate % over ROI sfovs per (scan, slab), plus peak/cutoff per slab."""
    arr = lambda name: zarr.open_array(f"{path}/{name}", mode="r")
    sub = arr("substrate")
    in_roi = arr("distance_roi")[:] <= 0  # (slab, mfov, sfov)
    scans = arr("scan")[:]  # real scan numbers; they start at -5, so index 5 == scan 0
    id_serial = arr("id_serial")[:]  # id_serial renumbers the slabs
    n_scan, n_slab = sub.shape[:2]

    curves = np.full((n_scan, n_slab), np.nan)  # read in slab-chunk blocks; substrate is big
    for lo in range(0, n_slab, sub.chunks[1]):
        hi = min(lo + sub.chunks[1], n_slab)
        s = np.where(in_roi[None, lo:hi], sub[:, lo:hi], np.nan)
        with warnings.catch_warnings():  # all-NaN slabs
            warnings.simplefilter("ignore", RuntimeWarning)
            curves[:, lo:hi] = np.nanmean(s.reshape(n_scan, hi - lo, -1), axis=2)

    valid = np.isfinite(curves)
    n_layers = valid.sum(0)
    slabs = sorted((i for i in range(n_slab) if n_layers[i]), key=lambda i: id_serial[i])
    print(f"[{wafer}] {len(slabs)}/{n_slab} slabs with data, {in_roi.sum()} ROI sfovs, "
          f"{n_layers.sum()} layers")

    # cutoff = scan of the peak, but only where the peak clears the threshold
    peak_scan = np.nanargmax(np.where(valid, curves, -np.inf), axis=0)
    peak = curves[peak_scan, np.arange(n_slab)]
    has_cutoff = peak > threshold
    print(f"[{wafer}] cutoff (peak > {threshold}%) in {has_cutoff[slabs].sum()} slabs")
    below = [f"id {id_serial[i]:.0f} ({peak[i]:.1f}%)" for i in slabs if not has_cutoff[i]]
    if below:
        print(f"[{wafer}]   slabs with data but no cutoff: {', '.join(below)}")
    return dict(wafer=wafer, scans=scans, curves=curves, id_serial=id_serial, slabs=slabs,
                n_layers=n_layers, peak_scan=peak_scan, peak=peak,
                has_cutoff=has_cutoff)


def plot(pdf, r):
    for page in range(0, len(r["slabs"]), ROWS * COLS):
        fig, axes = plt.subplots(ROWS, COLS, figsize=(16, 10), sharex=True, sharey=True)
        for ax, slab in zip(axes.ravel(), r["slabs"][page : page + ROWS * COLS]):
            ax.plot(r["scans"], r["curves"][:, slab], ".-", lw=0.8, ms=3)
            ax.set_title(f"id {r['id_serial'][slab]:.0f} (slab {slab}) - "
                         f"{r['n_layers'][slab]} layers", fontsize=8)
            if r["has_cutoff"][slab]:
                x, y = r["scans"][r["peak_scan"][slab]], r["peak"][slab]
                ax.plot(x, y, "o", color="red", ms=5)
                ax.annotate(f" scan {r['scans'][r['peak_scan'][slab]]}", (x, y),
                            color="red", fontsize=8, va="center")
        for ax in axes.ravel()[len(r["slabs"]) - page :]:
            ax.axis("off")
        fig.suptitle(f"wafer {r['wafer'][1:]}")
        fig.supxlabel("scan")
        fig.supylabel("substrate in ROI [%]")
        fig.tight_layout()
        pdf.savefig(fig)
        plt.close(fig)


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--w60-xlog", type=Path, help="path to the wafer 60 xlog.zarr")
    p.add_argument("--w61-xlog", type=Path, help="path to the wafer 61 xlog.zarr")
    p.add_argument("--plot-out", type=Path, nargs="?", const=Path("substrate_in_roi.pdf"),
                   help="write the per-slab PDF here (bare flag: ./substrate_in_roi.pdf); "
                        "omit to skip plotting")
    p.add_argument("--json-out", type=Path, nargs="?",
                   const=Path("hess_wafers_60_61.peak_scan.json"),
                   help="write peak scan per slab here (bare flag: "
                        "./hess_wafers_60_61.peak_scan.json); omit to skip")
    p.add_argument("--threshold", type=float, default=30,
                   help="%% substrate; peaks below this are not a cutoff (default: %(default)s)")
    args = p.parse_args()

    paths = {w: q for w, q in (("w60", args.w60_xlog), ("w61", args.w61_xlog)) if q}
    if not paths:
        p.error("give --w60-xlog and/or --w61-xlog")
    results = [analyze(q, w, args.threshold) for w, q in paths.items()]

    if args.plot_out:
        with PdfPages(args.plot_out) as pdf:
            for r in results:
                plot(pdf, r)
        print("wrote", args.plot_out)
    if args.json_out:
        # value = the `scan` number of the peak
        projects = {}  # slabs grouped by decade of id_serial
        for r in results:
            for i in r["slabs"]:
                sid = int(r["id_serial"][i])
                lo = sid // 10 * 10
                proj = f"{r['wafer']}_serial_{lo:03d}_to_{lo + 9:03d}"
                projects.setdefault(proj, {})[f"{r['wafer']}_s{sid:03d}"] = (
                    int(r["scans"][r["peak_scan"][i]]) if r["has_cutoff"][i] else None)
        args.json_out.write_text(json.dumps(
            {"owner": args.json_out.name.split(".")[0],
             "project_to_slab_peak_scan": projects}, indent=2))
        print("wrote", args.json_out)


if __name__ == "__main__":
    main()

