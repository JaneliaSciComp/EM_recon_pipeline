#!/bin/bash

# Prints volume compute costs based upon logs in the specified render align directory.

set -euo pipefail

# /groups/fibsem/fibsem/render/align/jrc_hela-L63-1
RENDER_ALIGN_DATA_SET_DIR=$(readlink -m "${1:-.}")

LAUNCH_SPARK_LOGS_DIR="${RENDER_ALIGN_DATA_SET_DIR}/logs"

if [ ! -d "${LAUNCH_SPARK_LOGS_DIR}" ]; then
  printf "\nERROR: %s not found\n\nData set directory should be something like /groups/fibsem/fibsem/render/align/jrc_hela-L63-1\n\n" "${LAUNCH_SPARK_LOGS_DIR}"
  exit 1
fi

RATE_PER_SLOT_HOUR="0.05"

TOTAL_SPARK_COST=0
TOTAL_LSF_COST=0

printf "\nCompute costs for %s\n\n" "${RENDER_ALIGN_DATA_SET_DIR}"
printf "%-70s %10s %10s %10s\n" "" "Slots" "Seconds" "Cost"
printf "Spark Jobs:\n"

# Only files immediately under LAUNCH_SPARK_LOGS_DIR that contain "spark-janelia"
while IFS= read -r -d '' f; do
  # Process gawk output so we can both print job lines and sum costs
  while IFS= read -r line; do
    if [[ $line == __COST__=* ]]; then
      v=${line#__COST__=}
      TOTAL_SPARK_COST=$(awk -v a="$TOTAL_SPARK_COST" -v b="$v" 'BEGIN { printf "%.6f", a+b }')
    else
      printf "%s\n" "$line"
    fi
  done < <(
    gawk -v FULLPATH="$f" -v RATE="$RATE_PER_SLOT_HOUR" '
      function basename(path,   n,a) { n=split(path,a,"/"); return a[n] }

      function read_runtime_secs(driverlog,   line, a, secs, rc) {
        secs = 0
        while ((rc = (getline line < driverlog)) > 0) {
          if (match(line, /Run time[^0-9]*([0-9]+)[[:space:]]*sec/, a)) {
            secs = a[1] + 0
            break
          }
        }
        close(driverlog)
        return secs
      }

      function parse_spark_line(line,   a) {
        if (match(line, /--nnodes=([0-9]+)/, a))        nnodes       = a[1] + 0
        if (match(line, /--worker_slots=([0-9]+)/, a))  worker_slots = a[1] + 0
        if (match(line, /--driverslots=([0-9]+)/, a))   driverslots  = a[1] + 0
      }

      FNR==1 {
        logsdir = ""
        driverlog = ""
        compute_seconds = 0
        nnodes = worker_slots = driverslots = 0
        have_spark = 0
      }

      $0 ~ /^  \/groups\/.*\/logs$/ {
        logsdir = $1
        driverlog = logsdir "/04-driver.log"
        compute_seconds = read_runtime_secs(driverlog)
      }

      /spark-janelia/ {
        have_spark = 1
        parse_spark_line($0)
      }
      END {
        if (have_spark) {
          compute_slot_count = driverslots + (nnodes * worker_slots)
          compute_cost = compute_slot_count * (compute_seconds / 3600.0) * RATE

          printf "  %-68s %10d %10d %10s\n",
                 basename(FULLPATH),
                 compute_slot_count,
                 compute_seconds,
                 sprintf("$%.2f", compute_cost)

          # machine-readable line for bash to sum (not shown in final output)
          printf "__COST__=%.6f\n", compute_cost
        }
      }
    ' "$f"
  )
done < <(
  find "$LAUNCH_SPARK_LOGS_DIR" -maxdepth 1 -type f -print0 \
  | xargs -0 grep -lZ "spark-janelia"
)

printf "%-70s %10s %10s %10s\n" "Spark TOTAL:" "" "" "$(awk -v c="$TOTAL_SPARK_COST" 'BEGIN{printf "$%.2f", c}')"
printf "\nLSF Batch Jobs:\n"

shopt -s nullglob

for BATCH_LOGS_DIR in "${RENDER_ALIGN_DATA_SET_DIR}"/run*/logs; do
  if [[ -d "${BATCH_LOGS_DIR}" ]]; then
    BATCH_RUN_DIR=$(dirname "${BATCH_LOGS_DIR}")
    RUN_NAME=$(basename ""${BATCH_RUN_DIR})

    SECONDS=$(
      awk '
        /processing (completed in|failed after)/ {
          h=m=s=0
          if (match($0, /([0-9]+) hours?/, a))   h=a[1]
          if (match($0, /([0-9]+) minutes?/, a)) m=a[1]
          if (match($0, /([0-9]+) seconds?/, a)) s=a[1]
          total += h*3600 + m*60 + s
        }
        END { print total+0 }
      ' "$BATCH_LOGS_DIR"/* 2>/dev/null
    )

    # numeric cost with more precision for summing
    COST_NUM=$(awk -v s="$SECONDS" -v r="$RATE_PER_SLOT_HOUR" 'BEGIN { printf "%.6f", (s/3600)*r }')
    TOTAL_LSF_COST=$(awk -v a="$TOTAL_LSF_COST" -v b="$COST_NUM" 'BEGIN { printf "%.6f", a+b }')

    SLOTS=1
    printf "  %-68s %10s %10s %10s\n" "$RUN_NAME" "$SLOTS" "$SECONDS" "$(awk -v c="$COST_NUM" 'BEGIN{printf "$%.2f", c}')"
  fi
done

printf "%-70s %10s %10s %10s\n" "LSF Batch TOTAL:" "" "" "$(awk -v c="$TOTAL_LSF_COST" 'BEGIN{printf "$%.2f", c}')"

GRAND_TOTAL=$(awk -v a="$TOTAL_SPARK_COST" -v b="$TOTAL_LSF_COST" 'BEGIN{printf "%.6f", a+b}')
printf "\nGrand TOTAL Compute Cost: %s\n\n" "$(awk -v c="$GRAND_TOTAL" 'BEGIN{printf "$%.2f", c}')"