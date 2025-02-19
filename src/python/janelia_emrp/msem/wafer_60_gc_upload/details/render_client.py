import re
from dataclasses import dataclass
from typing import Dict, List

from janelia_emrp.msem.wafer_60_gc_upload.details.config import Region, Slab
from janelia_emrp.render.web_service_request import RenderRequest


CORE_HOST_PATTERN = re.compile(r'http://([^/]+)/')

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
    """Wrapper class for interacting with the Render server."""

    def __init__(
            self,
            *,
            host: str,
            owner: str,
            project: str
    ):
        """Initialize the MultiSemClient with hostname, project, and owner."""
        core_host = CORE_HOST_PATTERN.match(host).group(1)
        self._render_request = RenderRequest(host=core_host, owner=owner, project=project)


    def get_stack_ids(self, slab: Slab) -> Dict[Region, List[StackId]]:
        """Get stack IDs from the Render server.
        :param slab: Physical slab for which to get stack IDs
        :return: Dictionary mapping regions to lists of stack IDs.
        """
        stack_ids = self._render_request.get_stack_ids()
        pattern = re.compile(f"^w{slab.wafer}_s{slab.serial_id:03}_r(\\d+)")

        region_stacks = {}
        for stack_id in stack_ids:
            match = pattern.match(stack_id['stack'])
            region_id = int(match.group(1))
            region = Region(slab=slab, region_id=region_id)
            if region not in region_stacks:
                region_stacks[region] = []
            region_stacks[region].append(StackId.from_dict(stack_id))

        return region_stacks


    def get_z_range(self, stack_id: StackId) -> List[int]:
        """Get the Z range of a stack from the Render server.
        :param stack_id: Stack ID of the stack.
        :return: List of minimum and maximum Z values.
        """
        z_values = self._render_request.get_z_values(stack_id.stack)
        return [int(z) for z in z_values]


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
        response = self._render_request.get_resolved_tiles_for_z(stack_id.stack, z)

        locations = []
        tile_id_to_spec_map = response['tileIdToSpecMap']
        for tile_spec in tile_id_to_spec_map.values():
            locations.append(tile_spec['mipmapLevels']['0']['imageUrl'])

        return locations
