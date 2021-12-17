# Reconstruction Part 2: Alignment Preparation
## Common Parameters
```bash
export BSUB_HOST="login1.int.janelia.org"
export BASE_WORK_DIR="/groups/flyem/data/alignment/flyem-alignment-ett/Z0720-07m"
export WORK_DIR="${BASE_WORK_DIR}/VNC/Sec26" # more generically: ${BASE_WORK_DIR}/${REGION}/${TAB}
```
## Validate Tile Specs (1 minute for VNC Sec26)
```bash
# Run on LSF / bsub submit host because most work will be done using LSF cluster.
ssh ${BSUB_HOST}
cd ${WORK_DIR}

# Setup work area and parameters for LSF array job to validate recently imported render tile specs. 
./07_gen_validate_spec_run.sh

| Retrieving z values from http://10.40.3.162:8080/render-ws/v1/owner/Z0720_07m_VNC/project/Sec26/stack/v1_acquire/zValues
| 
| Generating /groups/flyem/data/alignment/flyem-alignment-ett/Z0720-07m/VNC/Sec26/run_20211217_060707_37_ValidateTiles/job_specific_parameters.txt
| ..........
| 
| Common parameters for array job are:
| --baseDataUrl http://10.40.3.162:8080/render-ws/v1 --owner Z0720_07m_VNC --project Sec26 --stack v1_acquire --validatorClass org.janelia.alignment.spec.validator.TemTileSpecValidator --validatorData minCoordinate:-999999,maxCoordinate:999999,minSize:1000,maxSize:99999
| 
| Created bsub array script for 10 jobs (z or z batches) in:
| /groups/flyem/data/alignment/flyem-alignment-ett/Z0720-07m/VNC/Sec26/run_20211217_060707_37_ValidateTiles/bsub-array.sh
| 
| Logs will be written to:
| /groups/flyem/data/alignment/flyem-alignment-ett/Z0720-07m/VNC/Sec26/run_20211217_060707_37_ValidateTiles/logs

# If common parameters look ok (they should), run submit script (full path is output above):
run_20211217_060707_37_ValidateTiles/bsub-array.sh

| This job will be billed to flyem
| Job <113403049> is submitted to default queue <short>.
| This job will be billed to flyem
| Job <113403050> is submitted to default queue <short>.
| This job will be billed to flyem
| Job <113403051> is submitted to default queue <short>.

# The submit script launches 3 chained jobs:  
# 1. The first one runs just the first of the array job inputs [1-1].
# 2. If that succeeds, the second job runs the remaining array job inputs [2-10].
# 3. When the second job group completes, the third job runs a log check script.

# Output from the log check script is emailed to you (the job launcher) and looks like this:

| Job 113403051: <check_logs> in cluster <Janelia> Done
| ...
| The output (if any) follows:
| All log files in /groups/flyem/data/alignment/flyem-alignment-ett/Z0720-07m/VNC/Sec26/run_20211217_060707_37_ValidateTiles/logs look okay.
```

## Generate Mipmaps (17 minutes for VNC Sec26)
```bash
# Setup work area and parameters for LSF array job to generate down-sampled mipmaps for all source images. 
./08_gen_mipmap_run.sh

# Output (including full path to submit script) is similar to validation example above.

# If common parameters look ok (they should), run submit script:
run_20211217_063059_153_Mipmap/bsub-array.sh

# Output and 3-chained-job pattern is similar to validation example above.
# As with validation, output from the log check script is emailed to you.
```

## Generate Tile Pairs  (1 minute for VNC Sec26)
```bash
# Create tile pair metadata (JSON files) to be used as input for match.
# This java process runs directly on the submit host which technically you are not supposed to do.
# The process is relatively short (a minute or so) and has never been an issue, so I just run it on the submit host.
# If anyone ever complains, it is easy enough to use an interactive node (busb -i) and run there.  
./11_gen_new_pairs.sh

| ------------------------------------------------------------------------
| Setting up montage pairs (log is captured so wait for results) ...
| 
|   MAX_PAIRS_PER_FILE was set to 50
| 
|   Full pair generation output written to:
|    /groups/flyem/data/alignment/flyem-alignment-ett/Z0720-07m/VNC/Sec26/logs/tile_pairs-20211217_071324.log
| ...
| ------------------------------------------------------------------------
| Setting up cross pairs (log is captured so wait for results) ...
| ...
| 07:14:59.399 [main] INFO  [org.janelia.alignment.util.FileUtil] saveJsonFile: exit, wrote data to /groups/flyem/data/alignment/flyem-alignment-ett/Z0720-07m/VNC/Sec26/pairs_cross/tile_pairs_cross_p11919.json.gz
| 07:14:59.399 [main] INFO  [org.janelia.render.client.TilePairClient] deriveAndSaveSortedNeighborPairs: exit, saved 715143 total pairs
| 07:14:59.399 [main] INFO  [org.janelia.render.client.ClientRunner] run: exit, processing completed in 0 hours, 0 minutes, 57 seconds
```

## Generate Match Data  (75 minutes for VNC Sec26)
```bash
# Setup work areas and parameters for LSF array jobs to generate same layer and cross layer matches. 
./12_gen_staged_match_run.sh

| ------------------------------------------------------------------------
| Setting up job for run_20211217_071528_16_multi_stage_match_montage ...
| Generating /groups/flyem/data/alignment/flyem-alignment-ett/Z0720-07m/VNC/Sec26/run_20211217_071528_16_multi_stage_match_montage/common_parameters.txt
| Generating /groups/flyem/data/alignment/flyem-alignment-ett/Z0720-07m/VNC/Sec26/run_20211217_071528_16_multi_stage_match_montage/job_specific_parameters.txt
| ..................
| Created bsub array script for 1867 jobs in /groups/flyem/data/alignment/flyem-alignment-ett/Z0720-07m/VNC/Sec26/run_20211217_071528_16_multi_stage_match_montage/bsub-array.sh
| Logs will be written to /groups/flyem/data/alignment/flyem-alignment-ett/Z0720-07m/VNC/Sec26/run_20211217_071528_16_multi_stage_match_montage/logs
| 
| ------------------------------------------------------------------------
| Setting up job for run_20211217_071529_994_multi_stage_match_cross ...
| Generating /groups/flyem/data/alignment/flyem-alignment-ett/Z0720-07m/VNC/Sec26/run_20211217_071529_994_multi_stage_match_cross/common_parameters.txt
| Generating /groups/flyem/data/alignment/flyem-alignment-ett/Z0720-07m/VNC/Sec26/run_20211217_071529_994_multi_stage_match_cross/job_specific_parameters.txt
| .......................................................................................................................
| Created bsub array script for 11920 jobs in /groups/flyem/data/alignment/flyem-alignment-ett/Z0720-07m/VNC/Sec26/run_20211217_071529_994_multi_stage_match_cross/bsub-array.sh
| Logs will be written to /groups/flyem/data/alignment/flyem-alignment-ett/Z0720-07m/VNC/Sec26/run_20211217_071529_994_multi_stage_match_cross/logs

# As with previous array jobs, output from a log check script is emailed to you 
# for both the same layer (montage) and cross layer match processes.

# The check script provides summary statistics for each stage of ...

# the montage multi-stage process:

| Stage parameters loaded from /groups/flyem/data/alignment/flyem-alignment-ett/Z0720-07m/VNC/Sec26/run_20211217_071528_16_multi_stage_match_montage/stage_parameters.montage.json
| .........
|                                                                                                                           [stage name]_
|                                                                              SIFT       SIFT   Combined   Combined        SIFT_s[render scale]e[epsilon]_i[inliers]_c[coverage]pct_
|                      Total      Total    Percent       SIFT   Combined       Poor       Poor       Poor       Poor        GEO_s[render scale]e[epsilon]_i[combined inliers]_c[combined coverage]pct_
| Stage            Processed      Saved      Saved      Saved      Saved   Quantity   Coverage   Quantity   Coverage  Slug: d[delta z]_h[parameter hash]
| ---------------  ---------  ---------  ---------  ---------  ---------  ---------  ---------  ---------  ---------  -----------------------------------------------------------------------------------------------------------
| montagePass1         93341      73064       78.3      73064          0      17870       2407          0          0  montagePass1_SIFT_s0.40e02_i025_c070pct_GEO_none----_----_-------_d000_h8da6a90ff657806ebc8f4b9ff86f3340
| montagePass2         20277        608        3.0        582         26      15703          0       3852        114  montagePass2_SIFT_s0.50e02_i025_c070pct_GEO_s1.00e05_i025_c070pct_d000_h83331cf1918bd1cd1235c1093e71caeb
| montagePass3         19669       1155        5.9       1111         44          0          0      16494       2020  montagePass3_SIFT_s0.60e03_i025_c070pct_GEO_s1.00e05_i000_c060pct_d000_ha8feba4c49ed328a2d1ac7decdb756b6
| montagePass4         18514         12        0.1          0         12          0          0      16279       2223  montagePass4_SIFT_s0.60e03_i025_c070pct_GEO_s1.00e05_i000_c060pct_d000_hf170feeae225c5014591c47b5567613b
| montagePass5         18502       1296        7.0       1128        168          0          0      16162       1044  montagePass5_SIFT_s0.60e03_i012_c050pct_GEO_s1.00e03_i000_c050pct_d000_h118513a845169760a041936c8ff80f70
| montagePass6         17206       3190       18.5       3190          0      14016          0          0          0  montagePass6_SIFT_s1.00e05_i012_c000pct_GEO_none----_----_-------_d000_hb1cf242963c833a4b1f1e05f2c673e91
| 
| processed_pair_count:              93341
| saved_pair_count:                  79325
| average_seconds_per_pair:             13.26
| 
| jobs:                               1867
| average_minutes_per_job:              11.05
| max_job_minutes:                      71.93

# and the cross multi-stage process:

| Stage parameters loaded from /groups/flyem/data/alignment/flyem-alignment-ett/Z0720-07m/VNC/Sec26/run_20211217_071529_994_multi_stage_match_cross/stage_parameters.cross.json
| ...........................................................
|                                                                                                                           [stage name]_
|                                                                              SIFT       SIFT   Combined   Combined        SIFT_s[render scale]e[epsilon]_i[inliers]_c[coverage]pct_
|                      Total      Total    Percent       SIFT   Combined       Poor       Poor       Poor       Poor        GEO_s[render scale]e[epsilon]_i[combined inliers]_c[combined coverage]pct_
| Stage            Processed      Saved      Saved      Saved      Saved   Quantity   Coverage   Quantity   Coverage  Slug: d[delta z]_h[parameter hash]
| ---------------  ---------  ---------  ---------  ---------  ---------  ---------  ---------  ---------  ---------  -----------------------------------------------------------------------------------------------------------
| crossPass1          715143     156530       21.9     156530          0     558613          0          0          0  crossPass1_SIFT_s0.05e00_i020_c050pct_GEO_s0.10e00_i150_c050pct_d006_h7c57eb6f14fd7006563010950b1a8c4c
| crossPass2          558613     374210       67.0     374210          0     134499          0      49904          0  crossPass2_SIFT_s0.10e01_i020_c050pct_GEO_s0.15e00_i150_c050pct_d006_h43fb6938fc19a0a7bef73756f1dd03c2
| crossPass3          184403       8875        4.8       8875          0     103158          0      72370          0  crossPass3_SIFT_s0.15e01_i020_c050pct_GEO_s0.25e01_i150_c050pct_d006_h888d17a7cd1c7380997dd41b256b77c9
| crossPass4           85288      31243       36.6      31243          0      38266      15779          0          0  crossPass4_SIFT_s0.25e02_i150_c030pct_GEO_none----_----_-------_d003_h9dbf8fa30fbb5f6ccf6330362cdedc20
| crossPass5           35823      15901       44.4      15901          0          0          0      19922          0  crossPass5_SIFT_s0.25e02_i020_c050pct_GEO_s0.50e02_i075_c000pct_d002_hc9678dff8a758fa34fa42d4f78416501
| crossPass6            9500       8070       84.9       8070          0       1430          0          0          0  crossPass6_SIFT_s0.25e02_i020_c000pct_GEO_none----_----_-------_d001_h97ce9c637dced2411d673cb2865ba58c
| 
| processed_pair_count:             715143
| saved_pair_count:                 594829
| average_seconds_per_pair:              3.07
| 
| jobs:                              11920
| average_minutes_per_job:               3.07
| max_job_minutes:                      12.92 
```