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
git fetch upstream tag v6.1
git diff --name-only v6.1 HEAD
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
docker build -t yolov5-measurement-6.1.0 -f energy-measurement/Dockerfile .   # from a clone of this branch
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
| `build` | step "Install dependencies" of the upstream `cpu-tests` job | `python -m pip install --upgrade pip`, `pip install -qr requirements.txt` and `pip install -q onnx tensorflow-cpu keras==2.6.0` in a fresh venv, resolved from the image wheel directory, then `pip list` |
| `test` | the non-training commands of the upstream step "Tests workflow" | `val.py`, `detect.py`, inline hub loading, `models/yolo.py`, `models/tf.py`, `export.py` (TorchScript and ONNX) |
| `train` | the training command of the same step | `train.py`, one epoch |

Reference cell: `ci-testing.yml`, job `cpu-tests`, `ubuntu-latest` / Python 3.9 /
model `yolov5n`, at tag `v6.1` (`3752807c0b8af03d42de478fbcbf338ec4546a6c`).

## Deviations from the upstream pipeline

- **Offline dependencies, weights and datasets.** Everything is pre-baked into
  the image, each weight and dataset checked against its sha256, and `pip`
  installs from a local wheel directory with no index. RAPL has no network
  domain, so a live download would inflate wall time without proportional
  energy.
- **Dependency versions fixed at the tag date.** The tag pins no versions and
  the logs of its CI runs are no longer available; the image carries
  CPython 3.9.10 and the package releases current at the tag commit
  (2022-02-22), with the CPU builds of PyTorch.
- **`--network none`.** The measured containers have no network.
- **`test` validates only against the official weights.** Upstream loops over
  the official weights and the `best.pt` produced by the training step in the
  same job; here training is a separate stage, so the freshly trained
  checkpoint is deliberately not used in `test`.
- **`hubconf.py` replicated inline** through `hubconf._create`, with the model
  the tag builds (`yolov5s`) and without the remote source, preserving the same
  model construction path.
- **Source-only dependencies built as wheels at image build time.** `clang`,
  `termcolor` and `wrapt` have no wheel for this interpreter; they are built
  once in the image so the measured `build` installs wheels only.
- **No memory limit.** The containers run without `--memory`, as in the
  measurement of the default branch of this fork.

## Output schema

One CSV per run, one row per stage plus a `total` row:

```
run, stage, energy_pkg_j, energy_cores_j, energy_gpu_j, energy_ram_j,
wall_time_s, user_time_s, sys_time_s, energy_ram_liquid_raw_j,
wall_time_container_s, baseline_rate_pkg_w, baseline_rate_cores_w,
baseline_rate_ram_w
```

The first nine columns are the schema shared by every project in the study;
`energy_ram_liquid_raw_j`, `wall_time_container_s` and the baseline rates of
the run are diagnostic.

Host swap counters and the package temperature are read immediately before and
after the RAPL window of each stage, never inside it, and written as
`swap_run_NN_<stage>.txt` and `temp_run_NN_<stage>.txt` next to the CSV.

## Reproducibility notes

Bench: Intel Core i7-9700 (8 cores, no SMT), 16 GB RAM, Crucial BX500 SATA SSD,
Ubuntu 24.04 LTS, kernel 6.8.0, Docker 29.x.

Container flags: `--rm --privileged --network none`.

The `test` and `train` stages inherit the upstream parallelism settings without
override; the bench has 8 cores, more than a GitHub-hosted runner.
