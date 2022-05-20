"""
Root logger to be shared and used by all main functions.

Example usage::

    from janelia_emrp.root_logger import init_logger
    ...
    logger = logging.getLogger(__name__)
    ...
    if __name__ == "__main__":
        init_logger(__file__)
"""
import logging

import sys

root_logger = logging.getLogger()
console_handler = logging.StreamHandler(sys.stdout)
console_formatter = logging.Formatter("%(asctime)s [%(threadName)s] [%(name)s] [%(levelname)s] %(message)s")
console_handler.setFormatter(console_formatter)
root_logger.addHandler(console_handler)
root_logger.setLevel(logging.INFO)


def init_logger(context: str):
    root_logger.info(f'root logger initialized from {context}')