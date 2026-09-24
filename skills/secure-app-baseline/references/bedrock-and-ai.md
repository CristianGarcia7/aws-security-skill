# Bedrock and AI Services

## Deny by default

Every role should start with an explicit `Deny` on `bedrock:*` (see
`references/iam-least-privilege.md`). Only remove or scope down that deny
for roles that a workload genuinely uses to call a Bedrock model. Do not
leave Bedrock reachable "just in case" — an idle allow on an AI-invocation
service is a standing liability with no offsetting benefit until the day a
credential leaks.

## If the workload needs it, scope narrowly

Allow only `bedrock:InvokeModel` (and `bedrock:InvokeModelWithResponseStream`
if streaming is used) on the specific model ARNs the workload actually
calls — not `bedrock:*`, and not a resource wildcard across every model in
the account:

```json
{
  "Effect": "Allow",
  "Action": ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"],
  "Resource": "arn:aws:bedrock:<REGION>::foundation-model/<MODEL_ID>"
}
```

Do not grant `bedrock:CreateModelCustomizationJob`,
`bedrock:CreateProvisionedModelThroughput`, or other account-shaping actions
to an application role — those belong to a human or CI identity managing
the account's Bedrock configuration, not to a runtime workload.

## Enable model invocation logging

Turn on Bedrock model invocation logging (to CloudWatch Logs and/or S3).
Without it, there is no per-call record of which model was invoked, by
which identity, with what input size — which is exactly the evidence needed
to detect abuse quickly rather than discovering it on the next bill.

## Set cost guardrails before you need them

- **AWS Budgets**: create a budget with alert thresholds (e.g., 50%/80%/100%
  of expected monthly spend) that notifies a real channel, not just an
  email nobody watches.
- **Cost Anomaly Detection**: enable it for Bedrock (and broadly across the
  account) so an unexpected spike in usage — the signature of a leaked
  credential being used for inference — triggers an alert on its own,
  independent of the fixed budget thresholds.

## Why this matters: LLMjacking

Leaked AWS credentials are increasingly monetized by calling a managed
inference API directly ("LLMjacking") rather than through more traditional
paths like cryptocurrency mining or spinning up compute fleets. A pay-per-
token inference service reachable with a stolen key can generate a very
large bill in a short window with no infrastructure for the attacker to
provision or maintain — the deny-by-default rule above, combined with
model-ARN scoping and cost alerting, is what limits both the blast radius
and the time-to-detection if a credential does leak.

## Quick checklist

- [ ] `bedrock:*` explicitly denied on every role by default.
- [ ] Roles that call Bedrock allow only `InvokeModel`
      (`+InvokeModelWithResponseStream` if needed) on named model ARNs.
- [ ] Model invocation logging enabled.
- [ ] AWS Budgets alert thresholds configured for the account.
- [ ] Cost Anomaly Detection enabled.
