# Secrets and Environment Variables

## Credential chain, not credential values

An AWS SDK client should never be constructed with explicit credentials in
application code. The SDK default credential provider chain already resolves,
in order: environment variables, shared config/credentials file, container
credentials (ECS), and finally the instance metadata service (IMDS) for EC2.
On AWS compute, letting the chain fall through to the attached role is the
correct outcome — do not shortcut it.

**Bad:**
```ts
const s3 = new S3Client({
  region: "us-east-1",
  credentials: {
    accessKeyId: process.env.AWS_ACCESS_KEY_ID!,
    secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY!,
  },
});
```

**Good:**
```ts
const s3 = new S3Client({ region: "us-east-1" }); // default chain: role via IMDS
```

If a client explicitly passes `credentials`, that is a signal the app is
carrying a static key it does not need. Remove the block, not just the
`.env` line — leaving the block encourages someone to refill it later.

## Never a personal or admin key for an app

An app's AWS access must come from a role scoped to that app, never from a
human's own key, an "admin" key, or a shared "test" key repurposed for
production. Personal and admin credentials are broader than any single
workload needs and are harder to rotate without breaking someone's own
access. If an app currently authenticates with a human's key, treat that as
a finding regardless of the key's actual permissions.

## `.env` file rules

1. **Never committed.** Add `.env`, `.env.*` (except `.env.example`) to
   `.gitignore` before the first commit of a new project. Add a gitleaks
   pre-commit hook (`assets/gitleaks-pre-commit.yaml`) so a forgotten
   `.gitignore` entry does not silently let a secret through.
2. **Never baked into an image.** A `COPY .env` or `ADD .env` in a
   Dockerfile embeds the file in every layer and every pulled image,
   including ones pushed to a registry. Inject secrets at runtime (env vars
   from the orchestrator, mounted secret, or a secrets manager call), not at
   build time.
3. **File mode `600`, owned by the service user.** `640` or looser makes the
   file group-readable; any other local account or process running under
   the same group can read it. `chmod 600 .env && chown <service-user>:<service-user> .env`.
4. **Outside the web root.** A `.env` under a directory served by the web
   server is one misconfiguration away from being fetched directly by URL.
5. **Validated at boot with a fail-fast schema.** Parse and validate every
   expected variable before the app starts serving traffic; refuse to boot
   on a missing or malformed value instead of failing later at the call
   site. See `assets/env.validation.ts`.
6. **Only non-AWS secrets belong here, and only provisionally.** AWS access
   should come from the role (see above), not from `.env`. For third-party
   API keys and other non-AWS secrets, a `.env` is acceptable for small
   projects but a secrets manager (Secrets Manager, SSM Parameter Store
   `SecureString`) is still preferred — it adds rotation, audit trail, and
   removes the secret from the filesystem entirely.

## Using Secrets Manager / SSM Parameter Store

- Prefer SSM Parameter Store `SecureString` for simple key-value secrets at
  low cost; prefer Secrets Manager when automatic rotation, versioning, or
  cross-account sharing is needed.
- Grant read access to exactly the parameter/secret ARNs the workload needs,
  not `ssm:GetParameter` on `*`.
- Cache the fetched value in memory for the process lifetime; do not call
  the API on every request.

## If a key ever leaked (committed, pasted in chat, logged, attached to a
ticket)

Rotation is not optional once exposure happened, even if the key looks
unused. Treat "probably nobody saw it" as false.

1. **Deactivate immediately.** `aws iam update-access-key --access-key-id <ID> --status Inactive --user-name <USER>`
   stops the key from being usable while the rest of the response happens.
2. **Inspect CloudTrail** for any activity from that key: unexpected
   `iam:CreateAccessKey`, `iam:CreateUser`, `bedrock:InvokeModel`,
   `ec2:RunInstances`, or calls from unfamiliar source IPs/regions. This
   determines whether the incident is "key exposed" or "key used."
3. **Delete the key** once inactive and reviewed:
   `aws iam delete-access-key --access-key-id <ID> --user-name <USER>`.
4. **Rotate anything downstream** that depended on it: application config,
   CI secrets, any place the key (or a derivative token) was distributed.
5. **Remove the key from history**, not just from the current file —
   `git log -p` still holds it. Use `git filter-repo` or BFG, then force-push
   and have every collaborator re-clone. A `.gitignore` added after the fact
   does not remove already-committed content.
6. **Prefer eliminating the key entirely** over rotating it into another
   static key — migrate the workload to a role (`app-key-to-instance-role`
   pattern) so there is nothing left to leak next time.

## Quick checklist

- [ ] No `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` anywhere in app code
      or `.env` on AWS compute.
- [ ] `.env` in `.gitignore`, gitleaks hook installed.
- [ ] `.env` mode `600`, owned by the service user.
- [ ] `.env` outside the web root.
- [ ] Boot-time schema validation rejects missing/malformed vars.
- [ ] No `.env` copied into a Docker image layer.
