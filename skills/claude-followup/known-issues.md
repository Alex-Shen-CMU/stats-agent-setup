# Known issues with Claude followup jobs

Fixes for problems with chained followup sessions that don't depend on any one project. `SKILL.md`'s debugging table links to each section; read only the one you hit.

## Followup fails when the claude login has expired

**Symptom.** No followup report ever appears. `sacct -j <followup id>` shows the followup FAILED after a few seconds, and `slurm_logs/claude_followup_<id>.out` contains `Failed to authenticate: OAuth session expired`.

**Cause.** The `claude` login on the cluster has expired. The followup can't start a session.

**Resolution.** Unresolved as of 2026-10-26. Work around it:
- When a followup's report is missing, check `sacct -j <followup id>` and read its log before assuming the upstream jobs are still running.
- The user has to log `claude` back in on the cluster (run `claude` there and `/login`) before another followup can be chained. The agent can't fix this itself.

## Results posted twice

**Symptom.** Two near-identical results comments appear a minute or two apart.

**Cause.** The session chained a followup **and** monitored the jobs itself, so both reported.

**Resolution.** Pick **one** reporter:
- chain the followup and don't report results in-session (just tell the user the status), or
- monitor in-session, and `scancel` the chained followup as soon as you've confirmed the jobs finished.

## Writing a followup script is refused

**Symptom.** A tool call that creates a new followup sbatch script (with a heredoc, `scp`, or by adding a permission rule) is denied.

**Cause.** Claude Code's auto-mode permission classifier blocks the agent from deploying scripts that start unattended auto-mode sessions.

**Resolution.** Use the generic `claude_followup.sb` that the user placed on the cluster (a template ships in this skill's folder; the user copies it). It takes the prompt as `$1`. Never write a new followup script or a variant of it. If the script is missing or needs a change, ask the user to edit it.

## claude is not installed on Bridges-2

(Also documented in the `bridges2` skill.)

**Symptom.** `claude: command not found` in a followup log, or `which claude` fails on Bridges-2.

**Cause.** `claude` isn't installed on Bridges-2, so a followup job can't run there.

**Resolution.** Unresolved as of 2026-10-26. For Bridges-2 sweeps, monitor from the local session instead of chaining a followup. `GPU-shared` queue waits dominate wall-clock time (hundreds of pending jobs are normal), so poll infrequently.
