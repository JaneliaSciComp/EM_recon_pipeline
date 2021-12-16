#!/bin/bash

# 10:39:10.612 [main] INFO  [org.janelia.render.client.MultiStagePointMatchClient] constructor: loaded stage parameters with slug crossPass1_SIFT_s0.05e03_i020_c050pct_GEO_s0.10e02_i020_c000pct_d006_he5c221c5755b6d30ae71d05c7ab2c2d7
# 10:39:10.613 [main] INFO  [org.janelia.render.client.MultiStagePointMatchClient] constructor: loaded stage parameters with slug crossPass2_SIFT_s0.10e06_i020_c050pct_GEO_s0.15e03_i020_c000pct_d006_heb563c5e96c307375423f1bfa3f449e4
# 10:39:10.614 [main] INFO  [org.janelia.render.client.MultiStagePointMatchClient] constructor: loaded stage parameters with slug crossPass3_SIFT_s0.15e09_i020_c050pct_GEO_s0.25e04_i020_c000pct_d006_h1588887f682e680539e3654936b5dac3
# 10:39:10.615 [main] INFO  [org.janelia.render.client.MultiStagePointMatchClient] constructor: loaded stage parameters with slug crossPass4_SIFT_s0.25e15_i150_c030pct_GEO_none_d003_hf28a03394b65a541a6057ee3954b6845
# 10:39:10.616 [main] INFO  [org.janelia.render.client.MultiStagePointMatchClient] constructor: loaded stage parameters with slug crossPass5_SIFT_s0.25e15_i020_c050pct_GEO_s0.50e08_i020_c000pct_d002_h0c1bbf386e3a58edde74fbd4678ccb30
# 10:39:10.617 [main] INFO  [org.janelia.render.client.MultiStagePointMatchClient] constructor: loaded stage parameters with slug crossPass6_SIFT_s0.25e05_i020_c000pct_GEO_none_d001_hcf19fc728aab5722162d347449db28bd
# ...
# 20:01:18.587 [main] INFO  [org.janelia.alignment.match.RenderableCanvasIdPairs] load: exit, loaded 60 pairs
# ...
# 20:08:55.431 [main] INFO  [org.janelia.render.client.MultiStagePointMatchClient] logStats: for stage crossPass0, saved matches for 3 out of 60 pairs (5%), siftPoorCoverage: 18, siftPoorQuantity: 39, siftSaved: 3, combinedPoorCoverage: 0, combinedPoorQuantity: 0, combinedSaved: 0, 
# 20:08:55.431 [main] INFO  [org.janelia.render.client.MultiStagePointMatchClient] logStats: for stage crossPass1, saved matches for 12 out of 57 pairs (21%), siftPoorCoverage: 23, siftPoorQuantity: 22, siftSaved: 12, combinedPoorCoverage: 0, combinedPoorQuantity: 0, combinedSaved: 0, 
# 20:08:55.431 [main] INFO  [org.janelia.render.client.MultiStagePointMatchClient] logStats: for stage crossPass2, saved matches for 10 out of 45 pairs (22%), siftPoorCoverage: 23, siftPoorQuantity: 12, siftSaved: 10, combinedPoorCoverage: 0, combinedPoorQuantity: 0, combinedSaved: 0, 
# 20:08:55.431 [main] INFO  [org.janelia.render.client.MultiStagePointMatchClient] logStats: for stage crossPass3, saved matches for 15 out of 35 pairs (42%), siftPoorCoverage: 8, siftPoorQuantity: 12, siftSaved: 15, combinedPoorCoverage: 0, combinedPoorQuantity: 0, combinedSaved: 0, 
# 20:08:55.431 [main] INFO  [org.janelia.render.client.MultiStagePointMatchClient] logStats: for stage crossPass4, saved matches for 12 out of 20 pairs (60%), siftPoorCoverage: 0, siftPoorQuantity: 8, siftSaved: 12, combinedPoorCoverage: 0, combinedPoorQuantity: 0, combinedSaved: 0, 
# 20:08:55.431 [main] INFO  [org.janelia.render.client.ClientRunner] run: exit, processing completed in 0 hours, 7 minutes, 37 seconds

awk '
BEGIN {
  job_count = 0
  job_total_seconds = 0
  max_job_seconds = 0
}

/loaded stage parameters with slug/ {
  stage = substr($11, 1, index($11, "_") - 1)
  slug[stage] = $11
}

/Pass., saved matches for/ {
  gsub(/,/, "")
  stage = $8
  totalSaved[stage] += $12
  totalProcessed[stage] += $15
  siftPoorCoverage[stage] += $19
  siftPoorQuantity[stage] += $21
  siftSaved[stage] += $23
  combinedPoorCoverage[stage] += $25
  combinedPoorQuantity[stage] += $27
  combinedSaved[stage] += $29
}

/run: exit, processing completed in/ {
  job_count++
  job_seconds = ((3600 * $10) + (60 * $12) + $14)
  job_total_seconds += job_seconds
  if (job_seconds > max_job_seconds) {
    max_job_seconds = job_seconds
  }
  if ((job_count % 200) == 0) {
    printf "."
    system("")
  }
}

END {
  printf "\n\n"
  printf "%-15s  %9s  %9s  %9s  %9s  %9s  %9s  %9s  %9s  %9s  %s\n", "",                        "",           "",          "",          "",          "",          "",          "",          "",          "", "      [stage name]_"
  printf "%-15s  %9s  %9s  %9s  %9s  %9s  %9s  %9s  %9s  %9s  %s\n", "",                        "",           "",          "",          "",          "",      "SIFT",      "SIFT",  "Combined",  "Combined", "      SIFT_s[render scale]e[epsilon]_i[inliers]_c[coverage]pct_"
  printf "%-15s  %9s  %9s  %9s  %9s  %9s  %9s  %9s  %9s  %9s  %s\n", "",                   "Total",      "Total",   "Percent",      "SIFT",  "Combined",      "Poor",      "Poor",      "Poor",      "Poor", "      GEO_s[render scale]e[epsilon]_i[combined inliers]_c[combined coverage]pct_"
  printf "%-15s  %9s  %9s  %9s  %9s  %9s  %9s  %9s  %9s  %9s  %s\n", "Stage",           "Processed",     "Saved",     "Saved",     "Saved",     "Saved",  "Quantity",  "Coverage",  "Quantity",  "Coverage", "Slug: d[delta z]_h[parameter hash]"
  printf "%-15s  %9s  %9s  %9s  %9s  %9s  %9s  %9s  %9s  %9s  %s\n", "---------------", "---------", "---------", "---------", "---------", "---------", "---------", "---------", "---------", "---------", "-----------------------------------------------------------------------------------------------------------"
  processed_pair_count = 0
  saved_pair_count = 0
  for (stage in totalSaved) {
    pass_pair_count = totalSaved[stage]
    processedPercentage = 0
    if (totalProcessed[stage] > 0) {
      processedPercentage = totalSaved[stage] / totalProcessed[stage] * 100
    }
    printf "%-15s  %9d  %9d  %9.1f  %9d  %9d  %9d  %9d  %9d  %9d  %s\n", stage, totalProcessed[stage], totalSaved[stage], processedPercentage, siftSaved[stage],  combinedSaved[stage],  siftPoorQuantity[stage],  siftPoorCoverage[stage],  combinedPoorQuantity[stage],  combinedPoorCoverage[stage], slug[stage]
    if (totalProcessed[stage] > processed_pair_count) {
      processed_pair_count = totalProcessed[stage]
    }
    saved_pair_count += totalSaved[stage]
  }

  if ((processed_pair_count > 0) && (job_count > 0)) {

    average_seconds_per_pair = job_total_seconds / processed_pair_count
    printf "\n"
    printf "%-30s %9d\n", "processed_pair_count:", processed_pair_count
    printf "%-30s %9d\n", "saved_pair_count:", saved_pair_count
    printf "%-30s %12.2f\n", "average_seconds_per_pair:", average_seconds_per_pair

    average_minutes_per_job = (job_total_seconds / 60) / job_count
    max_job_minutes = max_job_seconds / 60
    printf "\n"
    printf "%-30s %9d\n", "jobs:", job_count
    printf "%-30s %12.2f\n", "average_minutes_per_job:", average_minutes_per_job
    printf "%-30s %12.2f\n", "max_job_minutes:", max_job_minutes

  }
}
' $*

