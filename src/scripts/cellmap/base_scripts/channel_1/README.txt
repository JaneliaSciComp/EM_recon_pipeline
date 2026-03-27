To export channel 1:

1. On a host with access to nearline, run 71_h5_to_align_c1.sh

   The *.channel-1.json file is created by the 1_h5_to_align_c1.sh script before doing the pixi run.

   Based on the align path in that json file, channel-1 h5 files will be written to an align_c1 subdirectory on nrs
   like /nrs/mengwang/data/jrc_celegans-dlon-2/align_c1 when the python script is run.

   Log output from the run is written to logs/h5_to_c1_<timestamp>.log.

   Processing for jrc_celegans-dlon-2 took 1 hour with the following parameters:
     /groups/fibsem/home/fibsemxfer/.pixi/bin/pixi run
       --manifest-path /groups/fibsem/home/fibsemxfer/git/EM_recon_pipeline/pyproject.toml
       --environment fibsem
       --frozen python
       /groups/fibsem/home/fibsemxfer/git/EM_recon_pipeline/src/python/janelia_emrp/fibsem/h5_raw_to_align.py
       --volume_transfer_info /groups/mengwang/mengwanglab/render/align/jrc_celegans-dlon-2/volume_transfer_info.jrc_celegans-dlon-2.channel-1.json
       --num_workers 30
       --parent_work_dir /groups/mengwang/mengwanglab/render/align/jrc_celegans-dlon-2/logs/dask_work_20260305_203757
       --channel_index 1

2. After step 1 completes, on that same host run 72_create_align_c1_stack.sh.

   Log output from the run is written to logs/create-align-c1-<timestamp>.log.

   Processing for jrc_celegans-dlon-2 took 1 minute.

3. After step 2 completes, move to submit.int.janelia.org and run 45_spark_render_to_n5.sh

   Processing for jrc_celegans-dlon-2 v3_acquire_align_channel_1 with 40 nodes took 10 minutes.

4. After step 3 completes, run 73_submit_c1_n5_to_zarr_job.sh.