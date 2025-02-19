import re
from dataclasses import dataclass
from typing import Dict, List

import requests

from janelia_emrp.msem.wafer_60_gc_upload.details.config import Region, Slab


TIMEOUT = 10

@dataclass
class StackId:
    """Class representing a stack ID."""
    owner: str
    project: str
    stack: str

    @classmethod
    def from_dict(cls, data: Dict[str, str]) -> 'StackId':
        """Create a StackId instance from a dictionary."""
        return cls(
            owner=data['owner'],
            project=data['project'],
            stack=data['stack']
        )


class MsemClient():
    """Client for requesting multi-sem data from the render web service."""

    def __init__(
            self,
            *,
            host: str,
            owner: str,
    ):
        """Initialize the MultiSemClient with hostname and owner."""
        self.host = host
        self.owner = owner


    def get_stack_ids(self, slab: Slab) -> Dict[Region, List[StackId]]:
        """Get stack IDs from the Render server.
        :param slab: Physical slab for which to get stack IDs
        :return: Dictionary mapping regions to lists of stack IDs.
        """
        project = get_project(slab)
        url = f"{self.host}/owner/{self.owner}/project/{project}/stackIds"

        response = requests.get(url, timeout=TIMEOUT)

        if response.status_code != 200:
            response.raise_for_status()

        ids = response.json()
        pattern = re.compile(f"^w{slab.wafer}_s{slab.serial_id:03}_r(\\d+)")

        region_stacks = {}
        for id in ids:
            match = pattern.match(id['stack'])
            region_id = int(match.group(1))
            region = Region(slab=slab, region_id=region_id)
            if region not in region_stacks:
                region_stacks[region] = []
            region_stacks[region].append(StackId.from_dict(id))

        return region_stacks


    def get_z_range(self, stack_id: StackId) -> List[int]:
        """Get the Z range of a stack from the Render server.
        :param stack_id: Stack ID of the stack.
        :return: List of minimum and maximum Z values.
        """
        url = (
            f"{self.host}/"
            f"owner/{stack_id.owner}/"
            f"project/{stack_id.project}/"
            f"stack/{stack_id.stack}/"
            "zValues"
        )

        response = requests.get(url, timeout=TIMEOUT)
        if response.status_code != 200:
            response.raise_for_status()

        return [int(z) for z in response.json()]


    def get_storage_locations(
            self,
            *,
            stack_id: StackId,
            z: int,
    ) -> List[str]:
        """Get storage locations from the Render server.
        :param serial_ids: Serial ID of the stack.
        :param z: z value for which to get storage locations.
        :return: List of storage locations.
        """
        url = (
            f"{self.host}/"
            f"owner/{stack_id.owner}/"
            f"project/{stack_id.project}/"
            f"stack/{stack_id.stack}/"
            "resolvedTiles"
            f"?minZ={z}&maxZ={z}"
        )

        response = requests.get(url, timeout=TIMEOUT)
        if response.status_code != 200:
            response.raise_for_status()

        locations = []
        tile_id_to_spec_map = response.json()['tileIdToSpecMap']
        for tile_spec in tile_id_to_spec_map.values():
            locations.append(tile_spec['mipmapLevels']['0']['imageUrl'])

        return locations


def get_project(slab: Slab) -> str:
    """Get the project name from the serial ID.
    :param serial_id: Serial ID of the stack.
    :return: Project name.
    :raises ValueError: If the serial ID is not valid.
    """
    lower_bound = slab.serial_id // 10 * 10
    upper_bound = lower_bound + 9
    return f"w{slab.wafer}_serial_{lower_bound}_to_{upper_bound}"
