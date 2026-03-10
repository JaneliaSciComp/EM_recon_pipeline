"""Writer for storing corrected MSEM images to local filesystem."""
import functools
import os
from typing import List

from cv2 import imencode, imwrite
import numpy as np

from janelia_emrp.msem.background_correction.details.config import AcquisitionConfig


class MsemLocalWriter:
    """
    Class for writing corrected MSEM data to local filesystem as PNGs.
    :param base_path: The base directory for the output data.
    """
    def __init__(self, base_path: str):
        self._base_path = base_path

    def write_image(
            self,
            image: np.ndarray,
            acquisition_config: AcquisitionConfig
    ) -> bool:
        """
        Write a single image to a PNG file on local disk.
        :param image: The image to write.
        :param acquisition_config: The acquisition configuration specifying the image location.
        """
        file_path = self._sfov_path_for(acquisition_config)
        os.makedirs(os.path.dirname(file_path), exist_ok=True)
        return imwrite(file_path, image)

    def write_all_images(
            self,
            images: np.ndarray,
            acquisition_configs: List[AcquisitionConfig]
    ) -> List[bool]:
        """
        Write a stack of images to PNGs on local disk.
        :param images: The images to write as 3D numpy array (1st dimension is the image index).
        :param acquisition_configs: The acquisition configurations specifying the image locations.
        """
        return [
            self.write_image(image, acquisition_config)
            for image, acquisition_config in zip(images, acquisition_configs)
        ]

    def _sfov_path_for(self, acquisition_config: AcquisitionConfig) -> str:
        """
        Get the local file path for the given acquisition configuration.
        Omits the slab directory when slab is 0 (e.g. wafer 68 paths have no slab).
        """
        parts = [self._base_path, f"scan_{acquisition_config.scan:03}"]
        if acquisition_config.slab != 0:
            parts.append(f"slab_{acquisition_config.slab:04}")
        parts.append(f"mfov_{acquisition_config.mfov:04}")
        parts.append(f"sfov_{acquisition_config.sfov:03}.png")
        return os.path.join(*parts)

    def full_url(self, acquisition_config: AcquisitionConfig) -> str:
        """
        Get the file: URI for the given acquisition configuration.
        """
        return "file:" + self._sfov_path_for(acquisition_config)

    @classmethod
    @functools.lru_cache(maxsize=100)
    def get_cached(cls, base_path: str) -> 'MsemLocalWriter':
        """
        Get a cached instance of the MsemLocalWriter.
        :param base_path: The base directory for the output data.
        """
        return cls(base_path=base_path)
