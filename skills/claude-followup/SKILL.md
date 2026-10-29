---
name: claude-followup
description: Chain an unattended Claude followup session onto long-running Slurm jobs on wright (claude_followup.sb), and write followup prompts. Use when launching anything expected to take over ~2 hours, or when a followup job failed or never reported.
---

# Claude followup jobs

## When to use

- Any wright pipeline expected to take **more than about 2 h**. Don't monitor it in-session; chain a followup and stop.
- **Not on Bridges-2.** `claude` isn't installed there; monitor Bridges-2 sweeps from the local session instead.
- Several long stages can be chained: each followup's prompt tells the next session what to launch, and the issue comments form the paper trail.

## Submitting

`claude_followup.sb` in the repo root on wright takes the prompt as `$1` and, optionally, a conda env as `$2`. It runs `claude -p "$1" --permission-mode auto` (30 min limit) from the directory it was submitted from. The script sets no partition, so always submit it on a priority (non-preemptible) partition with `-p`; on wright that's `statds` (see the `wright` skill):

```bash
cd ~/<repo>    # this project's checkout on wright
mkdir -p slurm_logs
sbatch -p <priority partition> --job-name=gi<N>_followup --dependency=afterany:<jobid[:jobid...]> claude_followup.sb "<prompt>" <env>
```

- Use `afterany`, not `afterok`, so the followup also runs, and reports, when jobs fail.
- Get job ids from `sbatch`'s output (`Submitted batch job <id>`) or from the launcher's output; join several with `:`.
- Submit from the repo root: the script's `--output` is relative (`slurm_logs/claude_followup_%j.out`), and Slurm doesn't create `slurm_logs/` itself.
- **Never write, copy or edit a followup script yourself**, not even a one-off variant (the permission classifier blocks it anyway). If `claude_followup.sb` is missing from the repo root on wright, ask the user to copy the template from this skill's folder, e.g. `scp <this skill's folder>/claude_followup.sb <user_id>@wright.hss.cmu.edu:~/<repo>/`, filling in the actual paths for them. If it needs a change, ask the user to make it.
- `claude` must be installed and logged in on wright for the user's account (it goes in `~/.local/bin`, which the script adds to `PATH`).
- **Pick one reporter.** Either chain the followup and don't report results in-session, or self-monitor and `scancel` the followup once you've confirmed the jobs finished.
- Before chaining, post an issue comment that lists the job ids and what the followup is expected to do.

## Writing the prompt

The followup session starts cold: it only has CLAUDE.md, the skills and the issue. The prompt should:

1. Name the issue URL and say the jobs from its last update have completed, e.g. `Slurm jobs pertaining to the last update on <issue URL> have completed. See CLAUDE.md and continue working.`
2. Say what to do **on success**. By default that's aggregation: summarize results, leading with the project's main metric (from CLAUDE.md or the issue). Name any stage it should launch next, and say that stage should chain its own followup.
3. Say what to do **on failure**: diagnose, post a requeue *plan* on the issue, and don't debug or resubmit without user approval.
4. Guard against duplicates: if the issue already has a results comment for these jobs, do nothing.

Keep step-by-step instructions on the issue rather than in the prompt, so the trail stays readable.

## Debugging reference

Look up by what you see, and read the linked entry only when you hit it. Rows link either to a section of `known-issues.md` (shared fixes from the setup repo) or to a GitHub issue in the user's own project (its description ends with a Resolution section).

| Symptoms | Cause | Details |
|---|---|---|
| No followup comment ever appears; followup job FAILED after ~9 s; `Failed to authenticate: OAuth session expired` in `slurm_logs/claude_followup_<id>.out` | the `claude` login on wright expired; the user must log in again | [known-issues.md](known-issues.md#followup-fails-when-the-claude-login-has-expired) |
| Two near-identical results comments ~90 s apart | followup chained **and** the session self-reported | [known-issues.md](known-issues.md#results-posted-twice) |
| Tool call creating a new followup `.sb` script (heredoc, `scp`, settings rule) denied | permission classifier blocks deploying auto-mode Claude sessions | [known-issues.md](known-issues.md#writing-a-followup-script-is-refused) |
| `claude: command not found` / `which claude` fails on Bridges-2 | claude only installed on wright and locally | [known-issues.md](known-issues.md#claude-is-not-installed-on-bridges-2) |
| Followup job stuck PENDING | `statds` is the single node n01; if it's down, nothing on `statds` runs. Check `sinfo -p statds` | — |
