"""
Dask cluster utilities for Janelia Research Campus compute cluster.

This module provides convenience functions for creating dask clusters,
originally from the dask-janelia package (https://github.com/janelia-cosem/dask-janelia).
Vendored here to avoid dependency version conflicts.
"""

from shutil import which

from dask_jobqueue.lsf import LSFJob
from distributed import LocalCluster
from dask_jobqueue import LSFCluster
import os
from pathlib import Path
import dask
from typing import Union, List, Dict, Any, Optional
import warnings

dask.config.set({"jobqueue.lsf.use-stdin": True})

threading_env_vars = [
    "NUM_MKL_THREADS",
    "OPENBLAS_NUM_THREADS",
    "OPENMP_NUM_THREADS",
    "OMP_NUM_THREADS",
]


def make_single_threaded_env_vars(threads: int) -> List[str]:
    return [f"export {var}={threads}" for var in threading_env_vars]


def bsub_available() -> bool:
    """Check if the `bsub` shell command is available

    Returns True if the `bsub` command is available on the path, False otherwise. This is used to check whether code is
    running on the Janelia Compute Cluster.
    """
    result = which("bsub") is not None
    return result


# A class to help exit gracefully on Janelia's LSF cluster.
# Copied from https://github.com/GFleishman/ClusterWrap/blob/44b3d9dccfde495809dc3e4776f0d402a701e7d8/ClusterWrap/clusters.py#L230
class JaneliaLSFJob(LSFJob):
    cancel_command = "bkill -d"  # default cancel command is just 'bkill'


def get_LSFCLuster(
    threads_per_worker: int = 1,
    walltime: str = "1:00",
    death_timeout: str = "600s",
    **kwargs,
) -> LSFCluster:
    """Create a dask_jobqueue.LSFCluster for use on the Janelia Research Campus compute cluster.

    This function wraps the class dask_jobqueue.LSFCLuster and instantiates this class with some sensible defaults,
    given how the Janelia cluster is configured.

    This function will add environment variables that prevent libraries (OPENMP, MKL, BLAS) from running multithreaded routines with parallelism
    that exceeds the number of requested cores.

    Additional keyword arguments added to this function will be passed to the dask_jobqueue.LSFCluster constructor.

    Parameters
    ----------
    threads_per_worker: int
        Number of cores to request from LSF. Directly translated to the `cores` kwarg to LSFCluster.
    walltime: str
        The expected lifetime of a worker. Defaults to one hour, i.e. "1:00"
    death_timeout: str
        The duration for the scheduler to wait for workers before flagging them as dead, e.g. "600s". For jobs with a large number of workers,
        LSF may take a long time (minutes) to request workers. This timeout value must exceed that duration, otherwise the scheduler will
        flag these slow-to-arrive workers as unresponsive and kill them.
    **kwargs:
        Additional keyword arguments passed to the LSFCluster constructor

    Examples
    --------

    >>> cluster = get_LSFCLuster(threads_per_worker=2, project="scicompsoft", queue="normal")

    """

    if "job_script_prologue" not in kwargs:
        kwargs["job_script_prologue"] = []

    kwargs["job_script_prologue"].extend(make_single_threaded_env_vars(threads_per_worker))

    USER = os.environ["USER"]
    HOME = os.environ["HOME"]

    if "local_directory" not in kwargs:
        # The default local scratch directory on the Janelia Cluster
        kwargs["local_directory"] = f"/scratch/{USER}/"

    if "log_directory" not in kwargs:
        log_dir = f"{HOME}/.dask_distributed/"
        Path(log_dir).mkdir(parents=False, exist_ok=True)
        kwargs["log_directory"] = log_dir

    # Memory is required by dask_jobqueue but not meaningful for slot-based LSF clusters
    # Set a default that satisfies the library without affecting job submission
    if "memory" not in kwargs:
        kwargs["memory"] = "16GB"

    job_cls = kwargs.pop("job_cls", JaneliaLSFJob)

    cluster = LSFCluster(
        cores=threads_per_worker,
        walltime=walltime,
        death_timeout=death_timeout,
        job_cls=job_cls,
        **kwargs,
    )
    return cluster


def get_LocalCluster(threads_per_worker: int = 1, n_workers: int = 0, **kwargs):
    """
    Creata a distributed.LocalCluster with defaults that make it more similar to a deployment on the Janelia Compute cluster.
    This function is a light wrapper around the distributed.LocalCluster constructor.

    Parameters
    ----------
    n_workers: int
        The number of workers to start the cluster with. This defaults to 0 here.
    threads_per_worker: int
        The number of threads to assign to each worker.
    **kwargs:
        Additional keyword arguments passed to the LocalCluster constructor
    Examples
    --------

    >>> cluster = get_LocalCluster(threads_per_worker=8)
    """
    return LocalCluster(
        n_workers=n_workers, threads_per_worker=threads_per_worker, **kwargs
    )


def get_cluster(
    threads_per_worker: int = 1,
    deployment: Optional[str] = None,
    local_kwargs: Dict[str, Any] = {},
    lsf_kwargs: Dict[str, Any] = {},
) -> Union[LSFCluster, LocalCluster]:

    """Convenience function to generate a dask cluster on either a local machine or the compute cluster.

    Create a distributed.Client object backed by either a dask_jobqueue.LSFCluster (for use on the Janelia Compute Cluster)
    or a distributed.LocalCluster (for use on a single machine). This function uses the output of the bsubAvailable function
    to determine whether code is running on the compute cluster or not.
    Additional keyword arguments given to this function will be forwarded to the constructor for the Client object.

    Parameters
    ----------
    threads_per_worker: int
        Number of threads per worker. Defaults to 1.

    deployment: str or None
        Which deployment (LocalCluster or LSFCluster) to prefer. If deployment=None, then LSFCluster is preferred, but LocalCluster is used if
        bsub is not available. If deployment='lsf' and bsub is not available, an error is raised.
    local_kwargs: dict
        Dictionary of keyword arguments for the distributed.LocalCluster constructor
    lsf_kwargs: dict
        Dictionary of keyword arguments for the dask_jobqueue.LSFCluster constructor
    """

    if "cores" in lsf_kwargs:
        warnings.warn(
            "The `cores` kwarg for LSFCLuster has no effect. Use the `threads_per_worker` argument instead."
        )

    if "threads_per_worker" in local_kwargs:
        warnings.warn(
            "the `threads_per_worker` kwarg was found in `local_kwargs`. It will be overwritten with the `threads_per_worker` argument to this function."
        )

    if deployment is None:
        if bsub_available():
            cluster = get_LSFCLuster(threads_per_worker, **lsf_kwargs)
        else:
            cluster = get_LocalCluster(threads_per_worker, **local_kwargs)
    elif deployment == "lsf":
        if bsub_available():
            cluster = get_LSFCLuster(threads_per_worker, **lsf_kwargs)
        else:
            raise EnvironmentError(
                "You requested an LSFCluster but the command `bsub` is not available."
            )
    elif deployment == "local":
        cluster = get_LocalCluster(threads_per_worker, **local_kwargs)
    else:
        raise ValueError(
            f'deployment must be one of (None, "lsf", or "local"), not {deployment}'
        )

    return cluster
