---
name: secure-app-baseline
description: "Trigger: new backend project, NestJS/Express API, .env secrets, AWS keys, S3 upload, presigned URL, SES email, Bedrock, security group, open port, deploy. Enforce secure-by-default app and AWS practices."
license: Apache-2.0
metadata:
  author: "cristian.garcia"
  version: "1.1"
---

## Activation Contract

Load for backend work touching AWS: new API project, `.env`/secrets, S3 upload/download, presigned URLs, SES, Bedrock/AI, security-group/network changes, or deploy. Framework-agnostic; NestJS mapping in `references/nestjs.md`. If installed, `nestjs-best-practices`, `securing-s3-buckets`, `aws-iam` add depth — this is the baseline.

## Hard Rules

- **Credentials**: on AWS compute, only the attached role (instance profile / ECS task role / Lambda role), SDK default chain — no explicit keys in code. Never an admin/"sectest"/personal key. Off-AWS: OIDC, IAM Roles Anywhere, or Secrets Manager/SSM SecureString.
- **`.env`**: never committed (`.gitignore` + gitleaks pre-commit), never baked into an image, mode `600` owned by the service user (640 leaks to group), outside web root, fail-fast schema at boot. Non-AWS secrets only; secrets manager still preferred. Rotate anything that ever touched a repo, chat, ticket, or log.
- **IAM**: one role per workload, least privilege on exact ARNs — no `*`, no shared super role. Explicit `Deny` on `iam:*`, `bedrock:*` (unless required), privilege escalation. Optional egress-IP/VPC deny guardrail — breaks browser-fetched presigned URLs; scope deliberately.
- **IMDSv2** required: `HttpTokens=required`, hop limit 1 (2 only for containers).
- **Network**: SGs default-deny; only 80/443 world-open, only on an LB/CloudFront. Never `0.0.0.0/0`/`::/0` on 22, 3389, 3306, 5432, 6379, 27017, 21, or an admin panel. SSM instead of SSH. DBs private, `PubliclyAccessible=false`. Every rule has a description; every temporary grant a revoke.
- **S3**: Block Public Access on (account + bucket), `BucketOwnerEnforced`, SSE on, deny non-TLS, never public `s3:ListBucket`. Private → presigned URLs; public assets → CloudFront + OAC, not a public bucket.
- **Presigned URLs**: temporary access to PRIVATE objects only — not every URL needs signing. It is a bearer token, usable by any holder until expiry. Authorize the user against the exact object BEFORE issuing; short TTL (60–300s GET, ≤900s PUT); never log/cache/embed the URL; server-generated keys only, never a client path (traversal/IDOR); constrain uploads (content-type, size, POST conditions). Also capped by the signing credential's lifetime.
- **SES**: `ses:SendEmail` on the identity ARN plus `ses:FromAddress` condition; SPF/DKIM/DMARC set; never let user input set `From`/recipients; handle bounces/complaints; rate-limit sending endpoints.
- **Bedrock/AI**: deny by default; if needed, only `bedrock:InvokeModel` on specific model ARNs, invocation logging on, Budgets + Cost Anomaly Detection — leaked keys enable LLMjacking.
- **Baseline**: CloudTrail all-regions, GuardDuty, budget alarms, no root keys, MFA. App: whitelist validation, deny-by-default authn+authz per route, rate limiting, helmet headers, CORS allowlist, no stack traces/secrets in errors/logs, dependency audit, no debug/Swagger in prod.
- **Improvement loop**: source repo `github.com/CristianGarcia7/aws-security-skill`. If a rule was missing, wrong, or ambiguous, or an asset failed, ask the user ONE yes/no question after the task to contribute a fix. Never submit without explicit approval; privacy-scrub first (no IDs, IPs, keys, names, amounts). Flow: `references/improving-this-skill.md`.

## Decision Gates

| Credential source? | Use |
|---|---|
| AWS compute | attached role, SDK default chain |
| CI/CD | OIDC, no static keys |
| Local dev | SSO profile (`aws sso login`) |
| Third-party API key | Secrets Manager/SSM |

| Serving a file? | Use |
|---|---|
| Public asset | CloudFront + OAC |
| Private, browser-facing | presigned GET after authz |
| Private, IP guardrail active | backend streaming/media proxy |
| Upload | presigned PUT/POST, conditions |

| Port request? | Route |
|---|---|
| Web traffic | load balancer :443 |
| Admin/shell | SSM Session Manager |
| Database | private SG reference only |

## Execution Steps

1. Inventory: AWS SDK calls, `.env` files, hardcoded keys, S3/SES/Bedrock usage.
2. Verify credential source: role-based on AWS compute, no static keys.
3. Build/verify IAM policy from `assets/iam-app-least-privilege.json`, scoped to exact resources.
4. Check network: SGs, IMDSv2, DB exposure (`references/network-and-ports.md`).
5. Check S3, SES, Bedrock per matching `references/*.md`.
6. Check app-level hardening (`references/app-hardening.md`, `references/nestjs.md` if NestJS).
7. Run `assets/audit-env-perms.sh`, `assets/audit-aws-exposure.sh`; walk `references/checklist.md`.
8. Report findings and fixes applied.
9. If a skill gap appeared, ask the improvement question and stop until answered.

## Output Contract

Return: findings table (severity, file/resource, issue, fix), what was applied vs. remaining risk, and `checklist.md` result (pass/fail per item). If a skill gap was found, end with the single improvement question.

## References

- `references/` — one file per topic: `secrets-and-env`, `iam-least-privilege`, `network-and-ports`, `s3-and-presigned-urls`, `ses-email`, `bedrock-and-ai`, `app-hardening` (OWASP API Top 10), `nestjs` (NestJS mapping), `incident-lessons`, `checklist` (pre-deploy).
- `references/improving-this-skill.md` — approval-gated contribution flow to the source repo.
- `assets/` — `iam-app-least-privilege.json`, `s3-bucket-policy.json`, `presigned-url.service.ts`, `env.validation.ts`, `gitleaks-pre-commit.yaml`, read-only audits `audit-env-perms.sh` and `audit-aws-exposure.sh`.
