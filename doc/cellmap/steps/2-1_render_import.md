# Reconstruction Part 1: Render Import
```bash
# Commonly used paths
RENDER_DIR="/groups/flyem/data/render/"
PROCESSING_DIR=<path to the processing directory set up in previous step>
```
We assume that the data has been successfully transferred and converted to HDF5 format, and that there is a directory set up for processing which we call `PROCESSING_DIR` (see [transfer documentation](1_transfer.md) for details). The first step for processing is to import the data into the Render database so that it can be accessed by the render clients.

## Generate TileSpecs
Go to a machine with access to `${RENDER_DIR}`, navigate to `${PROCESSING_DIR}` and run the following command:
```bash
./07_h5_to_render.sh
```
This will launch a local dask job that will generate TileSpecs from the HDF5 files and upload them to the render database. All necessary information is read from the `volume_transfer_info.<dataset>.json` file that was created in the previous step. After this step, a dynamically rendered stack can be accessed in the point match explorer and viewed in neuroglancer.

## Set up preview volume: export to N5
NOTE: this is a feature under active development and the process will likely change in the near future. For now, the following steps are necessary.

Go to the Janelia compute cluster (e.g., `ssh login1.int.janelia.org`), navigate to `${PROCESSING_DIR}` and run the following command:
```bash
./99_append_to_export.sh <number of executors>
```
This will submit a couple of spark cluster jobs and set up logging directories. The number of executors should be chosen based on the size of the dataset. Currently, a single executor will occupy 10 cores on the cluster and 3 more cores for the driver are needed. The logs for scripts usually reside in `${PROCESSING_DIR}/logs`, but the spark jobs will set up additional log directories for each executor and the driver. These directories are printed to the console when executing above command.

Once fininshed, the location of the final N5 volume can be found either in the driver logs or by running `gen_github_text.sh` again.
