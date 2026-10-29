# Agent Setup

This repository is intended to provide researchers in the CMU Statistics department with prewritten agent skills to improve efficiency and reduce token usage.

# How to use this repo

## Users

Simply run this command from any project directory and follow the instructions

```
curl -fsSL https://raw.githubusercontent.com/Alex-Shen-CMU/stats-agent-setup/main/install.sh | bash
```

The script asks which agent you use (Claude Code, Codex, Gemini CLI, Cursor, GitHub Copilot, OpenCode, or Other) and installs the instructions file and skills under the names that agent expects:

| Agent | Instructions file | Skills directory |
|---|---|---|
| Claude Code | `CLAUDE.md` | `.claude/skills/` |
| OpenAI Codex | `AGENTS.md` | `.agents/skills/` |
| Gemini CLI | `GEMINI.md` | `.gemini/skills/` |
| Cursor | `AGENTS.md` | `.cursor/skills/` |
| GitHub Copilot | `AGENTS.md` | `.github/skills/` |
| OpenCode | `AGENTS.md` | `.opencode/skills/` |
| Other | you choose (default `AGENTS.md`) | you choose (default `.agents/skills/`) |

Existing files are never overwritten without asking. To skip the prompts, pass options after `bash -s --`, e.g. `... | bash -s -- --agent codex --force`. Other options: `--dir PATH` (install somewhere other than the current directory) and `--ref TAG` (install a specific release tag or branch).

### Passwordless ssh to the servers

The server skills (`department-servers`, `wright`, `bridges2`) need key-based ssh login so the agent can connect without a password. After installing, run this from the same project directory:

```
curl -fsSL https://raw.githubusercontent.com/Alex-Shen-CMU/stats-agent-setup/main/passwordless_ssh.sh | bash
```

For each server you have an account on, it checks `~/.ssh/config` for a working key. If there isn't one, it generates a key pair, installs it with `ssh-copy-id`, verifies the login and adds a `~/.ssh/config` entry. Bridges-2 is the exception: PSC requires keys to be registered through its website, so the script points you to [PSC's ssh instructions](https://www.psc.edu/about-using-ssh/) instead. It also fills in your username (the `<user_id>` placeholder) in the installed skills. The department servers share one home directory, so they are set up once for all nodes.

## Contributors

Clone this repo and feel free to add any new skills or suggest improvements to existing ones. You can suggest changes on a new branch off of main and open a pull request.


# Included skills

An agent skill is a short Markdown file (`SKILL.md`) that holds the know-how for one recurring task: how to connect to a cluster, which partition to use, which errors have already been diagnosed and how they were fixed. Only each skill's name and one-line description sit in the agent's context. The agent reads the full file only when a request matches that description, so the instructions cost tokens only when they are needed.

Skills spare the agent from working out the same things from scratch in every session (probing a cluster's layout, rediscovering a module name, debugging an error someone has already solved). That saves tokens and time and keeps behavior consistent across sessions and users. They also carry rules for shared resources, such as checking a node's load before launching or keeping CPU work off GPU allocations, so the agent behaves well on machines other people depend on.

| Skill | Trigger phrases | Use cases |
|---|---|---|
| `department-servers` | "run this on a leviathan", "use ghidorah2", "the department servers", any mention of a hydra, leviathan or ghidorah node | Running jobs on the unmanaged CMU Statistics nodes: which node type to use, ssh and the shared NAS home, picking an idle node, detaching long jobs, using `/scratch` for heavy IO, and when to move the work to a managed cluster. |
| `wright` | "run this on wright", "submit to wright", "check my wright jobs" | Running Slurm jobs on `wright.hss.cmu.edu`: syncing git before running, conda activation in remote commands, `all` vs. `statds` partitions, `sbatch` patterns, monitoring, and a table of known errors. |
| `bridges2` | "run this on Bridges-2", "use PSC", "submit a GPU sweep to bridges2" | Running GPU jobs on PSC Bridges-2: modules and conda setup, project storage paths, the `GPU-shared` partition and GPU constraints, walltime limits, and a table of known errors. |
| `claude-followup` | "this will take a few hours", "chain a followup", "the followup job never reported" | Chaining an unattended Claude session onto long Slurm jobs on wright (`sbatch --dependency=afterany`), so results are summarized or failures diagnosed after the jobs finish, without the local session waiting on them. Also covers writing the followup prompt and debugging followups that fail. |
| `github-issues-workflow` | "work on issue 11", "continue #11", "pick up 11" | Treating a GitHub issue as the task: reading the issue and its latest comment, the "In Progress" label, posting progress as new comments, commit conventions, and writing up resolutions for bugs. |
