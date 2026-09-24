# IAM Least Privilege

## One role per workload

Each application, service, or function gets its own IAM role, scoped to the
exact AWS resources it touches. Do not attach a shared "platform" or
"QuickSetup"-style role to multiple workloads — it accumulates permissions
over time as different apps need different things, and eventually every app
on that role can do everything every other app can do. A compromise of the
weakest app then grants access to every resource the strongest app needs.

**Bad — one shared role for every instance:**
```json
{
  "Effect": "Allow",
  "Action": "s3:*",
  "Resource": "*"
}
```

**Good — scoped to exact ARNs:**
```json
{
  "Effect": "Allow",
  "Action": ["s3:GetObject", "s3:PutObject"],
  "Resource": "arn:aws:s3:::<BUCKET>/<PREFIX>/*"
}
```

See `assets/iam-app-least-privilege.json` for a full template with S3 and SES
scoped statements.

## No wildcards

`"Action": "*"` and `"Resource": "*"` are the two most common findings in an
over-permissioned role. Every statement should name the specific action(s)
(`s3:GetObject`, not `s3:*`) and the specific resource ARN(s), including a
prefix constraint when the workload only needs part of a bucket.

## Explicit denies

A least-privilege *allow* list is not enough on its own — a later policy
change or an attached managed policy can reintroduce broad access. Add
explicit `Deny` statements for the actions a workload should never be able
to perform, regardless of what else gets attached to the role later:

```json
{
  "Effect": "Deny",
  "Action": [
    "iam:*",
    "bedrock:*"
  ],
  "Resource": "*"
}
```

Drop the `bedrock:*` deny only if the workload legitimately calls Bedrock,
and then scope it to `bedrock:InvokeModel` on specific model ARNs instead
of removing the deny outright (`references/bedrock-and-ai.md`).

Also deny privilege-escalation actions the workload never needs:
`iam:CreatePolicyVersion`, `iam:SetDefaultPolicyVersion`,
`iam:AttachRolePolicy`, `iam:PutRolePolicy`, `sts:AssumeRole` on roles other
than its own. These are the actions an attacker uses to turn one compromised
role into broader account access.

## Optional credential guardrail (SourceIp / SourceVpc)

A role can deny use of its own credentials unless the request originates
from the workload's own known egress IP or VPC:

```json
{
  "Effect": "Deny",
  "NotAction": "sts:GetCallerIdentity",
  "Resource": "*",
  "Condition": {
    "NotIpAddressIfExists": { "aws:SourceIp": "<WORKLOAD_EGRESS_CIDR>" },
    "BoolIfExists": { "aws:ViaAWSService": "false" }
  }
}
```

This is a real containment control: if the role's credentials (or the
instance's IMDS-sourced credentials) leak, they are unusable from any other
network. It is what actually stops a stolen credential from being used
off-host — an IP allowlist on the *human* access path (SSO permission set)
does not touch this at all, because that is a separate, independent gate.

### Caveats — read before relying on this guardrail

- **`NotIpAddressIfExists` has a hole.** The condition only evaluates when
  `aws:SourceIp` is present on the request. A request that carries no
  `aws:SourceIp` key at all escapes the deny entirely. Pair it with
  `BoolIfExists { "aws:ViaAWSService": "false" }` to cover the ordinary
  service-initiated case, but do not treat the combination as absolute.
- **It breaks presigned URLs fetched by a browser or third party.** A
  presigned URL is signed with the role's credentials, but the *request
  against S3* happens from the browser's IP, not the workload's. If the
  guardrail is scoped to the workload's own egress IP, that browser request
  gets an explicit deny. Do not weaken the guardrail to fix this — route
  the file through a backend proxy instead (`references/s3-and-presigned-urls.md`,
  Decision Gate: "Private, IP guardrail active").
- **It does not protect against host-level compromise.** If an attacker has
  a shell on the instance itself, they call AWS from the instance's own IP
  and pass the guardrail trivially. This control stops *exfiltrated*
  credentials from being used elsewhere — it is not a substitute for not
  getting compromised.

## IMDSv2 required

Set `HttpTokens=required` on every instance's metadata options, with a hop
limit of 1 (raise to 2 only when the workload runs inside a container that
adds a network hop to reach IMDS). IMDSv1 allows credential retrieval via a
simple unauthenticated GET, which is trivially exploitable by SSRF; IMDSv2
requires a session token obtained via a PUT, which most SSRF vectors cannot
perform.

```
aws ec2 modify-instance-metadata-options \
  --instance-id <INSTANCE_ID> \
  --http-tokens required \
  --http-put-response-hop-limit 1
```

## Verify before trusting the policy

Do not assume a policy is correct because it reads correctly — simulate it:

```
aws iam simulate-principal-policy \
  --policy-source-arn <ROLE_ARN> \
  --action-names s3:GetObject s3:PutObject s3:ListBucket iam:CreateUser \
  --resource-arns arn:aws:s3:::<BUCKET>/<PREFIX>/*
```

Confirm every action the workload needs returns `allowed` and every action
it should not have (other buckets, `iam:*`, `bedrock:*` unless scoped)
returns `implicitDeny` or `explicitDeny`.

## Quick checklist

- [ ] One role per workload, not shared across apps.
- [ ] No `*` action or resource in any allow statement.
- [ ] Explicit deny on `iam:*`, `bedrock:*` (unless scoped), and
      privilege-escalation actions.
- [ ] IMDSv2 required, hop limit 1 (or 2 with justification).
- [ ] `simulate-principal-policy` run and reviewed, not assumed.
