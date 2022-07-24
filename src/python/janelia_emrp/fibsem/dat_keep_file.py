import datetime
import logging
import re
from pathlib import Path
from typing import Final, Optional

from pydantic import BaseModel

from janelia_emrp.fibsem.dat_path import new_dat_path

logger = logging.getLogger(__name__)


# Z0422-17_VNC_1^E^^Images^Fly Brain^Y2022^M07^D12^Merlin-6049_22-07-12_171723_0-0-1.dat^keep
KEEP_NAME_PATTERN: Final = re.compile(r"([^\^]+)\^([^\^]+)\^\^(.*\.dat)\^keep$")


class KeepFile(BaseModel):
    host: str
    keep_path: str
    data_set: str
    dat_path: str

    def acquire_time(self) -> datetime.datetime:
        return new_dat_path(Path(self.dat_path)).acquire_time


def build_keep_file(host: str,
                    keep_file_root: str,
                    keep_file_name: str) -> Optional[KeepFile]:

    keep_file = None
    m = KEEP_NAME_PATTERN.match(keep_file_name)
    if m:
        drive = m.group(2)
        drive_path = m.group(3).replace("^", "/")
        keep_file = KeepFile(host=host,
                             keep_path=f"{keep_file_root}/{keep_file_name}",
                             data_set=m.group(1),
                             dat_path=f"/cygdrive/{drive}/{drive_path}")
    else:
        logger.warning(f"build_keep_file: ignoring {keep_file_name} because it does not match expected pattern")

    return keep_file
