# Pre-Deploy Checklist

Run through every group before a new backend project's first production
deploy, and again after any change touching credentials, network, or a new
AWS service integration.

## Credentials

- [ ] No `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` in app code, `.env`,
      or a Docker image layer on AWS compute.
- [ ] No admin, "sectest", or personal key used for the app's own access.
- [ ] Off-AWS secrets sourced from Secrets Manager/SSM SecureString or
      short-lived creds (OIDC, IAM Roles Anywhere), not a static key.

## `.env` handling

- [ ] `.env` in `.gitignore`; gitleaks pre-commit hook installed
      (`assets/gitleaks-pre-commit.yaml`).
- [ ] `.env` file mode `600`, owned by the service user.
- [ ] `.env` outside the web root.
- [ ] Boot-time schema validation rejects missing/malformed vars
      (`assets/env.validation.ts`).
- [ ] No `.env` copied into a Docker image layer.

## IAM

- [ ] One dedicated role per workload; no shared "QuickSetup"-style role.
- [ ] No `*` action or resource in any allow statement.
- [ ] Explicit `Deny` on `iam:*`, `bedrock:*` (unless scoped), and
      privilege escalation.
- [ ] `simulate-principal-policy` run against the role's actual usage.
- [ ] IMDSv2 required (`HttpTokens=required`, hop limit 1, or 2 with
      justification).

## Network

- [ ] Only 80/443 world-open, only on a load balancer/CloudFront.
- [ ] No security group allows 22, 3389, 3306, 5432, 6379, 27017, or 21
      from `0.0.0.0/0` or `::/0`.
- [ ] SSM Session Manager is the shell-access path, not SSH.
- [ ] Every database has `PubliclyAccessible=false` and sits in a private
      subnet.
- [ ] Every security group rule has a description.

## S3

- [ ] Block Public Access on at account and bucket level.
- [ ] `BucketOwnerEnforced`, SSE on, non-TLS denied by bucket policy.
- [ ] No public `s3:ListBucket` on any bucket.
- [ ] Public assets served via CloudFront + OAC, not a public bucket
      policy.
- [ ] Anonymous `curl` against the bucket endpoint returns `403`.

## Presigned URLs

- [ ] Every issuance point authorizes the requesting user against the
      specific object before signing.
- [ ] TTLs are short (60–300s GET, ≤900s PUT).
- [ ] The full signed URL is never logged, cached, or embedded.
- [ ] Object keys are server-generated, never taken from client input.
- [ ] Uploads are constrained (content-type, size, presigned POST
      conditions).

## SES

- [ ] `ses:SendEmail` scoped to the exact identity ARN with an
      `ses:FromAddress` condition.
- [ ] SPF, DKIM, and DMARC configured and verified.
- [ ] `From` and recipients are never taken directly from unvalidated
      request input.
- [ ] Bounce/complaint handling configured.
- [ ] Every mail-sending endpoint has its own rate limit.

## Bedrock / AI

- [ ] `bedrock:*` denied by default on every role.
- [ ] Roles that need it allow only `InvokeModel` on named model ARNs.
- [ ] Model invocation logging enabled.
- [ ] AWS Budgets and Cost Anomaly Detection configured.

## Account baseline

- [ ] CloudTrail enabled in all regions.
- [ ] GuardDuty enabled.
- [ ] Budget alarms set.
- [ ] No root access keys; MFA enforced on human identities.

## App hardening

- [ ] Input validation rejects unknown properties on every endpoint.
- [ ] Deny-by-default authn+authz on every route.
- [ ] Object-level authorization on every endpoint taking an ID.
- [ ] Rate limiting on all routes, tighter on sensitive ones.
- [ ] Security headers (helmet) and a strict CORS allowlist.
- [ ] No stack traces or secrets in error responses or logs.
- [ ] Dependency audit wired into CI.
- [ ] No debug endpoint or Swagger/OpenAPI UI reachable in production.

## Verification run

- [ ] `assets/audit-env-perms.sh` run, findings triaged.
- [ ] `assets/audit-aws-exposure.sh` run against the target account,
      findings triaged.
