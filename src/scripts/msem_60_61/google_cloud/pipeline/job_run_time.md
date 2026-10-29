# Job Run Time Estimate: w61 Serial Slabs 070 to 199

Estimated time to run serial slabs 070 to 199 through `00_par_run` to `05_pixel_export_run`
with 13 VMs (`aaa` to `aam`).  Estimated 2026-10-26.

## Summary

| Approach                                                        | Typical               | Range        |
|-----------------------------------------------------------------|-----------------------|--------------|
| **Batch each project through all stages on one VM** (with dumps)| **~62 h (2 days 14 h)** | 57.6 to 64.5 h |
| Start each run as soon as its own inputs are ready (any VM)     | ~62 h (2 days 14 h)   | 57.4 to 64.4 h |
| Stage by stage (finish a stage for all slabs before the next)   | ~64 h (2 days 16 h)   | 59.3 to 66.3 h |

All three approaches take about the same time.  The differences (about 2 h) are smaller than the
uncertainty in the run times.

Batching each project through all stages is a good choice because it takes no longer and skips the
data loads between stages, including the 30 minute match collection loads.  It only works this well if
**freed cores go to the earliest stage first**: when cores free up, start the next 00 to 02 run before
starting more 03 to 05 work.  If cores go to whichever project is next in line instead, batching takes
about 70 h (see below).

The estimates do not include time to launch runs, overnight gaps, failures, or reruns.

## Stage Breakdown

These are the stage times when each stage runs by itself.  The approaches above overlap them in different ways.

| Stage                        | Runs                       | At once (limit)              | Time per run (from comments)  | Stage time |
|------------------------------|----------------------------|------------------------------|-------------------------------|------------|
| 00 par, 120 executors        | 24                         | 6 (cores: 484 per run)       | ~7 h                          | 28 h       |
| 01 match, 120 executors      | 24                         | 6 (cores)                    | ~90 min                       | 6 h        |
| 01 creep, 10 executors       | 24                         | 13 (VMs)                     | 15 min                        | 0.5 h      |
| 02 align, 120 executors      | 24                         | 6 (cores)                    | ~90 min                       | 6 h        |
| 03 ic2d, 50 executors        | 13                         | 13 (VMs: 204 cores per run)  | typically 4 to 5 h (2 to 5 h) | ~4.5 h     |
| 04 3d align, 50 executors    | 13                         | 13 (VMs)                     | 60 min                        | 1 h        |
| 05 pixel export, 5 executors | 240 jobs (130 r00, 110 r01)| ~125 jobs (cores: 24 per job)| r00 7 to 9 h, r01 2.5 to 3.5 h| ~14 to 18 h|
| **Compute total**            |                            |                              |                               | **~62 h**  |

The 484 core runs in stages 00 to 02 add up to about 40 h of the total, and they are the bottleneck
for every approach.

## Assumptions

- **Run times** come from the comments in the `load_data_for_*` scripts.
  Where a range is given, the low, typical, and high totals use the low, middle, and high values.
- **Executor counts** are the ones currently set on the `02_run_pipeline.sh` and
  `11_run_n5_export.sh` lines in each script.
  Each executor and each driver has 4 cores, so a 120 executor run uses 484 cores.
- **Core budget** is about 3,000 cores.
  Every "N concurrent runs will use ..." comment in the scripts stays below that.
- **Run sizes**:
  - Stages 00 to 02 run 5 slabs at a time for serials 070 to 179 (two regions, r00 and r01)
    and 10 slabs at a time for 180 to 199 (r00 only), so each of those stages has 24 runs.
  - Stages 03 to 05 run one 10 slab project at a time (070 to 190), so each has 13 runs.
  - Stage 05 submits one export job per `_asoi_3d` stack: 20 per two region project and
    10 per one region project.
- **Data loads** (only needed when a run's data is not already on its VM):
  - 30 minutes for runs that start from match collections (01 loads the par matches, 02 loads the
    creep matches), because each run loads about 10 match collections at about 3 minutes each.
  - 1 to 2 minutes for the other runs.
- **Dumps** are made after every run in every approach, so that data can be corrected or reviewed later.
  They take the times given in the script comments (up to about 10 minutes for a match collection).
- **A run holds its VM** while it loads, computes, and dumps.  Loads and dumps use no Spark cores.
- **Batched projects** stay on one VM each (13 projects for 13 VMs), and the two 5 slab halves of a
  two region project run one after the other on that VM during stages 00 to 02.
- **Removing data** that is no longer needed takes about as long as a short load (1 to 2 minutes).

## Why the Approaches End Up Close

- **Cores, not VMs, limit stages 00 to 02.**  Six 484 core runs use 2,904 of the 3,000 cores,
  so only 6 runs compute at a time no matter how they are ordered.
- **Loads and dumps cost little.**  They hold VMs but use no cores, and there are spare VMs during
  stages 00 to 02.  Including or skipping the dumps changes the estimates by less than 1 h.
  - Stage by stage, the idle VMs can load the next wave's data while the current wave computes,
    so only the first wave of each stage waits for its loads.
  - Batched, the data is already on the VM, so there is nothing to wait for.
- **Core priority matters most.**  When a cheap task (an ic2d run or a project's exports) takes cores
  that a 484 core run could have used, only 5 of the 484 core runs fit, and most of the freed cores
  go unused.  Giving freed cores to the earliest stage first keeps 6 of those runs going, and the
  cheap stages use the leftover cores as the heavy work winds down.

## Other Options Considered

- **Batching with cores going to the next project in line** (~70 h).  Cheap stages of the first
  projects take cores from the heavy stages of later ones, which spreads the 40 h of heavy work out.
  Giving the cheap stages priority, or the project with the most heavy work left, was no better (~67 to 69 h).
- **Stage by stage for 00 to 02, then batch 03 to 05 per project** (~62 h, the same as stage by stage
  compute).  This saves only the short 1 to 2 minute loads, because 03 to 05 already move in lockstep.
- **Change executor counts**:
  - **00 par with 400 executors** (~3 h per run) fits only one run at a time, which makes stage 00
    take about 72 h instead of 28 h.
  - **01 match with 25 executors** (~6 h per run, 13 at once) or **300 executors** (40 min, 2 at once)
    take about 12 h and 8 h, both slower than 6 h with 120 executors.
  - **02 align with 200 executors** took 20 minutes for one run (w61-s170-to-s174).  If that holds
    for the other slab groups, 3 runs at once would bring stage 02 from 6 h down to under 3 h.
  - **Fewer executors for the heavy stages** might leave room for other stages to overlap, but none of
    the script comments show how those runs scale with fewer executors.
- **Stage 05 job order**: starting a few r01 exports before the last r00 exports frees their core slots
  sooner and could bring stage 05 closer to 11 to 14 h.
- **A larger core quota**: with about 6,300 cores (13 x 484), every VM could run its own project through
  all stages with no waiting.  The whole run would then take about 34 h, which is the time for one two
  region project to finish every stage.

## Not Included

- `load_data_for_05_sofima_import.sh` and `load_data_for_06_ic3d_run.sh`
- the optional MFOV-as-tile reruns that are commented out in `load_data_for_00_par_run.sh`
- separate downsample-only and mask export passes for stage 05
- time to launch runs, overnight gaps, failures, and reruns
