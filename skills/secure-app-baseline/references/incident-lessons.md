# Incident Lessons (Anonymized)

These lessons come from a real AWS account compromise that resulted in
substantial unauthorized charges before it was contained. No
account IDs, instance IDs, IP addresses, or people's names are included —
the value here is the root-cause pattern, which is generic and reproducible
in any AWS account that skips the baseline in this skill.

## What went wrong, by root class

### 1. World-open ports across many resources

Dozens of security groups had SSH (22), a hosting control panel's admin
ports, FTP control and passive-range ports, and a database port open to
`0.0.0.0/0` (and on at least one group, `::/0`). This was not one
misconfigured instance — it was a pattern repeated across every resource
provisioned from the same template, which is how one bad default becomes an
account-wide exposure. **Lesson: audit security groups as a set, not one at
a time — a template mistake replicates.**

### 2. Long-lived admin keys in `.env`, loosely permissioned

An application `.env` file held long-lived IAM access keys belonging to an
administrative identity — not a scoped application identity — and the file
was readable by the file's group (mode `640`), not just its owner. Any
process or account sharing that group could read the keys without needing
root. **Lesson: an app's credentials must be scoped to the app, and a
`.env`'s file mode is itself a control, not a formality.**

### 3. A shared, over-privileged instance role abused via IMDS

Every instance in the fleet shared one broadly-scoped instance role,
originally created by a one-click setup wizard for a managed-instance
feature and never narrowed afterward. Once any single instance was reached,
its IMDS endpoint handed over credentials that worked across the entire
fleet's worth of granted permissions — the compromise of one weak entry
point inherited the access footprint of every workload sharing that role.
**Lesson: a "QuickSetup" or wizard-generated role is a starting point, not
a destination — narrow it to one role per workload before going to
production.**

### 4. AI service abuse with leaked credentials (LLMjacking)

Once credentials were exfiltrated, they were used to invoke a managed AI
model-hosting service directly, generating usage charges attributable to
the attacker rather than any legitimate workload. This is a distinct and
now common monetization path for leaked AWS credentials — the attacker does
not need to mine cryptocurrency or spin up EC2 fleets when a pay-per-token
inference API is reachable with the same stolen key. **Lesson: deny AI
service actions by default on every role; only allow `InvokeModel` on
named model ARNs for roles that actually call the service, and set cost
alerts before you need them, not after.**

### 5. A publicly accessible database

At least one database instance was reachable directly from the internet
(`PubliclyAccessible=true`, in a subnet with a route to an internet
gateway), rather than sitting behind the application tier in a private
subnet. **Lesson: `PubliclyAccessible=false` and a private subnet are not
optional defaults — verify them explicitly, since some provisioning paths
default the flag to `true`.**

### 6. An IP allowlist that only covered part of the access surface

A control restricting a sensitive session-management action to a known set
of office IP ranges existed — but it was implemented only on the
human-facing SSO permission sets. It did not, and structurally could not,
constrain a compromised instance's own role, because a role's IMDS-sourced
credentials are a completely separate access path from a human's federated
session. Responders initially treated the allowlist as covering "all
access" and lost time before realizing it never touched the actual
compromise vector. **Lesson: enumerate every distinct access path
(human SSO, IAM users, instance roles, service-linked roles) before
concluding a single control covers "access" — each needs its own analysis
and, where relevant, its own guardrail.**

### 7. Observed traffic is a lower bound, not a complete picture

When narrowing an allowlist to a vendor's shared egress range, the team
used historical connection logs to identify which specific addresses within
a larger published range had actually been seen, and scoped the allowlist
to that narrower set. Within 24 hours, legitimate traffic arrived from
addresses outside the narrowed set — the vendor's pool rotated addresses
the logs had simply never captured yet. **Lesson: when scoping a range from
a shared-egress or dynamic-address vendor, treat historical observation as
a floor, not a ceiling. Either accept the vendor's full published range (and
the shared-tenancy exposure that comes with it) or get a dedicated,
contracted egress address — do not present an observation-based prefix as
complete.**

## The controls that actually stopped repeat exposure

- Moving every instance off the shared wizard-generated role onto a
  dedicated per-workload role, scoped to exactly what that workload needs,
  closed the IMDS-based lateral movement path. This is the single highest-
  leverage fix among everything above.
- An explicit deny on the role's own credentials outside the workload's own
  known network address meant that even a subsequently leaked credential
  would fail when used from anywhere else — a second, independent layer
  behind least privilege.
- Closing every world-open port and moving shell access to SSM removed the
  network-level entry points entirely, rather than relying on credential
  controls alone to contain an intrusion that starts from an open port.

## How to apply this without repeating it

Every hard rule in `SKILL.md` maps to one of the root classes above. Running
this skill's Execution Steps against a new project before it reaches
production is materially cheaper than responding to the same pattern after
the fact.
