# Known issues on Bridges-2

Fixes for problems that come from Bridges-2, Slurm or common libraries rather than from any one project. `SKILL.md`'s debugging table links to each section; read only the one you hit. Some entries are also documented in the `wright` or `claude-followup` skill; they're repeated here so this skill works when installed on its own.

## Paths configured for another cluster

**Symptom.** A job fails with `PermissionError` (or `No such file or directory`) on a path that belongs to another cluster, e.g. `/home/export/...` or `/mnt/scratch/...` from wright.

**Cause.** The project's config defaults (cache, output or model directories) point at another cluster's filesystem, and the submission didn't override them.

**Resolution.** Override every cluster-specific path on **every** Bridges-2 submission (training and eval alike), pointing it at project storage under `/ocean/projects/`. See `SKILL.md` for the directories. Check which config keys hold paths before the first sweep.

## PYTHONPATH from the shell doesn't reach compute nodes

**Symptom.** `No module named '...'` in a job, or the job runs the main checkout's code instead of your branch's. This typically happens when you launch from a git worktree with `PYTHONPATH` exported in your shell.

**Cause.** The job doesn't reliably inherit `PYTHONPATH` from the submitting shell. The launcher's setup commands and the node's shell startup files build the job's environment.

**Resolution.**
- Set the path in the launcher's setup, not in your shell. With the Hydra submitit launcher:
  ```
  "hydra.launcher.setup=[\"export PYTHONPATH=$WT/src\",\"module load cuda/12.6.1\",\"export CUBLAS_WORKSPACE_CONFIG=:4096:8\"]"
  ```
  An override replaces the launcher's whole `setup` list, so repeat everything else it needs. See [CUBLAS_WORKSPACE_CONFIG is unset in submitit tasks](#cublas_workspace_config-is-unset-in-submitit-tasks).
- Print `<package>.__file__` in the job log to prove which code ran.
- The same applies on wright.

## CUBLAS_WORKSPACE_CONFIG is unset in submitit tasks

**Symptom.** `RuntimeError: Deterministic behavior was enabled ... CUBLAS_WORKSPACE_CONFIG=:4096:8` in a task, and the job log shows `CUBLAS_WORKSPACE_CONFIG=None`.

**Cause.** The launching script sets the variable at the top level, but submitit runs the task function in a fresh process on the compute node, where that code never ran.

**Resolution.** Put `export CUBLAS_WORKSPACE_CONFIG=:4096:8` in the `setup` list of every launcher config. Any `hydra.launcher.setup=[...]` override replaces that list, so include the export there too. It's harmless when determinism is off.

## Walltime over the 48 h limit

**Symptom.** `QOSMaxWallDurationPerJobLimit` at submission, or the job stays pending with that reason.

**Cause.** `GPU-shared` caps walltime at 48 h, and the partition's QOS overrides any QOS you request.

**Resolution.** Request at most `--time=48:00:00`. Make long training resumable from a checkpoint, and resubmit the same config to continue.

## claude is not installed on Bridges-2

(Also documented in the `claude-followup` skill.)

**Symptom.** `claude: command not found` in a followup log, or `which claude` fails on Bridges-2.

**Cause.** `claude` isn't installed on Bridges-2, so a chained Claude followup job can't run there.

**Resolution.** Unresolved as of 2026-10-26. For Bridges-2 sweeps, monitor from the local session instead of chaining a followup. `GPU-shared` queue waits dominate wall-clock time (hundreds of pending jobs are normal), so poll infrequently.

## Wrong batched Cholesky gradients in torch 2.6

(Also documented in the `wright` skill.)

**Symptom.** `CUBLAS_STATUS_EXECUTION_FAILED`, or the backward pass of a batched `torch.linalg.cholesky` returns wrong gradients without any error. The gradients are correct only with `CUDA_LAUNCH_BLOCKING=1`.

**Cause.** A bug in torch 2.6, seen on L40, L40S and V100 GPUs. It is fixed in torch 2.14.1.

**Resolution.**
- Use torch 2.14.1 or later. On the V100s, install a `cu126` build. `cu132` wheels have no sm_70 kernels.
- Pin torch explicitly (`torch==<version> torchvision==<matching version>`) whenever you change the env. An unpinned `pip install --upgrade` that includes a package with no build for the newer torch (torchaudio, in the original case) silently backtracks torch to 2.6.
- Check `python -c 'import torch; print(torch.__version__)'` after every env change. Re-runs after a torch upgrade can differ from earlier results in the last few bits.
