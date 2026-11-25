# Dataproc Job Run Times for Wafers 60 and 61

Measured run times from the 1,054 render pipeline and export Dataproc batches created between
2026-10-28 and 2026-11-24 (UTC): w61 serial slabs 070 to 199 (stages 00 to 07), w61 000 to 069
(stages 00 to 04d), and w60 410 to 412 (stages 00 to 04b).  The hot-knife cost and heightfield
batches are not included.  Use these to plan future runs.  The earlier estimates that this file
used to hold are in git history.

## Planning Table

Run time is the median batch time from RUNNING to done, with the range in parentheses.
Cores are executors x executor cores + 4 driver cores.  DCU-h is Dataproc's own usage measure
(`approximateUsage.milliDcuSeconds`) per slab for pipeline runs and per stack for exports.

| Stage (script)                    | Batch size  | Current setting  | Cores | w61 070-179                                 | w61 000-069               | DCU-h (070-179) |
|-----------------------------------|-------------|------------------|-------|---------------------------------------------|---------------------------|-----------------|
| 00 par (`00_par_run`)             | 5 slabs     | 50 x 4           | 204   | 9.2 h (7.8-10.5) at 60, 6.0 h at 120        | 16.1 h (12.8-19.5)        | 2,115 per slab  |
| 00 MAT rerun (optional)           | 5 slabs     | 120 x 4          | 484   | 0.4 h (0.4-1.7)                             | 0.5 h (one run)           | 182 per slab    |
| 01 match (`01_match_runs`)        | 5 slabs     | 50 x 4           | 204   | 2.0 h (1.5-2.5) at 60, 1.4 h at 120         | 3.9 h (3.4-4.8)           | 447 per slab    |
| 01 creep (`01_match_runs`)        | 5 slabs     | 10 x 4           | 44    | 0.2 h                                       | 0.3 h                     | 7 per slab      |
| 02 align (`02_align_run`)         | 5 slabs     | 50 x 4           | 204   | 1.6 h (1.2-2.0) at 60, 1.3 h at 300         | 2.5 h (1.9-2.9)           | 373 per slab    |
| 03 ic2d (`03_correct_intensity_run`) | 10 slabs | 100 x 4          | 404   | 3.6 h (3.1-4.3) at 50                       | 3.5 h (3.4-4.4)           | 345 per slab    |
| 04a 3d align (`04a_3d_align_run`) | 10 slabs    | 50 x 4           | 204   | 1.0 h (0.7-1.2)                             | 1.2 h (1.1-1.9)           | 93 per slab     |
| 04b pixel export, r00             | 1 stack     | 5 x 4            | 24    | 5.3 h (4.4-6.3)                             | 6.4 h (5.0-11.9)          | 169 per stack   |
| 04b pixel export, r01             | 1 stack     | 5 x 4            | 24    | 1.7 h (0.6-2.4)                             | 2.7 h (2.2-3.2)           | 53 per stack    |
| 04c remove problem layers         | 10-20 slabs | 2 x 4 standard   | 12    |                                             | under 0.1 h               | 0               |
| 04d problem export, r00 / r01     | 1 stack     | 10 x 4           | 44    |                                             | 5.2 h (3.1-5.7) / 1.5 h   | 309 / 90 per stack |
| 05 SOFIMA import (`05_sofima_import`) | 10 slabs | 20 x 4          | 84    | 0.1-0.2 h                                   |                           | 5 per slab      |
| 06a ic3d (`06a_ic3d_run`)         | 10 slabs    | 20 x 16          | 324   | 11.5 h (9.2-12.6), 9.0 h for r00-only 180-199 |                         | 1,736 per slab  |
| 06b ic3d pixel export, r00 / r01  | 1 stack     | 5 x 4            | 24    | 6.0 h (4.9-7.8) / 1.6 h (0.6-2.9)           |                           | 192 / 51 per stack |
| 06b ic3d mask export, r00 / r01   | 1 stack     | 5 x 4            | 24    | 2.0 h (1.7-2.6) / 0.6 h (0.2-0.9)           |                           | 64 / 18 per stack |
| 07 inpaint (`07_inpaint_run`)     | 10-30 slabs | 5 x 4 per 10 slabs | 24-64 | 5.5 h (10 slabs), 5.7 h (20), 4.9 h (30)  |                           | 17 per slab     |

The 22 `_aso` review exports (`rex-...-aso-pixel`) in the same period took r00 0.8 h at 40 x 4, r01 0.4 h at 30 x 4.

## Rules of Thumb

- **Cores are the limit, not Dataproc capacity.**  Median queue time was 0 to 1 minute for every
  stage.  The quota is about 3,000 cores, and the peak in use was 2,928 (12 runs of 244 cores on 10-28).
- **Batches stop after 24 h.**  Every batch has `ttl: 86400s`.  One 06a ic3d run with 20 x 4
  executors was killed at exactly 24.0 h.  The slowest 00 par run (19.5 h for w61 000-069) was close
  to the limit, so give large slabs more executors or a larger ttl.
- **Slab size matters more than anything else.**  In executor-hours, the w61 000-069 runs were
  1.2 to 1.9 times the 070-179 runs (00 par 1.5, 01 match 1.6, 02 align 1.3, 03 ic2d 1.9,
  04a 1.2, 04b r00 1.2, 04b r01 1.6).  The w60 410-412 stacks were about 3.5 to 4 times a w61 070-179
  r00 stack (00 par: 12.0 h at 50 executors for 3 stacks; 04b: 1.4 h at 75 executors per stack).
- **An r01 export takes about 0.3 times as long as an r00 export** (0.4 for w61 000-069).
- **More executors help less than linearly**, from the few runs with other settings:
  - 00 par, 60 to 120: 1.5 times faster.
  - 01 match, 60 to 120: 1.4 times faster.
  - 02 align, 60 to 300: only 1.2 times faster, at 4 times the DCU-h.
  - Exports, 5 to 10: 1.7 times faster for pixel exports and for mask exports.
- **00 par and 06a ic3d use the most.**  For a two region w61 070-179 slab, all stages together use
  about 5,700 DCU-h: 00 par 37%, 06a ic3d 31%, 01 match 8%, 02 align 7%, 03 ic2d 6%, exports 10%.
  The pipeline (`rp-`) batches run on the premium tier and the exports on the standard tier,
  so compare DCU-h only within a tier.

## Whole Runs

Wall time from the first batch starting to the last one finishing (UTC), including failures, reruns,
launch gaps, and overnight waits.

| Run                                          | Start       | End         | Wall time | Notes |
|----------------------------------------------|-------------|-------------|-----------|-------|
| w61 070-199, 00 to 04b                       | 10-28 00:42 | 10-31 22:54 | 94 h      | 24 halves for 00 to 02, mostly at 60 executors; 6 failed 00 par runs |
| w61 070-199, 05 to 07                        | 11-13 21:29 | 11-16 04:02 | 54.5 h    | after earlier 05 and 06a attempts on 070-079 (11-07 to 11-10) |
| w61 000-069, 00 to 04b first pass            | 11-20 11:09 | 11-22 14:52 | 52 h      | 14 halves at 50 executors |
| w61 000-069, 04c and 04d                     | 11-23 20:04 | 11-24 09:00 | 13 h      | 14 re-exports at 10 executors |
| w60 410-412, 00 to 04b                       | 11-23 00:42 | 11-23 21:14 | 20.5 h    | one region, 3 slabs, 50 to 300 executors |

The w61 000-069 stages, measured as first start to last finish:

| Stage               | Batches        | Span   | Estimated on 11-21 |
|---------------------|----------------|--------|--------------------|
| 00 par              | 13 (+1 failed) | 19.5 h | 13.3 h per run     |
| 01 match and creep  | 14 + 14        | 7.7 h  | 3.8 h per run      |
| 02 align            | 14             | 2.9 h  | 2.3 h per run      |
| 03 ic2d             | 7              | 4.4 h  | 4.8 h per run      |
| 04a 3d align        | 7              | 1.9 h  | 65 min per run     |
| 04b pixel export    | 114            | 11.9 h | 12 h               |

The estimate for 00 to 04b was 38 h (31 to 43 h).  It took 52 h, mostly because 00 par took 16 h
per run instead of 13 h and the slowest run set the pace (19.5 h).  The gaps between stages for dumps,
loads, and launching added about 3 h.

06a ic3d uses 324 cores per run, so all 13 w61 070-199 projects at once would need 4,212 cores.
They ran in two waves: 7 starting 11-13 22:19 (10 to 12 h) and 6 starting 11-14 12:09 (9 to 11 h).

## Failures

16 of the 1,054 batches failed or were cancelled.  The long ones cost the most:

- **00 par** (6): five 60 executor runs submitted on 10-29 failed after 7 to 22 h.  Two of them
  (140-144 and 190-199) failed at the same moment on 10-30 13:43 with `Internal Server Error`.
  w61 000-004 failed after 16.4 h and was finished with a 30 minute MAT rerun.
- **06a ic3d** (2): the 20 x 4 run hit the 24 h ttl, and a 20 x 16 run failed after 11.6 h.
- **05 SOFIMA import** (1): a 25 x 4 run failed after 18.5 h.  Good runs take under 15 minutes.
- **07 inpaint** (5): one failed at start, and four were cancelled after about 1 h.
- **03 ic2d** (1, a timeout at start) and **04b export** (1, after 1.4 h).

When planning, allow time to rerun at least one 00 par half, and check long runs well before
they are expected to finish.

## Not Measured Here

- Work on the VMs that uses no Dataproc cores: database loads and dumps, launching runs, and the
  SOFIMA alignment between 04 and 05.  These show up only as gaps between stages.
- How a single slab would run alone.  Times per slab in the planning table are batch times divided by
  slab count, not single slab run times.

## Updating These Numbers

```bash
gcloud dataproc batches list --region=us-east4 --project=janelia-ibeam \
  --filter='create_time>="2026-10-27T00:00:00Z" AND create_time<="2026-11-25T00:00:00Z"' \
  --limit=unlimited --format=json > dataproc_batches.<date>.json

jq -r -f ../dataproc/summarize_batches.jq dataproc_batches.<date>.json > dataproc_batches.<date>.tsv
```

The `create_time` limits are UTC.  Drop the `AND create_time<=...` part to include everything up to now.

The TSV has one row per batch with the stage, wafer, slab range, state, queue and run minutes,
DCU-hours, tier, and executor settings parsed from the batch id and properties.
The batch id steps map to stages as follows:

| Batch id step              | Stage                |
|----------------------------|----------------------|
| `rough`, `rough-mat`       | 00 par, 00 MAT rerun |
| `match`, `creep`           | 01                   |
| `aso`                      | 02                   |
| `ic2d`                     | 03                   |
| `a3d`                      | 04a                  |
| `rex ... asoi-3d-pixel`    | 04b and 04d          |
| `remove-layers`            | 04c                  |
| `import-sofima`, `rep-filters` | 05               |
| `ic3d`                     | 06a                  |
| `rex ... aso-3d-s3i-pixel`, `-mask` | 06b         |
| `inpaint`                  | 07                   |
