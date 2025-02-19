from abc import ABC, abstractmethod

class AbstractRenderDetails(ABC):
    """Abstract class for handling details (mostly paths) of the render database
    for the specific task."""

    @abstractmethod
    def project_from_slab(self, wafer: int, serial_id: int):
        """Get the project name from the wafer / serial ID combination."""
