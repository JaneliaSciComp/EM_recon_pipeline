import logging
import subprocess
import sys
import traceback
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, Optional

logger = logging.getLogger("mask_builder")


@dataclass
class MaskBuilder:
    base_dir: Optional[Path]
    mask_width: int
    existing_masks: set[Path] = field(compare=False, default_factory=set)
    mask_errors: Dict[Path, list[str]] = field(compare=False, default_factory=dict)

    def create_mask_if_missing(self,
                               image_width: int,
                               image_height: int) -> str:

        if self.base_dir is None:
            mask_uri_string = f"mask://outside-box?minX={self.mask_width}&minY=0&" \
                              f"maxX={image_width}&maxY={image_height}&" \
                              f"width={image_width}&height={image_height}"
        else:
            mask_path = Path(f"{self.base_dir}/mask_{image_width}x{image_height}_left_{self.mask_width}.tif")

            if not (mask_path in self.existing_masks):

                if not mask_path.exists():
                    # noinspection PyBroadException
                    try:
                        argv = [
                            '/groups/flyem/data/render/bin/create_mask.sh',
                            str(image_width),
                            str(image_height),
                            str(self.mask_width),
                            str(self.base_dir)
                        ]
                        create_output = subprocess.check_output(argv, stderr=subprocess.STDOUT)
                        logger.info(create_output)

                    except Exception:
                        exc_type, exc_value, exc_traceback = sys.exc_info()
                        self.mask_errors[mask_path] = traceback.format_exception(exc_type, exc_value, exc_traceback)

                self.existing_masks.add(mask_path)

            mask_uri_string = f"file://{str(mask_path)}"

        return mask_uri_string

    def get_mask_loader_type(self) -> Optional[str]:
        return "DYNAMIC_MASK" if self.base_dir is None else None
