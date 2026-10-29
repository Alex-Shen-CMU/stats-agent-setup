# Project: <optional project name>

<optional project description>

## Skills

Skills live in `<path>/SKILL.md`; read the matching one before starting the work.

## Compute

- Unless specified, run all experiments on external compute (leviathans, wright or Bridges-2). If the user doesn't say which cluster, ask; never assume. Say which cluster every experiment runs on.
- Smoke test new functionality and experiment configs locally first. If something can't run locally, smoke test it as a short GPU job if a GPU is available, otherwise smoke test on CPU.
- Light jobs on a login/head node are OK, but submit CPU-heavy work to compute nodes where possible.
- Run experiments from the latest default branch (`main` or `master`). Make sure the repo on external compute is synced.
- Keep dependencies in sync across machines, matching the form used locally (e.g. local conda env = make same conda env on remote)
- Leave experiment outputs on the cluster and tell the user where they are. When pulling figures/tables to local, keep their path relative to the repo root.
- Don't commit Slurm scripts by default

## Conventions

- If something appears to be a repeating workflow not currently outlined in these instructions, suggest adding them here.
- Ask clarifying questions instead of guessing.

## Git instructions

- Follow these instructions if you find yourself in a git repo
- Work directly on the default branch (`main` or `master`); commit and push unless told otherwise. Prefix commit messages with `<agent>:`. 
- Before anything: `git pull` locally, and stop if local is behind with uncommitted work or the histories diverged. Tell the user about branches on GitHub or a cluster that aren't present locally.
- Scratch scripts (one-off calculations) go in the gitignored top-level `<agent>_scratch/`.


