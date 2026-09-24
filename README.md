# aws-security-skill

A Claude Code skill that enforces secure-by-default practices when you build or review a backend that runs on AWS. It is framework-agnostic; NestJS is covered as an example stack.

The skill is `secure-app-baseline`. It loads automatically when you work on things like a new API, `.env` secrets, AWS keys, S3 uploads, presigned URLs, SES, Bedrock, security groups, or a deploy.

## What it enforces

- **Credentials** — no long-lived IAM access keys in code, `.env`, images, or CI. Use the attached role (instance profile, ECS task role, Lambda role), OIDC in CI, and SSO locally.
- **`.env` files** — never committed, never baked into images, mode `600`, validated at boot.
- **IAM** — one least-privilege role per workload, exact ARNs, explicit denies for `iam:*` and `bedrock:*`.
- **Network** — only 80/443 open to the world, and only on a load balancer or CloudFront. SSM instead of SSH. Private databases. IMDSv2 required.
- **S3** — Block Public Access, no public listing, TLS only. Public assets through CloudFront + OAC.
- **Presigned URLs** — only for temporary access to private objects. They are bearer tokens: authorize the user before issuing, keep the TTL short, never log them, generate object keys server-side.
- **SES and Bedrock** — scoped to one identity or model, with budget and anomaly alerts.
- **App hardening** — input validation, deny-by-default auth, rate limiting, security headers, strict CORS, no leaked internals in errors.

## Layout

```
skills/secure-app-baseline/
├── SKILL.md       # rules, decision tables, audit steps
├── references/    # detail per topic, NestJS mapping, pre-deploy checklist
└── assets/        # IAM and bucket policies, NestJS services, audit scripts
```

## Install globally (every project)

Clone once and link the skill into your personal skills folder. Claude Code reads skills from `~/.claude/skills/<name>/SKILL.md`.

```bash
git clone https://github.com/CristianGarcia7/aws-security-skill.git ~/aws-security-skill
mkdir -p ~/.claude/skills
ln -s ~/aws-security-skill/skills/secure-app-baseline ~/.claude/skills/secure-app-baseline
```

Update later with:

```bash
git -C ~/aws-security-skill pull
```

The symlink means every session picks up the new version without reinstalling.

## Install in one project

Use this when a team should get the skill from the project repository itself. Claude Code reads project skills from `.claude/skills/<name>/SKILL.md`.

```bash
# from the project root
mkdir -p .claude/skills
git clone --depth 1 https://github.com/CristianGarcia7/aws-security-skill.git /tmp/aws-security-skill
cp -R /tmp/aws-security-skill/skills/secure-app-baseline .claude/skills/
rm -rf /tmp/aws-security-skill
git add .claude/skills/secure-app-baseline
```

The copy is committed with the project, so teammates get it on clone. Repeat the steps to update it.

## Verify

Start a new Claude Code session and ask:

```
What skills are available?
```

`secure-app-baseline` should be listed. You can also invoke it directly with `/secure-app-baseline`.

## Use

It triggers on its own for security-relevant work. Typical prompts:

- "Audit this NestJS project against secure-app-baseline."
- "Add a file upload to S3 for user avatars."
- "Review the security groups before we deploy."

The audit scripts in `assets/` are read-only and can also be run by hand:

```bash
# .env permissions and AWS key patterns (values are masked)
bash ~/.claude/skills/secure-app-baseline/assets/audit-env-perms.sh <path>

# AWS exposure: open security groups, public RDS, S3 public access, IMDSv1, old access keys
bash ~/.claude/skills/secure-app-baseline/assets/audit-aws-exposure.sh --profile <profile> --region <region>
```

## Uninstall

```bash
rm ~/.claude/skills/secure-app-baseline      # global symlink
rm -rf .claude/skills/secure-app-baseline    # project copy
```

## License

Apache-2.0
