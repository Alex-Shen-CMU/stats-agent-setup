# Known issues on wright

Fixes for problems that come from wright, Slurm or common libraries rather than from any one project. `SKILL.md`'s debugging table links to each section; read only the one you hit.

## sacct is flaky and blocking launchers hang

**Symptom.** `Bypassing sacct error` or `sacct: error: ... Connection refused` in logs. A blocking Hydra submitit driver (`hydra/launcher=submitit_slurm`) reports the array as `UNKNOWN` and never returns, even though every task finished.

**Cause.** `sacct` talks to slurmdbd, which intermittently refuses connections, especially from compute nodes. submitit polls `sacct` in-process, so a driver that waits on the array can see `UNKNOWN` forever.

**Resolution.**
- A few `sacct` errors are noise. Retry on the next poll.
- Don't rely on a driver job that blocks until its array finishes. Use a submit-only launcher that submits the array (e.g. with `submitit.AutoExecutor`) and returns immediately with the array job id.
- Chain dependent stages with Slurm dependencies instead of `&&` in a driver: `sbatch --dependency=afterany:<jobid> ...`, or `+hydra.launcher.additional_parameters.dependency=afterany:<jobid>` with the submitit launcher.
- Judge completion from output files, not from `sacct`/`squeue` state.

## Node failure requeues driver jobs from scratch

**Symptom.** After a node outage, new array jobs you didn't submit appear in `squeue`.

**Cause.** Slurm requeues jobs that were running on a failed node. A driver job restarts from the beginning and submits its whole array again.

**Resolution.**
- After any node flakiness, check `squeue -u <user_id>` for unexpected arrays and `scancel` the duplicates promptly. Duplicate training tasks race on the same checkpoint files, which can corrupt them. Duplicate eval-only tasks are lower risk but still waste allocation.
- Prefer submit-only launchers to long-lived driver jobs (see [sacct is flaky and blocking launchers hang](#sacct-is-flaky-and-blocking-launchers-hang)). If you need a driver, submit it with `--no-requeue`.

## Cancelled submitit tasks keep writing after squeue clears

**Symptom.** `Bypassing signal SIGTERM` in a task log. Output files (results, checkpoints) keep changing for minutes after the job left `squeue`.

**Cause.** submitit catches SIGTERM for its own preemption handling, so the task keeps running until Slurm follows up with SIGKILL.

**Resolution.**
- If you cancelled a job to inspect or reuse its on-disk state, wait a few minutes after `squeue` clears before reading its outputs.
- Wait before resubmitting a job that writes to the same output folder, so two writers never overlap.
- A kill in the middle of a non-atomic save can leave a truncated file. See [Preemption leaves a truncated checkpoint](#preemption-leaves-a-truncated-checkpoint).

## sbatch wrap runs under sh

**Symptom.** `slurm_script: 4: source: not found` from a job submitted with `sbatch --wrap`.

**Cause.** `--wrap` generates a `#!/bin/sh` script, and `sh` on wright has no `source` builtin.

**Resolution.** Wrap the payload in a login bash shell. Always pass an absolute `--chdir` and `--output`: a relative `--output` resolves against the submitting directory, and the job dies silently if that path doesn't exist.

```bash
sbatch --partition=statds --job-name=<name> \
  --chdir=/home/export/<user_id>/<repo> \
  --output=/home/export/<user_id>/<repo>/slurm_logs/<name>_%j.out \
  --wrap="bash -lc 'source /home/export/<user_id>/miniconda3/etc/profile.d/conda.sh && conda activate <env> && python <script>.py'"
```

## Job array larger than MaxArraySize

**Symptom.** `sbatch: error: Invalid job array specification`.

**Cause.** wright's `MaxArraySize` is 1001, so array indices must be in 0–1000. Check the current value with `scontrol show config | grep MaxArraySize`.

**Resolution.** Split anything bigger into several arrays of at most 1000 tasks.

## Preemption leaves a truncated checkpoint

**Symptom.** A resumed task fails with `EOFError` (or another unpickling error) while loading a checkpoint. The file is 0 bytes or truncated, and the earlier attempt ended with `CANCELLED ... DUE TO PREEMPTION`.

**Cause.** The checkpoint was written in place with `torch.save(obj, path)`. The job was killed mid-write, which left a partial file at the real path, and the next attempt tried to resume from it. This is likely on the preemptible `all` partition.

**Resolution.**
- Save atomically: write to a temporary file in the same directory, then `os.replace` it onto the real path. A kill then leaves either the old file or the new one, never a partial one.
  ```python
  def atomic_torch_save(obj, path):
      path = Path(path)
      tmp = path.with_name(f".{path.name}.{os.getpid()}.tmp")
      torch.save(obj, tmp)
      os.replace(tmp, path)
  ```
- To recover a run that's already broken, move the empty checkpoint (and any stale "best model" file written alongside it) aside, then resubmit that task, ideally on `statds` so it isn't preempted again. Don't run evals on that folder until training has completed.

## Text file busy when array tasks write the same file

**Symptom.** `OSError: [Errno 26] Text file busy` (or `FileNotFoundError`) from `os.replace` on a temp file like `<name>.pt.<pid>.temp`. This happens when many array tasks start on a cold cache.

**Cause.** Several tasks compute the same content-addressed cache file at once and race to rename it into place on NFS.

**Resolution.**
- Treat "the destination now exists" as success, and skip the write if the file is already there:
  ```python
  if path.exists():
      return
  try:
      os.replace(tmp, path)
  except OSError:
      if not path.exists():
          raise
      tmp.unlink(missing_ok=True)
  ```
- Or warm the cache first: run one task, or throttle the array (`--array=0-99%1`, or `hydra.launcher.array_parallelism=1`), before the wide array.
- Requeue any tasks lost to the race. Against a warm cache they finish quickly.

## Jobs die when the home filesystem is full

**Symptom.** A job exits with code 1 and a truncated log with no traceback. Sometimes `No space left on device` appears.

**Cause.** The shared `/home/export` volume is full.

**Resolution.**
- Run `df -h /home/export/<user_id>` **before** debugging any code.
- Don't delete anything on the shared volume without asking the user. Regenerable caches are the first candidates. If the volume is full because of other users, the sysadmins have to clear it.
- Pure-CPU analysis can run locally in the meantime.

## Wrong batched Cholesky gradients in torch 2.6

(Also documented in the `bridges2` skill.)

**Symptom.** `CUBLAS_STATUS_EXECUTION_FAILED`, or the backward pass of a batched `torch.linalg.cholesky` returns wrong gradients without any error. The gradients are correct only with `CUDA_LAUNCH_BLOCKING=1`.

**Cause.** A bug in torch 2.6, seen on L40, L40S and V100 GPUs. It is fixed in torch 2.14.1.

**Resolution.**
- Use torch 2.14.1 or later. On V100s (Bridges-2), install a `cu126` build. `cu132` wheels have no sm_70 kernels.
- Pin torch explicitly (`torch==<version> torchvision==<matching version>`) whenever you change the env. An unpinned `pip install --upgrade` that includes a package with no build for the newer torch (torchaudio, in the original case) silently backtracks torch to 2.6.
- Check `python -c 'import torch; print(torch.__version__)'` after every env change. Re-runs after a torch upgrade can differ from earlier results in the last few bits.
