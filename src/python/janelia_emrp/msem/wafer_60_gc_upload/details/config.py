"""
Configuration classes for specifying acquisition parameters of multi-sem data.
"""
import re
from dataclasses import dataclass


SLAB_PATTERN = re.compile(r"slab_(\d{4})")
SCAN_PATTERN = re.compile(r"scan_(\d{3})")
MFOV_PATTERN = re.compile(r"mfov_(\d{4})")
SFOV_PATTERN = re.compile(r"sfov_(\d{3})")


@dataclass(frozen=True)
class Slab:
    """
    Class that specifies a single slab by its wafer and serial ID.
    """
    wafer: int
    serial_id: int

    def __post_init__(self):
        if self.wafer not in (60, 61) or self.serial_id < 0 or self.serial_id > 800:
            raise ValueError(f"Invalid slab ID: {self}")
    

@dataclass(frozen=True)
class Region:
    """
    Class that specifies a single region by its slab and region ID.
    """
    slab: Slab
    region_id: int

    def __post_init__(self):
        if self.region_id < 0:
            raise ValueError(f"Invalid region ID: {self}")


@dataclass(frozen=True)
class BeamConfig:
    """
    Class that specifies a single beam configuration that (hopefully) does not
    change during acquisition.
    """
    scan: int
    slab: int
    sfov: int

    def all_acquisitions(self, mfovs) -> 'AcquisitionConfig':
        """
        Generate AcquisitionConfig objects for all acquisitions in the given
        list of mfovs.
        """
        return [AcquisitionConfig(mfov=mfov, beam_config=self) for mfov in mfovs]
    
    @classmethod
    def from_storage_location(
        cls,
        storage_location: str,
    ) -> 'BeamConfig':
        """
        Create a BeamConfig object from a storage location string.
        :param storage_location: The storage location string.
        :return: The BeamConfig object.
        :raises ValueError: If the storage location string is invalid (i.e.,
            either scan, slab, or sfov could not be inferred from the location).
        """
        try:
            scan = int(SCAN_PATTERN.search(storage_location).group(1))
            slab = int(SLAB_PATTERN.search(storage_location).group(1))
            sfov = int(SFOV_PATTERN.search(storage_location).group(1))
        except AttributeError:
            raise ValueError(f"Invalid storage location: {storage_location}") from None

        return cls(scan=scan, slab=slab, sfov=sfov)


class AcquisitionConfig:
    """
    Class that specifies the configuration for a single acquisition (i.e., a
    single sfov). This class can be initialized with either a BeamConfig object
    and an mfov, or with a scan, slab, sfov, and mfov.
    """
    def __init__(
        self,
        /,
        mfov: int,
        scan: int = None,
        slab: int = None,
        sfov: int = None,
        beam_config: BeamConfig = None,
    ):
        has_beam_config = beam_config is not None
        has_other = scan is not None and slab is not None and sfov is not None

        if has_beam_config and has_other:
            raise ValueError("Cannot specify both beam_config and (scan, slab, sfov)")

        if not has_beam_config and not has_other:
            raise ValueError("Must specify either beam_config or (scan, slab, sfov)")

        if has_beam_config:
            self._beam_config = beam_config

        if has_other:
            self._beam_config = BeamConfig(scan=scan, slab=slab, sfov=sfov)

        self._mfov = mfov

    @classmethod
    def from_storage_location(
        cls,
        storage_location: str,
    ) -> 'AcquisitionConfig':
        """
        Create an AcquisitionConfig object from a storage location string.
        :param storage_location: The storage location string.
        :return: The AcquisitionConfig object.
        :raises ValueError: If the storage location string is invalid (i.e.,
            either scan, slab, sfov, or mfov could not be inferred from the
            location).
        """
        try:
            scan = int(SCAN_PATTERN.search(storage_location).group(1))
            slab = int(SLAB_PATTERN.search(storage_location).group(1))
            mfov = int(MFOV_PATTERN.search(storage_location).group(1))
            sfov = int(SFOV_PATTERN.search(storage_location).group(1))
        except AttributeError:
            raise ValueError(f"Invalid storage location: {storage_location}") from None

        return cls(scan=scan, slab=slab, sfov=sfov, mfov=mfov
    )

    @property
    def scan(self) -> int:
        """Scan number for the acquisition."""
        return self._beam_config.scan

    @property
    def slab(self) -> int:
        """Slab number for the acquisition."""
        return self._beam_config.slab

    @property
    def sfov(self) -> int:
        """SFOV number for the acquisition."""
        return self._beam_config.sfov

    @property
    def mfov(self) -> int:
        """MFOV number for the acquisition."""
        return self._mfov

    @property
    def beam_config(self) -> BeamConfig:
        """BeamConfig object for the acquisition."""
        return self._beam_config

    def __repr__(self) -> str:
        return (
            "AcquisitionConfig("
            f"scan={self.scan}, "
            f"slab={self.slab}, "
            f"sfov={self.sfov}, "
            f"mfov={self.mfov})"
        )

    def __str__(self) -> str:
        return self.__repr__()
