import re
from dataclasses import dataclass

from janelia_emrp.msem.wafer_60_gc_upload.details import (
    Region,
    Slab,
    MsemCloudWriter,
    AcquisitionConfig
)
from janelia_emrp.render.web_service_request import RenderRequest


CORE_HOST_PATTERN = re.compile(r'http://([^/]+)/')

@dataclass
class StackId:
    """Class representing a stack ID."""
    owner: str
    project: str
    stack: str

    @classmethod
    def from_dict(cls, data: dict[str, str]) -> 'StackId':
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
        self.host = host
        self.owner = owner
        self.project = project
        self._render_request = RenderRequest(host=core_host, owner=owner, project=project)


    def get_stack_ids(self, slab: Slab) -> dict[Region, list[StackId]]:
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


    def get_z_range(self, stack_id: StackId) -> list[int]:
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
    ) -> tuple[list[str], dict[str, any]]:
        """Get storage locations from the Render server.
        :param serial_ids: Serial ID of the stack.
        :param z: z value for which to get storage locations.
        :return: List of storage locations and full tile specs.
        """
        full_tile_specs = self._render_request.get_resolved_tiles_for_z(stack_id.stack, z)

        locations = []
        tile_id_to_spec_map = full_tile_specs['tileIdToSpecMap']
        for tile_spec in tile_id_to_spec_map.values():
            locations.append(tile_spec['mipmapLevels']['0']['imageUrl'])

        return locations, full_tile_specs


    def setup_new_stack(self, src_stack: str, dst_stack: str):
        """Copy metadata from one stack to another (new) stack.
        :param src_stack: Source stack name.
        :param dst_stack: Destination stack name.
        """
        stack_version = self._render_request.get_stack_metadata(src_stack)["currentVersion"]
        stack_version["versionNotes"] = \
            f"Copied from {src_stack} with Google Cloud paths for tiles."
        self._render_request.create_stack(stack=dst_stack, stack_version=stack_version)


    def complete_stack(self, stack: str):
        """Set the state of a stack to complete.
        :param stack: Stack name.
        """
        self._render_request.set_stack_state_to_complete(stack=stack)


    def save_tilespecs_with_gc_paths(
        self,
        stack: str,
        tile_specs: dict[str, any],
        gc_writer: MsemCloudWriter
    ):
        """Save tile specs with Google Cloud paths to a stack.
        :param stack: Target stack to save the tile specs to.
        :param tile_specs: Tile specs to modify and save.
        :param gc_writer: MsemCloudWriter instance for inferring Google Cloud paths.
        """
        # Add the Google Cloud paths to the tile specs
        for tile_spec in tile_specs['tileIdToSpecMap'].values():
            loc = tile_spec['mipmapLevels']['0']['imageUrl']
            gc_loc = gc_writer.full_url(AcquisitionConfig.from_storage_location(loc))
            tile_spec['mipmapLevels']['0']['imageUrl'] = gc_loc

        # Save the tile specs to the stack
        self._render_request.save_resolved_tiles(stack=stack, resolved_tiles=tile_specs)
