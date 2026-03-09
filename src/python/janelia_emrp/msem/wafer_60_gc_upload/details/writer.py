"""Writer protocol and pickle-safe factory classes for MSEM image writers."""
from dataclasses import dataclass
from typing import Protocol, List

import numpy as np

from .config import AcquisitionConfig


class MsemWriter(Protocol):
    """Protocol for writing corrected MSEM images."""

    def write_image(self, image: np.ndarray, acquisition_config: AcquisitionConfig) -> bool: ...

    def write_all_images(self, images: np.ndarray, acquisition_configs: List[AcquisitionConfig]) -> List[bool]: ...

    def full_url(self, acquisition_config: AcquisitionConfig) -> str: ...


@dataclass(frozen=True)
class CloudWriterFactory:
    """Pickle-safe factory for creating MsemCloudWriter instances on Dask workers."""
    bucket_name: str
    base_path: str

    def create(self) -> MsemWriter:
        from .gc_writer import MsemCloudWriter
        return MsemCloudWriter.get_cached(self.bucket_name, self.base_path)


@dataclass(frozen=True)
class LocalWriterFactory:
    """Pickle-safe factory for creating MsemLocalWriter instances on Dask workers."""
    base_path: str

    def create(self) -> MsemWriter:
        from .local_writer import MsemLocalWriter
        return MsemLocalWriter.get_cached(self.base_path)
