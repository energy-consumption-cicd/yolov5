# Energy measurement instrumentation

## Purpose

This directory is not part of the upstream YOLOv5 repository. It was added to
measure the energy consumption of CI/CD pipeline commands on controlled
hardware, using Intel RAPL counters. The measured construct is the energy of
the CI commands on a controlled bench, not the energy of GitHub-hosted CI in
production.

## Non-invasiveness

No original project file is created or modified. The only additions are this
directory and `.github/workflows/energy-measurement.yml`. Verify with:

```bash
git remote add upstream https://github.com/ultralytics/yolov5.git
git fetch upstream
git diff --name-only upstream/master...HEAD
```

## What is measured

Energy is read from the Intel RAPL counters under
`/sys/class/powercap/intel-rapl`, for four domains: package (`pkg`), cores,
uncore (reported as `gpu`, structurally zero on this bench) and DRAM (`ram`).
Counter deltas are overflow-corrected against `max_energy_range_uj`, read from
sysfs at run time rather than hardcoded.

Each run measures a 120 s idle baseline first and derives a per-second rate per
domain. Reported energy per stage is

```
net = max(raw_delta - baseline_rate * wall_time_s, 0)
```

The clamp at zero prevents a negative DRAM figure on light memory workloads;
the unclamped DRAM value is kept as the diagnostic column
`energy_ram_liquid_raw_j`.

`wall_time_s` covers the whole `docker run --rm` lifecycle, including container
setup and teardown, because the RAPL reading window covers the same interval.

Per-stage CPU time is captured inside the container: file descriptor 3
preserves the workload's stderr while `time` writes to `/timing`, so the CPU
time of child processes is attributed to the stage instead of to the host
`docker` client.

## How to run

```bash
docker build -t yolov5-medicao -f energy-measurement/Dockerfile .
bash energy-measurement/run_pipeline.sh 1
```

The workflow runs the same script on a self-hosted runner, dispatched manually:

```bash
gh workflow run energy-measurement.yml -f campaign=validation   # run 0 only
gh workflow run energy-measurement.yml -f campaign=full         # 10 runs + median
```

## Stages

Each stage runs in its own container, so build artifacts do not survive into
the later stages.

| stage | corresponds to | command |
|---|---|---|
| `build` | dependency installation of the upstream `Tests` job | offline `uv pip install -r requirements.txt` from the image wheel cache |
| `test` | the non-training parts of the upstream steps "Test detection / segmentation / classification" | `val.py`, `detect.py`, inline hub loading, `models/yolo.py`, `export.py`, `segment/*`, `classify/*` |
| `train` | the training invocations of the same steps | `train.py`, `segment/train.py` (x2), `classify/train.py`, one epoch each |

Reference cell: `ci-testing.yml`, job `Tests`, `ubuntu-latest` / Python 3.11 /
model `yolov5n` — cell 1 of 6.

## Deviations from the upstream pipeline

- **Offline dependencies, weights and datasets.** Everything is pre-baked into
  the image and installed with `--offline`. RAPL has no network domain, so a
  live download would inflate wall time without proportional energy.
- **`--network none`.** The measured containers have no network.
- **`test` validates only against the official weights.** Upstream loops over
  the official weights and the `best.pt` produced by the training step in the
  same job; here training is a separate stage, so the freshly trained
  checkpoint is deliberately not used in `test`.
- **`hubconf.py --model` replicated inline** through `hubconf._create`, without
  the remote source, preserving the same model construction path.
- **No memory limit.** This campaign predates the `--memory` convention adopted
  later; the flag is absent by generation, not by choice.

## Output schema

One CSV per run, one row per stage plus a `total` row:

```
run, stage, energy_pkg_j, energy_cores_j, energy_gpu_j, energy_ram_j,
wall_time_s, user_time_s, sys_time_s, energy_ram_liquid_raw_j
```

The first nine columns are the official schema shared by every project in the
study; `energy_ram_liquid_raw_j` is diagnostic.

**Schema note.** The script in this directory writes an eleventh column,
`wall_time_container_s`, which the closed campaign's CSVs do not have: the
column was introduced on 2026-07-12, one day after that campaign. The ten
columns common to both coincide in name and order. A byte-exact recovery of the
script version that produced the closed results is not possible from any
surviving artifact; the gap is documented in the project's fidelity note in the
study's private infrastructure repository.

## Reproducibility notes

Bench: Intel Core i7-9700 (8 cores, no SMT), 16 GB RAM, Crucial BX500 SATA SSD,
Ubuntu 24.04 LTS, kernel 6.8.0, Docker 29.x.

Container flags: `--rm --privileged --network none`.

The `test` and `train` stages inherit the upstream parallelism settings without
override; the bench has 8 cores against 4 on a GitHub-hosted runner.
