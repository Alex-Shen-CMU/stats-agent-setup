---
name: bridges2
description: Connect to the PSC Bridges-2 cluster and run this project's GPU jobs there (ssh, modules, conda env, storage paths, GPU-shared partition, launcher overrides). Use before running or inspecting anything on bridges2.
---

# Running on Bridges-2

<!-- ssh-setup:start -->
> **Unfilled `<user_id>`.** `<user_id>` in this file is a placeholder, which means the user may not have set up public-key login to Bridges-2. Before connecting:
>
> 1. Check for a working key: `ssh -o BatchMode=yes -o PreferredAuthentications=publickey -o ConnectTimeout=10 bridges2.psc.edu true`. `ssh -G bridges2.psc.edu | grep -E '^(user|identityfile) '` shows the username and keys `~/.ssh/config` resolves to.
> 2. If it succeeds, ask the user's permission to update this skill. With permission, replace every `<user_id>` with the username from `ssh -G` in this file and in every other file in this skill's folder (e.g. `known-issues.md`), and delete this note from this file (everything from `ssh-setup:start` to `ssh-setup:end`).
> 3. If it fails, don't try password login. Bridges-2 keys must be registered with PSC (not copied with `ssh-copy-id`), so point the user to PSC's instructions for adding a key: https://www.psc.edu/about-using-ssh/ ("Authenticating using a public-private key pair"). Once the key is registered and `~/.ssh/config` has a `bridges2.psc.edu` entry with their `User` and `IdentityFile`, they can run `curl -fsSL https://raw.githubusercontent.com/Alex-Shen-CMU/stats-agent-setup/main/passwordless_ssh.sh | bash -s -- --only bridges2` from the project directory to verify it and fill in this skill's files. (If the error is a timeout rather than `Permission denied`, the problem is the connection, not the key.)
<!-- ssh-setup:end -->

Placeholders: `<repo>` is this project's repository name, `<env>` its conda environment and `<allocation>` the PSC allocation (charge ID) to run under. Take `<repo>` and `<env>` from the local checkout and the local env. For `<allocation>`, run `projects` on Bridges-2 to list the user's allocations and ask which one to charge; never guess.

## Connect and set up

- `ssh <user_id>@bridges2.psc.edu`. The `<user_id>@` is required unless `~/.ssh/config` sets the user, because the remote username often differs from the local one.
- Repo: `~/<repo>` = `/jet/home/<user_id>/<repo>`. If it isn't there, ask the user before cloning it.
- Environment for every remote command and job:
  ```bash
  module load anaconda3 && source $(conda info --base)/etc/profile.d/conda.sh && conda activate <env>
  module load cuda/12.6.1    # GPU jobs
  ```
  A plain `ssh host 'cmd'` and sbatch payloads may not source `~/.bashrc`, so also export any environment variables the project reads (e.g. output directories) explicitly.
- **Never write experiment outputs to the home directory** unless the user explicitly asks; its quota is small. Everything goes under project storage, `/ocean/projects/<allocation>/<user_id>/`.
- Override every config path that points at a local or other-cluster location (outputs, caches, checkpoints) on every submission. See the debugging reference.
- If `<env>` doesn't exist on Bridges-2, create it to match the local env. The V100 nodes need a torch build with sm_70 kernels: use a CUDA 12.6 build (`cu126`), because `cu132` wheels lack V100 kernels. Keep packages compatible with the loaded `cuda` module.
- The login node is slow: a smoke test that takes 30 s locally can take over 10 min there. Run anything non-trivial as a job.

## Sync before running anything

These are the same rules as on wright (also in the `wright` skill).

1. Locally: `git pull`. Stop if local is behind remote **and** has uncommitted work, or if histories diverged.
2. On Bridges-2: `git fetch && git status -sb`. The checkout must be on the default branch (`main` or `master`). If it's on another branch, ask the user before doing anything.
3. Make code changes locally, smoke test locally, commit (with the prefix CLAUDE.md specifies), push, then `git pull --ff-only` on Bridges-2. Never edit code directly on Bridges-2.
4. Tell the user about any branch on Bridges-2 or GitHub that isn't present locally.

## Partition and resources

- Use `GPU-shared` with one GPU:
  ```
  #SBATCH -p GPU-shared
  #SBATCH -A <allocation>
  #SBATCH --gres=gpu:1
  #SBATCH --constraint="l40s|v100-32"
  ```
  Most jobs fit a v100-32. Request only `l40s` when they don't.
- Warn the user if they ask for a **CPU-only** workload here. GPU allocations usually come without CPU-node credits, and running CPU work on GPU nodes wastes GPU allocation. Do CPU work locally or on another cluster instead.
- Walltime ceiling is 48 h (2880 min). The partition QOS overrides any requested QOS. Long training must resume via a re-submission of the same config.
- Queue waits dominate wall-clock (hundreds of pending jobs are normal).

## Submitting

- If the work is for a GitHub issue, prefix every job name with `gi<issue>_` (e.g. `gi54_train`) so jobs can be traced back to it.
- For Hydra sweeps with the submitit launcher, the launcher config needs the partition, account, `gres` and constraint above, plus `module load cuda/12.6.1` in its `setup` list. If the project enables deterministic torch, also add `export CUBLAS_WORKSPACE_CONFIG=:4096:8` there. Prefer a launcher that submits the array and returns over a blocking driver job, and chain stages with `--dependency=afterany:<jobid>`.

## Monitoring

- Judge completion from the run's output files (final checkpoints, metrics, summaries), not from `sacct`/`squeue` state.
- `claude` is not installed on Bridges-2, so chained Claude followup jobs don't work here. Monitor long sweeps from the local session by checking back periodically, and poll infrequently, since queue waits dominate.
- Leave outputs on Bridges-2 and tell the user where they are.

## Debugging reference

Look up by what you see, and read the linked entry only when you hit it. Rows link either to a section of `known-issues.md` (shared fixes from the setup repo) or to a GitHub issue in the user's own project (its description ends with a Resolution section).

| Symptoms | Cause | Details |
|---|---|---|
| `PermissionError` on a `/home/export/...` or `/mnt/scratch/...` path | config defaults point at another cluster's paths | [known-issues.md](known-issues.md#paths-configured-for-another-cluster) |
| `No module named '...'` / branch code not used when launching from a worktree | shell `PYTHONPATH` doesn't reach compute nodes | [known-issues.md](known-issues.md#pythonpath-from-the-shell-doesnt-reach-compute-nodes) |
| `RuntimeError: Deterministic behavior was enabled ... CUBLAS_WORKSPACE_CONFIG=:4096:8`; log shows `CUBLAS_WORKSPACE_CONFIG=None` | submitit skips the script's top-level env setup | [known-issues.md](known-issues.md#cublas_workspace_config-is-unset-in-submitit-tasks) |
| `QOSMaxWallDurationPerJobLimit` at submission | GPU-shared caps walltime at 48 h; resubmit the same config to resume | [known-issues.md](known-issues.md#walltime-over-the-48-h-limit) |
| `claude: command not found` in a followup log | claude isn't installed on Bridges-2 | [known-issues.md](known-issues.md#claude-is-not-installed-on-bridges-2) |
| `CUBLAS_STATUS_EXECUTION_FAILED`; wrong batched `linalg.cholesky` gradients | torch 2.6 bug | [known-issues.md](known-issues.md#wrong-batched-cholesky-gradients-in-torch-26) |
| `pip install --upgrade` silently downgrades torch to 2.6 | unpinned torch backtracks for a package without a newer build; pin `torch==` | [known-issues.md](known-issues.md#wrong-batched-cholesky-gradients-in-torch-26) |
