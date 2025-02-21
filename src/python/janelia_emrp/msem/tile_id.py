from __future__ import annotations
from dataclasses import dataclass
from typing import ClassVar

from janelia_emrp.msem.render_sfov_order import RENDER_SFOV_ORDER

@dataclass
class TileID:
    """Render TileID.
    
    Beware of different indexings:
        image paths use 1-based indexing: e.g. the first sfov is named sfov_001.png
        metrics from the IBEAM-MSEM acquisition side use 0-based indexing
        tile IDs in render use 1-based indexing

    E.g. w60_magc0002_scan001_m0003_s04 has sfov = 3 and is sfov_004.png
    """
    wafer_id: str
    slab: int
    scan: int
    mfov: int
    sfov: int
    """0-based indexing"""
    wafer_prefix : ClassVar[str] = "w"
    slab_prefix: ClassVar[str] = "magc"
    scan_prefix: ClassVar[str] = "scan"
    mfov_prefix: ClassVar[str] = "m"
    render_prefix: ClassVar[str] = "r"
    sfov_prefix: ClassVar[str] = "s"
    
    @property
    def scope_sfov_number(self)->int:
        """1-based indexing of the sfov."""
        return self.sfov + 1

    def __str__(self)->str:
        """String representation of TileID, e.g. w60_magc0002_scan001_m0003_s04."""
        return "_".join(
            (
                f"{self.wafer_prefix}{self.wafer_id}",
                f"{self.slab_prefix}{self.slab:04}",
                f"{self.scan_prefix}{self.scan:03}",
                f"{self.mfov_prefix}{self.mfov:04}",
                f"{self.render_prefix}{RENDER_SFOV_ORDER[self.sfov]:02}",
                f"{self.sfov_prefix}{self.scope_sfov_number:02}",
            )
        )
    @classmethod
    def from_string(cls, string:str)->TileID:
        """Creates TileID from its string representation, see __str__."""
        split=string.split("_")
        return TileID(
            wafer_id=split[0].removeprefix(cls.wafer_prefix),
            slab=int(split[1].removeprefix(cls.slab_prefix)),
            scan=int(split[2].removeprefix(cls.scan_prefix)),
            mfov=int(split[3].removeprefix(cls.mfov_prefix)),
            sfov=int(split[5].removeprefix(cls.sfov_prefix)) - 1,
        )
        
    def to_roi_name(self)->str:
        """To roi name, e.g. w60_magc0399_scan049_m0043_r35_s04 -> 0043_s04."""
        return f"{self.mfov:04}_{self.sfov_prefix}{self.scope_sfov_number:02}"