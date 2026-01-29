import logging

import dask.bag as dask_bag
import sys
import time
from janelia_emrp.cluster import get_cluster
from distributed import Client

logger = logging.getLogger()
console_handler = logging.StreamHandler(sys.stdout)
console_formatter = logging.Formatter("%(asctime)s [%(threadName)s] [%(name)s] [%(levelname)s] %(message)s")
console_handler.setFormatter(console_formatter)
logger.addHandler(console_handler)
logger.setLevel(logging.INFO)


def snooze(task_ids: list[int]):
    logger.info(f"start task partition for tasks {task_ids}")
    for task_id in task_ids:
        logger.info(f"snooze for task {task_id}")
        time.sleep(5)
        logger.info(f"task {task_id} complete")
    logger.info(f"end task partition for tasks {task_ids}")


def main(num_workers: int):
    task_list = [i for i in range(0, num_workers*2)]
    with get_cluster(threads_per_worker=1) as dask_cluster, Client(dask_cluster) as dask_client:
        dask_client.cluster.scale(n=num_workers)
        logger.info(f"observe dask cluster information at {dask_cluster.dashboard_link}")
        logger.info(f"scaled count is {len(dask_cluster.worker_spec)}")

        bag = dask_bag.from_sequence(task_list, npartitions=num_workers)
        bag = bag.map_partitions(snooze)
        dask_client.compute(bag, sync=True)


if __name__ == "__main__":
    main(num_workers=2)
