# Render pipeline for Cellmap projects
This document describes the pipeline for processing FIB-SEM data for the Cellmap project. The scripts and tools mentioned in this document can be found at `src/scripts/cellmap`. Most of the information below is specific to the cellmap project, but the general ideas should be transferable.

Tracking of the progress of the processing and communication with collaborators is detailed in the [project management](project_management.md) section.

General info on how to run programs on Janelia’s compute cluster can be found on the [Janelia Compute Cluster Wiki page](https://wikis.janelia.org/display/SCS/Janelia+Compute+Cluster). There are also a few things to consider for running Spark on an LSF cluster; see the [corresponding Wiki page](https://wikis.janelia.org/display/ScientificComputing/Spark+on+LSF).

## Pipeline overview

The pipeline consists of the following steps:
1. [Transfer](steps/1_transfer.md) the data from the scope to the shared drive.
2. Process the data:
   1. [Render import](steps/2-1_render_import.md): Import the data into the render webservice.
   2. [Prepare alignment](steps/2-2_alignment_prep.md): Prepare the data for alignment.
   3. [Review](steps/2-3_review_matches.md): Review the matches.
   4. [Alignment](steps/2-4_alignment_solve.md): Actually align the data.
3. [Export](steps/3_export.md) the data to a final N5 volume.

For running each of the processing and export steps, up to three actors are involved:
- A web-server running the render webservice (render-ws). Here, all meta-data is persisted in form of `TileSpec`s (which includes geometric information, paths to the image file, and transformations) and `PointMatch`es.
- The file system where the actual image files are stored. This is usually the lab’s shared drive.
- The machine where the actual computation is done. This is typically the cluster or a local workstation and it needs access to both of the above.

In addition, for the transfer step, access to the scope and [Janelia's Jenkins server](https://jenkins.int.janelia.org) is needed.
