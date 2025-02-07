#!/bin/bash

DATE_PATTERN="20250[234]"

DRIVER_LOGS=$(ls /nrs/[cf]*/data/*/align/logs/spark/${DATE_PATTERN}*/logs/04-driver.log /nrs/r*/data/*/h5/align/logs/spark/${DATE_PATTERN}*/logs/04-driver.log 2> /dev/null)

# egrep "(n5_view|findMinZToRender|Turnaround time)" /nrs/[cf]*/data/*/align/logs/spark/202407*/logs/04-driver.log /nrs/r*/data/*/h5/align/logs/spark/202407*/logs/04-driver.log
# /nrs/cellmap/data/jrc_alta24-b9_4nm/align/logs/spark/20240701_012303/logs/04-driver.log:2024-07-01 01:24:01,899 [main] INFO [H5TileToN5PreviewClient]: exportPreview: view stack command is n5_view.sh -i /nrs/cellmap/data/jrc_alta24-b9_4nm/jrc_alta24-b9_4nm.n5 -d /render/jrc_alta24_b9_4nm/imaging_preview -o -2456,-2500,1
# /nrs/cellmap/data/jrc_alta24-b9_4nm/align/logs/spark/20240701_012303/logs/04-driver.log:2024-07-01 01:24:02,061 [main] INFO [H5TileToN5PreviewClient]: findMinZToRender: returning 5725, maxZ is 6780
# /nrs/cellmap/data/jrc_alta24-b9_4nm/align/logs/spark/20240701_012303/logs/04-driver.log:    Turnaround time :                            569 sec.
# /nrs/cellmap/data/jrc_mus-salivary-2/align/logs/spark/20240701_012310/logs/04-driver.log:2024-07-01 01:24:11,644 [main] INFO [H5TileToN5PreviewClient]: exportPreview: view stack command is n5_view.sh -i /nrs/cellmap/data/jrc_mus-salivary-2/jrc_mus-salivary-2.n5 -d /render/jrc_mus_salivary_2/imaging_preview -o -7465,-6580,1
# /nrs/cellmap/data/jrc_mus-salivary-2/align/logs/spark/20240701_012310/logs/04-driver.log:2024-07-01 01:24:11,790 [main] INFO [H5TileToN5PreviewClient]: findMinZToRender: returning 545, maxZ is 4620
# /nrs/cellmap/data/jrc_mus-salivary-2/align/logs/spark/20240701_012310/logs/04-driver.log:    Turnaround time :                            8300 sec.
# /nrs/reiser/data/jrc_sepia_MPI-S-DEC_5A/h5/align/logs/spark/20240701_012316/logs/04-driver.log:2024-07-01 01:24:20,894 [main] INFO [H5TileToN5PreviewClient]: exportPreview: view stack command is n5_view.sh -i /nrs/reiser/data/jrc_sepia_MPI-S-DEC_5A/jrc_sepia_MPI-S-DEC_5A.n5 -d /render/jrc_sepia_MPI_S_DEC_5A/imaging_preview -o -17456,-8417,1
# /nrs/reiser/data/jrc_sepia_MPI-S-DEC_5A/h5/align/logs/spark/20240701_012316/logs/04-driver.log:2024-07-01 01:24:21,112 [main] INFO [H5TileToN5PreviewClient]: findMinZToRender: returning 20886, maxZ is 21785
# /nrs/reiser/data/jrc_sepia_MPI-S-DEC_5A/h5/align/logs/spark/20240701_012316/logs/04-driver.log:    Turnaround time :                            7663 sec.

awk '
fname != FILENAME { 
  fname = FILENAME
  idx++ 
  file_name[idx] = FILENAME
}
/^\(spark.default.parallelism,/ {
  # (spark.default.parallelism,1500)
  split($0, fields, "[,]")
  active_slots = fields[2] / 3
  worker_slots[idx] = active_slots + (active_slots / 10)
}
/exportPreview: view stack command/ {
  # ... exportPreview: view stack command is n5_view.sh -i /nrs/...
  export_preview[idx] = $0
  sub(/.*n5_view.sh /, "", export_preview[idx])
}
/findMinZToRender/ {
  # ... findMinZToRender: returning 5725, maxZ is 6780
  min_z[idx] = $8
  max_z[idx] = $11
}
/Turnaround time/ {
  # Turnaround time :                            569 sec.
  turnaround_minutes[idx] = $4 / 60
}
END {
  for (i = 1; i <= idx; i++) {
    cost = ( turnaround_minutes[i] / 60 ) * worker_slots[i] * 0.07
    delta_z = max_z[i] - min_z[i]
    # printf("%-100s | $%6.2f, %3d min, %3d slots, %5d layers: z %5d to %5d | %s\n", file_name[i], cost, turnaround_minutes[i], worker_slots[i], delta_z, min_z[i], max_z[i], export_preview[i])
    printf("%-100s | $%6.2f, %3d min, %3d slots, %5d layers: z %5d to %5d\n", file_name[i], cost, turnaround_minutes[i], worker_slots[i], delta_z, min_z[i], max_z[i])
  }
}
' ${DRIVER_LOGS}

# /nrs/[cf]*/data/*/align/logs/spark/${DATE_PATTERN}*/logs/04-driver.log
# /nrs/r*/data/*/h5/align/logs/spark/${DATE_PATTERN}*/logs/04-driver.log
