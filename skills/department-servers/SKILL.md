---
name: department-servers
description: Connect to and run jobs on the CMU Statistics department servers (hydra, leviathan, ghidorah nodes; ssh, shared NAS home, picking an idle node, running unattended jobs, checking for other users). Use before running or inspecting anything on a hydra, leviathan or ghidorah node, or when the user mentions the department servers.
---

# Running on the department servers

<!-- ssh-setup:start -->
> **Unfilled `<user_id>`.** `<user_id>` in this file is a placeholder, which means the user may not have set up public-key login to the department servers. Before connecting:
>
> 1. Check for a working key: `ssh -o BatchMode=yes -o PreferredAuthentications=publickey -o ConnectTimeout=10 leviathan1.stat.cmu.edu true`. `ssh -G leviathan1.stat.cmu.edu | grep -E '^(user|identityfile) '` shows the username and keys `~/.ssh/config` resolves to. The nodes share one home directory, so one key works on all of them; if this host is down, test another node.
> 2. If it succeeds, ask the user's permission to update this skill. With permission, replace every `<user_id>` with the username from `ssh -G` in this file and in every other file in this skill's folder (e.g. `known-issues.md`), and delete this note from this file (everything from `ssh-setup:start` to `ssh-setup:end`).
> 3. If it fails, don't try password login. Ask the user to run this in their own terminal, from the project directory: `curl -fsSL https://raw.githubusercontent.com/Alex-Shen-CMU/stats-agent-setup/main/passwordless_ssh.sh | bash`. It sets up the key and fills in this skill's files. (If the error is a timeout rather than `Permission denied`, they may need the CMU VPN first.)
<!-- ssh-setup:end -->

The department servers are **unmanaged** nodes: no Slurm, no queue, no allocation. You ssh in and run directly, alongside whoever else is logged in.

## Nodes

| Type | Hosts | Hardware | Use for |
|---|---|---|---|
| Hydra | `hydra1`–`hydra4` | CPU only, old | Light CPU work only. Soon to be deprecated: prefer a leviathan. |
| Leviathan | `leviathan1`–`leviathan11` | CPU only, newer | Default for CPU work. |
| Ghidorah | `ghidorah1`–`ghidorah3` | One RTX 4090 each | GPU work. Don't run CPU-only jobs here. |

## Connect and set up

- `ssh <user_id>@<type><number>.stat.cmu.edu`, e.g. `ssh <user_id>@hydra2.stat.cmu.edu`.
- The home directory lives on a central NAS and is the **same on every node**. Code, conda envs and outputs written on one node are visible on all of them, so there is nothing to sync between nodes.
- The ghidorahs and leviathans also have scratch storage at `/scratch`. Make your own folder under scratch first (typically named after the user's Andrew ID).
- Because home is shared, two jobs on different nodes writing to the same output path will clobber each other. Give concurrent runs distinct output dirs.
- A plain `ssh host 'cmd'` may not source `.bashrc`. Activate the environment explicitly in every remote command.

## Before launching: check the node

Other users share these machines with no scheduler to arbitrate. Before starting anything non-trivial, check load and pick the idlest node:

```bash
ssh <user_id>@<host>.stat.cmu.edu 'who; uptime; nproc; free -h; top -bn1 -o %CPU | head -20'
# Ghidorahs also:
ssh <user_id>@ghidorahN.stat.cmu.edu 'nvidia-smi'
```

- If the load average is near `nproc`, memory is mostly used, or (on a ghidorah) the GPU already has another user's process, try another node of the same type.
- Leave headroom: don't take every core or nearly all RAM. Cap thread pools explicitly (`OMP_NUM_THREADS`, `MKL_NUM_THREADS`, `n_jobs`, `torch.set_num_threads`) rather than letting libraries grab every core.
- Run long CPU jobs under `nice` (e.g. `nice -n 10`) so interactive users stay responsive.
- Tell the user which node you chose and why.

## Running jobs

- There is no queue, so a job dies with your ssh session unless detached. Use `tmux`/`screen` or `nohup ... > log 2>&1 &`, and write logs to a file under the run's output dir.
- Record the host and PID of every job you start so it can be checked on or killed later (`ps -fu <user_id>` on that host).
- Nodes can be rebooted or overloaded by others without warning. Jobs longer than an hour or so should checkpoint and be resumable.
- Judge completion from output artifacts and logs, not just from whether the process is gone.
- Do not run heavy IO jobs off of the NAS, or the entire department suffers. Use `/scratch` instead.

## When to move to a real cluster

These nodes are for single-node work. **Avoid experiments that occupy multiple department nodes for an extended period** (e.g. spreading a sweep across several leviathans for hours or days). That crowds out other department users and has no scheduler to recover from failures.

If a workload needs multiple nodes, many GPUs, or long wall-clock time, recommend the user move it to a managed cluster instead:

- **wright** (`wright` skill): department Slurm cluster, CPU and GPU partitions.
- **Bridges-2 / PSC** (`bridges2` skill): Pittsburgh Supercomputing Center, for large GPU sweeps.

Raise this before launching, not after; let the user decide.
