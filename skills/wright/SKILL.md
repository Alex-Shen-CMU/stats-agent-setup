---
name: wright
description: Connect to the wright.hss.cmu.edu Slurm cluster and run this project's jobs there (ssh, conda env, git sync, partitions, sbatch patterns, monitoring). Use before running or inspecting anything on wright.
---

# Running on wright

<!-- ssh-setup:start -->
> **Unfilled `<user_id>`.** `<user_id>` in this file is a placeholder, which means the user may not have set up public-key login to wright. Before connecting:
>
> 1. Check for a working key: `ssh -o BatchMode=yes -o PreferredAuthentications=publickey -o ConnectTimeout=10 wright.hss.cmu.edu true`. `ssh -G wright.hss.cmu.edu | grep -E '^(user|identityfile) '` shows the username and keys `~/.ssh/config` resolves to.
> 2. If it succeeds, ask the user's permission to update this skill. With permission, replace every `<user_id>` with the username from `ssh -G` in this file and in every other file in this skill's folder (e.g. `known-issues.md`), and delete this note from this file (everything from `ssh-setup:start` to `ssh-setup:end`).
> 3. If it fails, don't try password login. Ask the user to run this in their own terminal, from the project directory: `curl -fsSL https://raw.githubusercontent.com/Alex-Shen-CMU/stats-agent-setup/main/passwordless_ssh.sh | bash`. It sets up the key and fills in this skill's files. (If the error is a timeout rather than `Permission denied`, they may need the CMU VPN first.)
<!-- ssh-setup:end -->

Placeholders: `<repo>` is this project's repository name and `<env>` its conda environment. Take them from the local checkout and the local env, and ask the user if the copies on wright are named differently. Chaining a Claude followup onto jobs is covered by the `claude-followup` skill, if it's installed.

## Connect and set up

- `ssh <user_id>@wright.hss.cmu.edu` (key-based). It lands on `headnode`.
- Repo: `~/<repo>` = `/home/export/<user_id>/<repo>`. If it isn't there, ask the user before cloning it. Assume other sessions' experiments may be running from this checkout.
- A plain `ssh host 'cmd'` does not source `.bashrc`, so activate the env explicitly in every remote command and sbatch payload:
  ```bash
  source /home/export/<user_id>/miniconda3/etc/profile.d/conda.sh && conda activate <env>
  ```
  If conda lives somewhere other than `~/miniconda3`, find it with `bash -lc 'which conda'` and adjust the path. If `<env>` doesn't exist on wright, create it to match the local env (same package versions) instead of installing into `base`.
- Check where the project writes outputs, caches and checkpoints (config defaults, environment variables), and make sure they resolve to paths on wright, not local or other-cluster paths.
- `/mnt/scratch` is a fixed location on the compute nodes. It does not exist on the head node, so only use it from inside a job (create directories and read results there from a job, not over a plain `ssh`).

## Sync before running anything

1. Locally: `git pull`. Stop if local is behind remote **and** has uncommitted work, or if histories diverged.
2. On wright: `git fetch && git status -sb`. Wright's checkout must be on the default branch (`main` or `master`). If it's on another branch, ask the user before doing anything.
3. Make code changes locally, smoke test locally, commit (with the prefix CLAUDE.md specifies), push, then `git pull --ff-only` on wright. Never edit code directly on wright.
4. Tell the user about any branch on wright or GitHub that isn't present locally.

## Partitions

| Partition | Nodes | Use for |
|---|---|---|
| `all` | n01, n02, n03 | GPU training/eval arrays. Low priority and **preemptible**, so jobs over 1 h must be resumable. |
| `statds` | n01 only | Jobs that must not be preempted: followups, drivers, small CPU jobs (aggregation, plots). High priority, low capacity. |

- Don't put a small job that bottlenecks the task (an aggregation step, a followup) on `all`. It can sit behind the whole queue or get preempted.
- `statds` is open to all CMU Statistics department members. Users outside the department may not have access; if a `statds` submission is rejected, ask the user which non-preemptible partition they can use instead and use it wherever this skill (or `claude-followup`) says `statds`.
- `statds` has exactly one node. If n01 is down, `statds` jobs stay PENDING with no fallback, so check `sinfo -p statds` when something sits pending.
- Light work (composing configs, `git`, reading CSVs) is fine on the head node. Anything CPU-heavy should go to a `statds` CPU job.

## Submitting

- If the work is for a GitHub issue, prefix every job name with `gi<issue>_` (e.g. `gi54_train`) so jobs can be traced back to it. Jobs that aren't for an issue get no prefix. With Hydra's submitit launcher, the Slurm job name comes from `hydra.job.name=<name>`. Rename an already-submitted job with `scontrol update JobId=<id> JobName=<name>`.
- One-off CPU job:
  ```bash
  sbatch --partition=statds --job-name=<name> \
    --chdir=/home/export/<user_id>/<repo> \
    --output=/home/export/<user_id>/<repo>/slurm_logs/<name>_%j.out \
    --wrap="bash -lc 'source /home/export/<user_id>/miniconda3/etc/profile.d/conda.sh && conda activate <env> && python <script>.py'"
  ```
  Keep the `bash -lc` and the absolute `--chdir`/`--output`, and make sure the `slurm_logs/` directory exists.
- GPU smoke test (for GPU code that can't run locally): a short `--gres=gpu:1` job on `all`.
- One array holds at most 1001 tasks. Chunk anything bigger.
- For Hydra sweeps, prefer a launcher that submits the array and returns over the blocking `submitit_slurm` driver, and chain stages with `--dependency=afterany:<jobid>` (see the first entry in the debugging reference).

## Monitoring

- Judge completion from the run's output files (final checkpoints, metrics, summaries), not from `sacct`/`squeue` state.
- `sacct` is flaky (intermittent `Connection refused`). A few of these are noise. Retry on the next poll.
- For pipelines expected to take over about 2 h, don't monitor in-session. Chain a followup if the `claude-followup` skill is installed. Otherwise tell the user what to check and when.
- Leave outputs on wright and tell the user where they are. When pulling figures/tables to local, preserve the path relative to the repo root.

## Debugging reference

Look up by what you see, and read the linked entry only when you hit it. Rows link either to a section of `known-issues.md` (shared fixes from the setup repo) or to a GitHub issue in the user's own project (its description ends with a Resolution section).

| Symptoms | Cause | Details |
|---|---|---|
| `Bypassing sacct error`; `sacct` `Connection refused`; blocking submitit driver hangs (`UNKNOWN`) after the array finished | sacct/slurmdbd flaky from compute nodes | [known-issues.md](known-issues.md#sacct-is-flaky-and-blocking-launchers-hang) |
| Unexpected new array jobs in `squeue` after a node outage | Slurm requeue restarts driver jobs from scratch | [known-issues.md](known-issues.md#node-failure-requeues-driver-jobs-from-scratch) |
| `Bypassing signal SIGTERM`, then output files keep changing minutes after `squeue` cleared | submitit ignores SIGTERM until SIGKILL | [known-issues.md](known-issues.md#cancelled-submitit-tasks-keep-writing-after-squeue-clears) |
| `slurm_script: 4: source: not found` | `--wrap` runs under `sh` | [known-issues.md](known-issues.md#sbatch-wrap-runs-under-sh) |
| `sbatch: error: Invalid job array specification` | array over `MaxArraySize` 1001 | [known-issues.md](known-issues.md#job-array-larger-than-maxarraysize) |
| `EOFError` loading a checkpoint on resume; 0-byte `.pt` after `CANCELLED ... DUE TO PREEMPTION` | non-atomic save killed mid-write | [known-issues.md](known-issues.md#preemption-leaves-a-truncated-checkpoint) |
| `OSError: [Errno 26] Text file busy` from `os.replace` (`.pt.<pid>.temp`) on a cold cache | NFS race between array tasks | [known-issues.md](known-issues.md#text-file-busy-when-array-tasks-write-the-same-file) |
| Exit 1, truncated log, no traceback; `No space left on device` | shared home FS full; run `df -h /home/export/<user_id>` | [known-issues.md](known-issues.md#jobs-die-when-the-home-filesystem-is-full) |
| `CUBLAS_STATUS_EXECUTION_FAILED`; batched `linalg.cholesky` gradients wrong unless `CUDA_LAUNCH_BLOCKING=1` | torch 2.6 bug | [known-issues.md](known-issues.md#wrong-batched-cholesky-gradients-in-torch-26) |
| `pip install --upgrade` silently downgrades torch to 2.6 | unpinned torch backtracks for a package without a newer build; pin `torch==` | [known-issues.md](known-issues.md#wrong-batched-cholesky-gradients-in-torch-26) |
