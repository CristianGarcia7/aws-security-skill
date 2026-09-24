---
name: secure-app-baseline
description: "Trigger: new backend project, NestJS/Express API, .env secrets, AWS keys, S3 upload, presigned URL, SES email, Bedrock, security group, open port, deploy. Enforce secure-by-default app and AWS practices."
license: Apache-2.0
metadata:
  author: "cristian.garcia"
  version: "1.0"
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

## Output Contract

Return: findings table (severity, file/resource, issue, fix), what was applied vs. remaining risk, and `checklist.md` result (pass/fail per item).

## References

- `references/secrets-and-env.md` — credential chain, `.env` rules, rotation.
- `references/iam-least-privilege.md` — roles, denies, guardrail caveats, IMDSv2.
- `references/network-and-ports.md` — SG rules, SSM vs SSH, private DB, audits.
- `references/s3-and-presigned-urls.md` — bucket config, presigned rules, OAC.
- `references/ses-email.md` — identity scoping, DNS auth, abuse prevention.
- `references/bedrock-and-ai.md` — deny-by-default, logging, cost controls.
- `references/app-hardening.md` — OWASP API Top 10 checklist.
- `references/nestjs.md` — NestJS mapping of every rule.
- `references/incident-lessons.md` — lessons from a real compromise.
- `references/checklist.md` — pre-deploy checklist.
- `assets/iam-app-least-privilege.json` — least-privilege IAM policy.
- `assets/s3-bucket-policy.json` — deny non-TLS, OAC-only reads.
- `assets/presigned-url.service.ts` — NestJS presigned URL example.
- `assets/env.validation.ts` — fail-fast env schema example.
- `assets/audit-env-perms.sh` — `.env` permission/secret audit.
- `assets/audit-aws-exposure.sh` — AWS exposure audit (SGs, RDS, S3, IMDS, keys).
- `assets/gitleaks-pre-commit.yaml` — pre-commit hook example.
