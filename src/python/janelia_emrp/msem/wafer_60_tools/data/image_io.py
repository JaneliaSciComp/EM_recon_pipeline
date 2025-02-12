import os
from typing import List

from cv2 import imread, imwrite, IMREAD_GRAYSCALE
import numpy as np

from msem_tools.config import BeamConfig


def trim_mime_type(file_path: str) -> str:
    """Trim the MIME type to remove any additional parameters."""
    if file_path.startswith('file:'):
        file_path = file_path[5:]
    return file_path

def load_images_as_stack(file_paths: List[str]) -> np.ndarray:
    """Load images from file paths and stack them into a 3D array."""
    file_paths = [trim_mime_type(file_path) for file_path in file_paths]
    images = [imread(file_path, IMREAD_GRAYSCALE) for file_path in file_paths]
    return np.stack(images, axis=0)

def store_beam_shading(shading: np.ndarray, base_path: str, beam_config: BeamConfig) -> None:
    """Store the beam shading pattern to a file."""
    image_dir = os.path.join(
            f'{base_path}', 'beam_shading',
            f'scan_{beam_config.scan:03}',
            f'slab_{beam_config.slab:04}'
    )
    image_path = os.path.join(image_dir, f'sfov_{beam_config.sfov:03}.tif')
    os.makedirs(image_dir, exist_ok=True)
    imwrite(image_path, shading)
