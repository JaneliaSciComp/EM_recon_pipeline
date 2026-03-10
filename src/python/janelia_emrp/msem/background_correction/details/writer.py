"""Writer protocol and pickle-safe factory classes for MSEM image writers."""
from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Protocol, List

import numpy as np

from .config import AcquisitionConfig
from .gc_writer import MsemCloudWriter
from .local_writer import MsemLocalWriter


class MsemWriter(Protocol):
    """Protocol for writing corrected MSEM images."""

    def write_image(self, image: np.ndarray, acquisition_config: AcquisitionConfig) -> bool: ...

    def write_all_images(self, images: np.ndarray, acquisition_configs: List[AcquisitionConfig]) -> List[bool]: ...

    def full_url(self, acquisition_config: AcquisitionConfig) -> str: ...


class MsemWriterFactory(ABC):
    """Abstract factory for creating MsemWriter instances.

    Subclasses must be pickle-safe (only primitive fields) so they can be
    serialized by Dask and sent to workers.
    """

    @abstractmethod
    def create(self) -> MsemWriter: ...


@dataclass(frozen=True)
class CloudWriterFactory(MsemWriterFactory):
    """Pickle-safe factory for creating MsemCloudWriter instances on Dask workers."""
    bucket_name: str
    base_path: str

    def create(self) -> MsemCloudWriter:
        return MsemCloudWriter.get_cached(self.bucket_name, self.base_path)


@dataclass(frozen=True)
class LocalWriterFactory(MsemWriterFactory):
    """Pickle-safe factory for creating MsemLocalWriter instances on Dask workers."""
    base_path: str

    def create(self) -> MsemLocalWriter:
        return MsemLocalWriter.get_cached(self.base_path)
