import logging
from dataclasses import dataclass, field
from typing import Any

import numpy as np
from fibsem_tools.io import read

from janelia_emrp.fibsem.dat_path import DatPath

logger = logging.getLogger(__name__)


@dataclass
class CYXDat:
    dat_path: DatPath
    header: dict[str, Any] = field(compare=False)
    pixels: np.ndarray = field(compare=False)

    def __str__(self):
        return str(self.dat_path.file_path)


def new_cyx_dat(dat_path: DatPath) -> CYXDat:
    """
    Returns
    -------
    CYXDat
        A new instance read from the specified dat path and with pixels rolled into channel, y, x order.
    """
    logger.info(f"new_cyx_dat: reading {dat_path.file_path}")

    dat_record = read(dat_path.file_path)
    dat_header_dict = dat_record.attrs.__dict__

    # data comes in as x, y, c - we need to change it to c, y, x because dat reader no longer does that
    cyx_dat_record = np.rollaxis(dat_record, 2)

    return CYXDat(dat_path=dat_path,
                  header=dat_header_dict,
                  pixels=cyx_dat_record)
