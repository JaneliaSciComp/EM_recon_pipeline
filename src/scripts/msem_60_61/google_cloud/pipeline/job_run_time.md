# Job Run Time Estimate: w61 Serial Slabs 000 to 069 (r00 Only)

Estimated time to run the r00 stacks of serial slabs 000 to 069 through `00_par_run` to
`04e_pixel_export_runs` (called stage 05 in the 070 to 199 estimate below), with `--regions r00`.  Estimated 2026-11-20.

The 00, 01, and 02 scripts now launch with 50 executors (for the 14 VM approach).  The 7 VM rows and
the stage breakdown use the earlier 60 executor setting, so edit the `02_run_pipeline.sh` line if you
run that way instead.

## Summary

| Approach                                                              | Typical               | Range      |
|-----------------------------------------------------------------------|-----------------------|------------|
| **7 VMs, one per project, halves one after the other (60 executors)** | **~40 h (1 day 16 h)** | 33 to 45 h |
| Same, with 100 executors for 00 to 02                                 | ~33 h (1 day 9 h)     | 27 to 37 h |
| 14 VMs (`aaa` to `aan`), every half at once, 50 executors for 00 to 02  | ~28 h (1 day 4 h)     | 23 to 32 h |

The 00 to 02 runs are 5 slabs (5 r00 stacks) each, because 10 of these large r00 stacks make too much
match data for one VM.  So there are 14 half project runs, and since a run holds its VM, the
number of VMs decides how many of them can run at once:

- **7 VMs** run the two halves of each project one after the other, which doubles the 00 to 02 time
  (about 27 of the 40 h), but uses only about 1,700 cores.
- **13 VMs are not enough to run every half at once.**  With 13 VMs, the 14th half has to wait for a
  VM, so its project takes as long as with 7 VMs (~40 h).  At 60 executors only 12 halves fit in the
  cores anyway (12 x 244 = 2,928).
- **14 VMs** (with the new `aan` VM) and 50 executors fit all 14 halves at once in
  2,856 cores, which is the fastest option.

The estimates do not include time to launch runs, overnight gaps, failures, or reruns.

## Stage Breakdown (7 VMs, 60 Executors)

| Stage                         | Runs           | Cores at once            | Time per run (comment time)    | Time per run (this batch) |
|-------------------------------|----------------|--------------------------|--------------------------------|---------------------------|
| 00 par, 60 executors          | 14 (7 at once) | 1,708 (7 x 244)          | ~11 h                          | ~8.7 h (7.8 to 9.5 h)     |
| 01 match, 60 executors        | 14 (7 at once) | 1,708                    | not recorded (~2.8 h, see below) | ~2.2 h (2 to 2.4 h)     |
| 01 creep, 10 executors        | 14 (7 at once) | 308 (7 x 44)             | 15 min                         | ~12 min                   |
| 02 align, 60 executors        | 14 (7 at once) | 1,708                    | ~2 h                           | ~1.6 h (1.4 to 1.7 h)     |
| Dumps and loads for each half |                | none                     |                                | ~40 min                   |
| **00 to 02, both halves**     |                |                          |                                | **~27 h (24 to 29 h)**    |
| 03 ic2d, 50 executors         | 7              | 1,428 (7 x 204)          | typically 4 to 5 h (2 to 5 h)  | ~3.6 h (1.4 to 4.3 h)     |
| 04 3d align, 50 executors     | 7              | 1,428                    | 60 min                         | ~50 min                   |
| 04e pixel export, 5 executors | 70 jobs (r00)  | 1,680 (70 x 24)          | r00 7 to 9 h                   | ~8.8 h (7 to 10.8 h)      |
| **Total for one project**     |                |                          |                                | **~40 h (33 to 45 h)**    |

## Assumptions

- **Stack size**: these r00 stacks get larger toward s000 and are much larger than their r01 stacks.
  The estimate assumes they are 1.0 to 1.2 times the size of the 070 to 199 r00 stacks (1.1 typical),
  and that an r01 stack there takes 0.4 times as long as an r00 stack (the ratio of the r01 and r00
  pixel export times).  So:
  - a 5 r00 stack run is about 0.8 (0.7 to 0.86) times the work of the 5 r00 plus 5 r01 stack runs
    that the 00 to 02 comment times are for,
  - a 10 r00 stack project is about 0.8 times the work of the whole two region projects that the
    03 and 04 comment times are for, and
  - a 04e r00 export takes 1.0 to 1.2 times the 7 to 9 h comment time.
  If you have run times for any of these slabs, they would be a better basis than this guess.
- **01 match at 60 executors** has no recorded time ("~? hours" in the script).  The 2.8 h comes from
  interpolating between the 25 executor (~6 h) and 120 executor (~90 min) times.
- **Other executor counts** are interpolated the same way between the script comment times (in log-log
  scale).  None of the 50 or 100 executor times for 00 to 02 have been measured.
- **Cores**: each executor and driver has 4 cores, and the core quota is about 3,000.  With 7 VMs,
  about 1,300 cores are left for other work (for example hot-knife or 070 to 199 jobs).  The other two
  approaches use nearly all of the cores during 00 to 02.
- **Dumps** after every run take the times in the script comments (about 13 min after 00 and 21 min
  after 01), and each 00 and 03 run starts with a 1 to 2 minute load.
- **The halves** of a project use the same VM, so the second half starts after the first half's
  02 dump, and 03 starts after the second half's 02 dump.

## Faster Options

- **100 executors for 00 to 02 with 7 VMs** (7 x 404 = 2,828 cores): each half's 00 to 02 takes about
  9 h instead of 13 h, saving about 7 h overall.  It leaves no cores for other work during the first
  ~20 h, and uses more core hours (about 20% more for 00 par).
- **14 VMs with 50 executors**: every half runs 00 to 02 at once, which takes about 15 h, so the whole
  batch takes about 28 h.  The 14th VM (`aan`, letter N) runs the half that would otherwise wait.

Time the first runs before relying on either option.

## Not Included

- the 05 SOFIMA import and later stages (`load_data_for_05_sofima_import.sh` onward)
- the r01 stacks for these slabs (to be run later with `--regions r01`)
- the optional MFOV-as-tile reruns in `load_data_for_00_par_run.sh`
- separate downsample-only and mask export passes for 04e
- time to launch runs, overnight gaps, failures, and reruns

---

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
