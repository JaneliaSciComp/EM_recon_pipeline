"""Assembly."""

from __future__ import annotations

import itertools
from functools import partial
from typing import TYPE_CHECKING

import matplotlib
import matplotlib.pyplot as plt
import numpy as np
from dask import bag
from distributed import Client
from janelia_emrp.msem.ingestion_ibeammsem.constant import FACTOR_THUMBNAIL, N_BEAMS
from janelia_emrp.msem.ingestion_ibeammsem.path import get_image_paths, get_slab_path
from janelia_emrp.msem.ingestion_ibeammsem.roi import get_mfovs
from janelia_emrp.msem.ingestion_ibeammsem.xdim import XDim
from janelia_emrp.msem.ingestion_ibeammsem.xvar import XVar
from matplotlib.transforms import Affine2D
from skimage.io import imread
from skimage.transform import EuclideanTransform

#matplotlib.use("tkagg")
matplotlib.use("Agg") # avoid "Cannot load backend 'tkagg' which requires the 'tk' interactive framework" error

if TYPE_CHECKING:
    from pathlib import Path

    import xarray as xr


def get_max_scans(xlog: xr.Dataset) -> int:
    """Gets the maximum number of scans.

    The xlog is conservatively over-dimensioned upfront along XDim.SCAN
        to accommodate all anticipated scans.

    The prediction of the number of scans is made by IBEAM-MSEM operators
        considering the nominal slab thickness
        and the material removal thickness at every scan.

    Note that scans with strictly negative labels exist,
        but they are internals of the IBEAM-MSEM process
        and must not be ingested.
    """
    return 1 + xlog[XDim.SCAN].max().values.item()


def get_slab_rotation(xlog: xr.Dataset, scan: int, slab: int) -> float:
    """Returns the rotation of a slab, in degrees.

    The slab rotation depends on the scan, because:
        1. the plate position changes at every scan
        2. the coordinates exposed for downstream assembly hide low-level hardware artefacts
    The scan dependency is likely negligible, but it is conceptually correct.
    """
    return 180 + xlog[XVar.ROTATION_SLAB].sel(scan=scan, slab=slab).values.item()


def get_xys_sfov_and_paths(
    xlog: xr.Dataset, scan: int, slab: int, mfov: int
) -> tuple[list[Path], np.ndarray]:
    """Paths and top-left corner coordinates of SFOVs of an MFOV in straight orientation.

    Paths:
        type UNC
        length N_BEAMS
    Coordinates:
        shape (N_BEAMS, 2)
        unit: full-resolution pixel
        orientation: original, that is, the SFOVs are "straight"
        top-left corner of the SFOVs

    To align multiple slabs with the correct offset and orientation,
        apply the slab rotation around the center (0,0).
    """
    xys_center_rotated = (
        get_xy_slab(xlog=xlog, scan=scan, slab=slab, mfovs=[mfov]).squeeze().T
    )

    xys_center_original: np.ndarray = EuclideanTransform(
        rotation=np.radians(get_slab_rotation(xlog=xlog, scan=scan, slab=slab))
    )(xys_center_rotated)
    xys_top_left_original = xys_center_original - np.array(
        [xlog[XDim.X_SFOV].size / 2, xlog[XDim.Y_SFOV].size / 2]
    )
    return get_image_paths(
        slab_path=get_slab_path(xlog=xlog, scan=scan, slab=slab),
        mfovs=[mfov],
        thumbnail=False,
    ), xys_top_left_original


def get_xy_slab(
    xlog: xr.Dataset, scan: int, slab: int, mfovs: list[int] | np.ndarray | None = None
) -> np.ndarray:
    """Returns the coordinates of the SFOV centers of a slab, in full resolution pixels.

    We recommend using these coordinates for the data ingestion.

    These coordinates hide low-level artifacts of the IBEAM-MSEM workflow:
        1. plate insertion position variability
        2. mismatch between request stage position and actual stage position
        3. internal knowledge of beam position

    The coordinates are in the local, aligned space:
        the slabs have been 3d aligned using light microscopy.
        See XVar.X.
    It is not the original orientation in which the images were acquired.
    In this registered space, we need to rotate the SFOVs using the slab rotation.
    See plot_aligned_slab.

    The returned array has a shape (2, n_mfovs, N_BEAMS)

    If mfovs is None, then we use all the MFOVs of the slab.
    """
    return (
        xlog[[XVar.X, XVar.Y]]
        .sel(scan=scan, slab=slab, mfov=mfovs if mfovs is not None else slice(0, None))
        .dropna(XDim.MFOV, how="all")
        .to_dataarray()
        .values
    )


def open_sfovs(paths: list[Path], client: Client | None = None) -> np.ndarray:
    """Opens SFOVs in parallel given their paths."""
    if client is None:
        with Client(processes=True) as client:
            images = _open_sfovs(paths, client)
    else:
        images = _open_sfovs(paths, client)
    return (255 * np.asarray(images)).astype(np.uint8)


def _open_sfovs(paths: list[Path], client: Client) -> np.ndarray:
    """Opens SFOVs with a dask client."""
    return (
        bag.from_sequence(paths, npartitions=10)
        .map(partial(imread, as_gray=True))
        .compute(scheduler=client)
    )


def assemble_mfovs_straight(
    xlog: xr.Dataset,
    scan: int,
    slab: int,
    mfovs: list[int] | None = None,
    *,
    thumbnail: bool = True,
) -> np.ndarray:
    """Assembles SFOVs of MFOVs in the original acquisition orientation.

    Straight means in the orientation in which the images were acquired.
    If mfovs is not provided or is None, then uses all MFOVs of the slab.

    size = (width, height) = np.flip(image.shape) | Fiji  convention of (X,Y)
    shape = image.shape                           | numpy convention of (Y,X)
    """
    if mfovs is None:
        mfovs = get_mfovs(xlog=xlog, slab=slab)
    xy = get_xy_slab(xlog=xlog, scan=scan, slab=slab, mfovs=mfovs).reshape(2, -1).T / (
        FACTOR_THUMBNAIL if thumbnail else 1
    )
    xy_straight: np.ndarray = EuclideanTransform(
        rotation=np.radians(get_slab_rotation(xlog=xlog, scan=scan, slab=slab))
    )(xy)
    xy_straight = (xy_straight - xy_straight.min(axis=0)).round().astype(int)

    slab_path = get_slab_path(xlog=xlog, scan=scan, slab=slab)
    sfov_paths = get_image_paths(slab_path=slab_path, mfovs=mfovs, thumbnail=thumbnail)
    sfovs = open_sfovs(paths=sfov_paths)

    image_size = np.flip(sfovs[0].shape)
    assembly_size = np.max(xy_straight, axis=0) + image_size
    assembly = np.zeros(np.flip(assembly_size).astype(int), dtype=np.uint8)

    corners_images = (
        np.pad(image_size[np.newaxis], ((1, 0), (0, 0))) + xy_straight[:, np.newaxis]
    )
    for corners_sfov, sfov in zip(corners_images, sfovs):
        assembly[slice(*corners_sfov[:, 1]), slice(*corners_sfov[:, 0])] = sfov
    return assembly


def plot_aligned_slab(
    xlog: xr.Dataset, scan: int, slab: int, *, thumbnail: bool = True
) -> None:
    """Plots a slab in local space.

    Slabs are 3d aligned in the local space using light microscopy transforms.

    The transforms for every SFOV are:
        1. translate SFOV center to (0,0)
        2. apply slab rotation around SFOV center at (0,0)
        3. translate the SFOV by (x,y) to place the SFOV center at (x,y)
    """
    slab_path = get_slab_path(xlog=xlog, scan=scan, slab=slab)
    rotation = -get_slab_rotation(xlog=xlog, scan=scan, slab=slab)
    xy = get_xy_slab(xlog=xlog, scan=scan, slab=slab) / (
        FACTOR_THUMBNAIL if thumbnail else 1
    )

    fig, ax = plt.subplots()
    ax.set_xlim(np.min(xy[0]), np.max(xy[0]))
    ax.set_ylim(np.min(xy[1]), np.max(xy[1]))

    mfovs = get_mfovs(xlog=xlog, slab=slab)
    paths = get_image_paths(slab_path=slab_path, mfovs=mfovs, thumbnail=thumbnail)
    with Client(processes=True) as client:
        images = open_sfovs(paths=paths, client=client)
    for (mfov, sfov), image in zip(
        itertools.product(mfovs, np.arange(N_BEAMS)), images
    ):
        sfov_patch = ax.imshow(
            image,
            extent=(0, image.shape[1], 0, image.shape[0]),
            cmap="gray",
            vmin=0,
            vmax=255,
            origin="lower",
        )
        transform = (
            Affine2D()
            .translate(-image.shape[1] / 2, -image.shape[0] / 2)
            .rotate_deg(rotation)
            .translate(*xy[:, mfov, sfov])
        )
        sfov_patch.set_transform(transform + ax.transData)
    fig.suptitle("Slab assembled in local space. Recommended for ingestion.")
    plt.show()
