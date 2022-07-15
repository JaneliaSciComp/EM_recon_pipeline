import logging
import re
from typing import Final, Optional

from pydantic import BaseModel

logger = logging.getLogger(__name__)


# 0522-09_ZF-Card^E^^Images^Zebrafish^Y2022^M07^D12^Merlin-6257_22-07-12_153254_0-0-1.dat^keep
# Z0422-17_VNC_1^E^^Images^Fly Brain^Y2022^M07^D12^Merlin-6049_22-07-12_171723_0-0-1.dat^keep
KEEP_NAME_PATTERN: Final = re.compile(r"([^\^]+)\^([^\^]+)\^\^(.*\.dat)\^keep$")


class KeepFile(BaseModel):
    host: str
    keep_path: str
    data_set: str
    dat_path: str

    def host_prefix(self):
        return "" if self.host is None or len(self.host) == 0 else f"{self.host}:"


def build_keep_file(host:str,
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
