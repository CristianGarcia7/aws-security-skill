# aws-security-skill

A skill is a set of instructions your AI coding agent loads automatically so
it builds secure backends by default — no pasting rules into every prompt.
This one is called `secure-app-baseline`. It teaches your agent secure AWS
and app defaults: credentials, `.env` files, IAM, network ports, S3,
presigned URLs, SES, Bedrock, and general app hardening.

Works with **Claude Code, Codex CLI, OpenCode, Pi, and Kiro**.

## Quick install

```bash
git clone https://github.com/CristianGarcia7/aws-security-skill.git ~/aws-security-skill
cd ~/aws-security-skill
./install.sh
```

Then **restart your agent**.

To update later:

```bash
cd ~/aws-security-skill && git pull && ./install.sh
```

## What is a skill?

- It's just a folder with a file called `SKILL.md` inside.
- `SKILL.md` starts with a short description. Your agent reads that
  description up front, for every skill it has installed.
- The agent only loads the full rules when your current task matches that
  description — for example, when you mention `.env`, S3, or a security
  group.
- You never paste anything. Once installed, it works in the background.

## Why this skill exists

It comes from lessons learned in a real AWS account compromise (details
anonymized: no amounts, names, or IDs). The pattern was generic, and it is
common:

- Security groups left ports open to the whole internet.
- Long-lived admin AWS keys sitting in a `.env` file that other accounts on
  the server could also read.
- One shared, over-privileged server role used by every instance, so
  compromising one instance gave access to everything.
- Once credentials leaked, they were used to call an AI model service
  (Bedrock) directly — running up a very large bill in the attacker's
  favor, not the app's.

Each of those is a normal mistake an agent can make while "just getting
something working." This skill exists so the agent avoids them from the
start.

## What it protects you from

| Risk | What the skill makes the agent do |
|---|---|
| Leaked AWS credentials | Use the instance/server's attached IAM role instead of long-lived access keys. No keys in code or `.env`. |
| Exposed `.env` secrets | Keep `.env` out of git, mode `600` (owner-only), never baked into a Docker image. |
| Over-privileged IAM | One narrow role per workload, scoped to exact resources — never a shared "do everything" role. |
| Open ports | Only 80/443 open, only on a load balancer. SSH replaced by SSM. Databases kept private. |
| Public S3 buckets | Block Public Access on by default. Public files go through CloudFront, not a public bucket. |
| Presigned URL misuse | See note below — presigned URLs are treated as bearer tokens, not casual links. |
| SES abuse | Sending scoped to one verified identity, with bounce/complaint handling. |
| Bedrock (AI) abuse | Denied by default; allowed only for named models, with budget alerts on. |
| Weak app defaults | Input validation, deny-by-default auth, rate limiting, security headers, no leaked stack traces. |

**Presigned URL nuance:** a presigned URL is only needed for *temporary*
access to a *private* file. A public file doesn't need one. Think of a
presigned URL like a spare key: anyone holding the link can use it until it
expires — so the skill makes the agent check the user's permission *before*
creating it, keep the expiry short, and never log the URL itself.

## When does it activate?

The agent loads this skill on its own when your prompt touches:

- A new backend/API project
- `.env` files or AWS credentials
- S3 uploads, downloads, or presigned URLs
- SES email sending
- Bedrock or another AI service call
- Security groups, ports, or a deploy

You can also call it by name if you want to be explicit:

| Agent | How to call it explicitly |
|---|---|
| Claude Code | `/secure-app-baseline` |
| Codex CLI | `/skills`, or type `$` to mention it |
| OpenCode | Ask: "use the secure-app-baseline skill" |
| Pi | `/skill:secure-app-baseline` |
| Kiro | Type `/` and pick it from the list |

## Install options

By default `./install.sh` installs **globally**, for **all 5 agents**:

| Agent | Global folder | Project folder |
|---|---|---|
| Claude Code | `~/.claude/skills/` | `.claude/skills/` |
| Codex CLI | `~/.agents/skills/` | `.agents/skills/` |
| OpenCode | `~/.claude/skills/` or `~/.agents/skills/` | `.claude/skills/` or `.agents/skills/` |
| Pi | `~/.agents/skills/` | `.agents/skills/` |
| Kiro | `~/.kiro/skills/` | `.kiro/skills/` |

Only some agents:

```bash
./install.sh --agents claude,codex
```

Per project, instead of globally:

```bash
cd your-project
~/aws-security-skill/install.sh --project .
```

Commit it so your teammates get it automatically on `git clone`:

```bash
git add .claude/skills/secure-app-baseline .agents/skills/secure-app-baseline .kiro/skills/secure-app-baseline
git commit -m "chore: add secure-app-baseline skill"
```

(Only add the folders `install.sh` actually created for you.)

### Manual install (without the script)

```bash
mkdir -p ~/.claude/skills ~/.agents/skills ~/.kiro/skills
cp -R ~/aws-security-skill/skills/secure-app-baseline ~/.claude/skills/
cp -R ~/aws-security-skill/skills/secure-app-baseline ~/.agents/skills/
cp -R ~/aws-security-skill/skills/secure-app-baseline ~/.kiro/skills/
```

The script **copies** the skill instead of linking it, because not every
agent's symlink support is documented. Claude Code and Codex CLI do
document symlinks, so if you prefer a live link for those two, you can do it
by hand:

```bash
ln -s ~/aws-security-skill/skills/secure-app-baseline ~/.claude/skills/secure-app-baseline
```

## Check it works

| Agent | How to check |
|---|---|
| Claude Code | Ask "what skills do you have?" |
| Codex CLI | Run `/skills` |
| OpenCode | Ask "what skills do you have?" |
| Pi | Ask "what skills do you have?" |
| Kiro | Type `/` and look at the list |

You should see `secure-app-baseline` in the list.

## Try it

- "Add a file upload to S3 for user avatars."
- "Review the security groups before we deploy."
- "Audit this NestJS project against secure-app-baseline."

## What's inside

```
skills/secure-app-baseline/
├── SKILL.md       # rules, decision tables, audit steps
├── references/    # one file per topic (IAM, network, S3, SES, Bedrock, NestJS...)
└── assets/        # example policies, example code, and 2 audit scripts
```

The two audit scripts are **read-only** — they never change anything, only
report:

```bash
# .env file permissions and AWS key patterns (values are masked)
bash skills/secure-app-baseline/assets/audit-env-perms.sh <path>

# AWS exposure: open ports, public RDS, public S3, IMDSv1, old access keys
bash skills/secure-app-baseline/assets/audit-aws-exposure.sh --profile <profile> --region <region>
```

## Update

```bash
cd ~/aws-security-skill && git pull && ./install.sh
```

## Uninstall

```bash
cd ~/aws-security-skill && ./install.sh --uninstall

# or, for a project install:
./install.sh --uninstall --project /path/to/project
```

## Troubleshooting

| Problem | Try this |
|---|---|
| Skill not listed | Restart your agent. Check the folder is named exactly `secure-app-baseline`. Check it's in the right path from the table above. |
| Kiro or OpenCode doesn't find it | Confirm the folder exists at the path their table row shows. |
| Permission error during install | Never use `sudo` with this script. Check you own the target folder (`~/.claude`, `~/.agents`, `~/.kiro`, or your project folder). |

## License

Apache-2.0 — see [LICENSE](LICENSE).
