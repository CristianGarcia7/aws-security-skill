# SES Email

## Scope the sending permission to the identity

Grant `ses:SendEmail` / `ses:SendRawEmail` on the specific verified identity
ARN the workload sends from, not on `*`. Add an `ses:FromAddress` condition
so the role can only send as the address(es) it is actually meant to use,
even if the identity itself is a whole domain:

```json
{
  "Effect": "Allow",
  "Action": ["ses:SendEmail", "ses:SendRawEmail"],
  "Resource": "arn:aws:ses:<REGION>:<ACCOUNT_ID>:identity/<SES_IDENTITY>",
  "Condition": {
    "StringEquals": { "ses:FromAddress": "noreply@<DOMAIN>" }
  }
}
```

Without the `FromAddress` condition, a role scoped to a domain identity can
send as *any* address at that domain, including ones that look
administrative or that impersonate a specific person — narrowing this is
cheap and closes an easy spoofing path from inside a compromised app.

## Domain authentication: SPF, DKIM, DMARC

- **SPF** — publish a TXT record authorizing SES's sending infrastructure
  for the domain; without it, receiving servers have no basis to trust mail
  claiming to be from the domain.
- **DKIM** — enable easy DKIM signing in SES and publish the resulting CNAME
  records; this lets receivers verify the message wasn't altered in transit
  and genuinely originated from an SES-authorized sender.
- **DMARC** — publish a policy record (`p=quarantine` or `p=reject` once
  SPF/DKIM are confirmed working) so receivers know what to do with mail
  that fails alignment, instead of leaving that decision to each receiver's
  own heuristics.

Without all three, legitimate mail is more likely to land in spam, and
there is no domain-level defense against someone else's mail impersonating
the sending domain.

## Never let user input set `From` or recipients freely

**Bad:**
```ts
await ses.sendEmail({
  Source: req.body.from, // attacker controls the From header
  Destination: { ToAddresses: req.body.to }, // and every recipient
  Message: buildMessage(req.body),
});
```

This turns the endpoint into an open relay: anyone can use the app's SES
identity to send arbitrary mail to arbitrary recipients, which gets the
sending domain's reputation burned and can trigger AWS account-level
sending holds.

**Good:** the `From` address is a fixed, server-defined constant (or chosen
from a small, server-defined allowlist based on authenticated context, e.g.
"which verified store is this seller sending as"). Recipients come from
data the server already trusts (the authenticated user's own email, or an
address looked up from a database record the user is confirmed to own) —
never a raw field copied from the request body into `Destination`.

## Handle bounces and complaints

Configure an SNS topic for bounce and complaint notifications on the
identity, and process them: suppress future sends to addresses that hard-
bounce or complain. Ignoring this both wastes sends and, at scale, degrades
the domain's sending reputation with mailbox providers who track complaint
rates per sending identity.

## Rate limit endpoints that send mail

Any endpoint that triggers an email send (signup confirmation, password
reset, invite, contact form) needs its own rate limit, independent of the
general API rate limit — these are exactly the endpoints an attacker uses
to mail-bomb a third party or enumerate valid accounts by observing send
behavior. SES also enforces an account-level sending quota; a burst from
one endpoint can exhaust it and block legitimate mail from the rest of the
application.

## Quick checklist

- [ ] `ses:SendEmail` scoped to the exact identity ARN, not `*`.
- [ ] `ses:FromAddress` condition present.
- [ ] SPF, DKIM, and DMARC all configured and verified.
- [ ] `From` and recipients are never taken directly from unauthenticated
      or unvalidated request input.
- [ ] Bounce/complaint SNS topic configured and processed.
- [ ] Every mail-sending endpoint has its own rate limit.
