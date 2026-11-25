# Summarize `gcloud dataproc batches list --format=json` output as TSV.
# Usage: jq -r -f summarize_batches.jq dataproc_batches.<date>.json > dataproc_batches.<date>.tsv
#
# Download the input with:
#   gcloud dataproc batches list --region=us-east4 --project=janelia-ibeam \
#     --filter='create_time>="2026-10-27T00:00:00Z"' --limit=unlimited --format=json > dataproc_batches.<date>.json
#
# One row per batch, oldest first.  queue_min is PENDING to RUNNING, run_min is RUNNING to the final state.
# slab_count comes from the batch id range (s410-to-s414 counts 5 even if only 3 slabs exist).
def secs: sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;
def mins(a; b): if a and b then (((b | secs) - (a | secs)) / 60 | floor) else null end;
def prop(k): .runtimeConfig.properties["spark:spark." + k] // "";
def arg(k): (.sparkBatch.args | index(k)) as $i | if $i then .sparkBatch.args[$i + 1] else "" end;

["batch_id", "kind", "step", "wafer", "first_slab", "last_slab", "slab_count", "state",
 "create_utc", "queue_min", "run_min", "dcu_hours", "tier", "executors", "exec_cores",
 "exec_mem", "main_class", "detail"],
(sort_by(.createTime)[]
 | (.name | split("/") | last) as $id
 | ($id | capture("^(?<kind>rp|rex|hf-surface|cost-hf)-[0-9]{8}-[0-9]{6}-(?<rest>.*)$")) as $p
 | (if $p.kind == "rp"
    then ($p.rest | capture("^(?<step>.*)-w(?<w>6[01])-s(?<a>[0-9]{3})(-to-s(?<b>[0-9]{3}))?$"))
    else ($p.rest | capture("^w(?<w>6[01])-s(?<a>[0-9]{3})-r[0-9]{2}-(?<step>.*)$")) end) as $s
 | ($s.b // $s.a) as $last
 | (.stateHistory // [] | map(select(.state == "RUNNING")) | .[0].stateStartTime) as $runStart
 | [$id, $p.kind, (if $p.kind == "rp" then $s.step else ($p.kind + ":" + $s.step) end),
    "w" + $s.w, $s.a, $last, (($last | tonumber) - ($s.a | tonumber) + 1),
    .state, (.createTime | sub("\\.[0-9]+Z$"; "Z")),
    mins(.createTime; $runStart), mins($runStart; .stateTime),
    ((.runtimeInfo.approximateUsage.milliDcuSeconds // "0" | tonumber) / 3600000 | . * 10 | round / 10),
    (.runtimeConfig.properties["dataproc:dataproc.tier"] // ""),
    (if prop("dynamicAllocation.enabled") == "true" then "dyn<=" + prop("dynamicAllocation.maxExecutors") else prop("executor.instances") end),
    prop("executor.cores"), prop("executor.memory"),
    (.sparkBatch.mainClass | split(".") | last),
    (arg("--pipelineJson") | split("/") | last) + arg("--n5Dataset")]
)
| @tsv
