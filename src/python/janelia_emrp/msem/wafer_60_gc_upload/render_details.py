from abc import ABC, abstractmethod

class AbstractRenderDetails(ABC):
    """Abstract class for handling details (mostly paths) of the render database
    for the specific task."""

    @abstractmethod
    def project_from_slab(self, wafer: int, serial_id: int):
        """Get the project name from the wafer / serial ID combination."""

    @abstractmethod
    def is_source_stack(self, stack_name: str) -> bool:
        """Check if the stack is to be used as a source for background correction.
        In this case, the images from this stack are loaded and used to estimate
        the shading."""

    @abstractmethod
    def is_target_stack(self, stack_name: str) -> bool:
        """Check if the stack is to be used as a target for background correction.
        In this case, the shading is applied to the images of this stack and the
        corrected images are uploaded to Google Cloud Storage."""

    @abstractmethod
    def gc_stack_from(self, stack_name: str) -> str:
        """Get the name of the stack with Google Cloud Storage paths from the original
        stack name.
        """
