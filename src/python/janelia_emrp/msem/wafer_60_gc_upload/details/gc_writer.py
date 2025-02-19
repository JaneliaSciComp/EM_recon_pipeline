import functools
from typing import List
from cv2 import imencode
from google.cloud import storage
import numpy as np

from janelia_emrp.msem.wafer_60_gc_upload.details.config import AcquisitionConfig

class MsemCloudWriter:
    """
    Class for writing wafer 60/61 MSEM data to Google Cloud Storage.
    :param bucket_name: The name of the Google Cloud Storage bucket.
    :param base_path: The base prefix for the data in the bucket.
    """
    def __init__(
            self,
            bucket_name: str,
            base_path: str,
    ):
        self._base_path = base_path
        self._client = storage.Client()
        self._bucket = self._client.bucket(bucket_name)


    def write_image(
            self,
            image: np.ndarray,
            acquisition_config: AcquisitionConfig
    ):
        """
        Write a single image to a png file in Google Cloud Storage.
        :param image: The image to write.
        :param acquisition_config: The acquisition configuration specifying the image location.
        """
        file_path = self._sfov_path_for(acquisition_config)
        blob = self._bucket.blob(file_path)
        raw_image = imencode('.png', image)[1].tostring()
        blob.upload_from_string(raw_image, content_type='image/png')
        return blob.exists()


    def write_all_images(
            self,
            images: np.ndarray,
            acquisition_configs: List[AcquisitionConfig]
    ) -> List[bool]:
        """
        Upload a stack of images to pngs in Google Cloud Storage.
        :param images: The images to write as 3D numpy array (1st dimension is the image index).
        :param acquisition_configs: The acquisition configurations specifying the image locations.
        """
        return [
            self.write_image(image, acquisition_config)
            for image, acquisition_config in zip(images, acquisition_configs)
        ]


    def _sfov_path_for(self, acquisition_config: AcquisitionConfig) -> str:
        """
        Get the path of a single image for the given acquisition configuration.
        """
        return (
            f"{self._base_path}/"
            f"scan_{acquisition_config.scan:03}/"
            f"slab_{acquisition_config.slab:04}/"
            f"mfov_{acquisition_config.mfov:04}/"
            f"sfov_{acquisition_config.sfov:03}.png"
        )


    def full_url(self, acquisition_config: AcquisitionConfig) -> str:
        """
        Get the path of a single image for the given acquisition configuration.
        """
        return f"{self._bucket}/{self._sfov_path_for(acquisition_config)}"


    @classmethod
    @functools.lru_cache(maxsize=100)
    def get_cached(
            cls,
            bucket_name: str,
            base_path: str,
    ) -> 'MsemCloudWriter':
        """
        Get a cached instance of the MsemCloudWriter.
        :param bucket_name: The name of the Google Cloud Storage bucket.
        :param base_path: The base prefix for the data in the bucket.
        """
        return cls(bucket_name=bucket_name, base_path=base_path)
