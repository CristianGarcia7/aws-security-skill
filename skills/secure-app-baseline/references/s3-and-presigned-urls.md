# S3 and Presigned URLs

## Bucket configuration baseline

Every bucket a new project creates should start from this configuration,
not have it added later after a finding:

- **Block Public Access** enabled at both the account level and the bucket
  level (all four settings: `BlockPublicAcls`, `IgnorePublicAcls`,
  `BlockPublicPolicy`, `RestrictPublicBuckets`). This is the single control
  that prevents an accidental public bucket policy or ACL from ever taking
  effect.
- **`BucketOwnerEnforced`** object ownership — disables ACLs entirely so
  access is governed only by bucket policy and IAM, which is easier to
  audit than a mix of both.
- **Server-side encryption (SSE)** on by default (SSE-S3 or SSE-KMS).
- **Deny non-TLS requests** via bucket policy (`aws:SecureTransport: false`
  → deny), so a client cannot accidentally or deliberately fetch/put over
  plain HTTP.
- **Never grant public `s3:ListBucket`.** Listing a bucket's contents
  enumerates every object key, which defeats "security by obscurity" object
  naming and hands an attacker a target list. This holds even for buckets
  that otherwise serve public content — public *read of specific objects*
  is a different grant than public *listing*.

See `assets/s3-bucket-policy.json` for the deny-non-TLS and
OAC-only-reads statements.

## Private objects vs. public assets — different mechanisms

| Content | Mechanism | Not this |
|---|---|---|
| Private, user-specific (uploads, generated reports, user photos) | Presigned URL, issued after authorization | A public bucket, "unguessable" keys as the only protection |
| Public, static (marketing assets, public downloads) | CloudFront distribution with Origin Access Control (OAC) | A public-read bucket policy |

CloudFront + OAC keeps the bucket itself fully private (Block Public Access
still on) while serving content publicly through the distribution, which
also gets you caching, HTTPS, and a WAF attachment point for free. A
public-read bucket policy has none of that and is one policy edit away from
exposing more than intended.

## Presigned URLs — the core rules

A presigned URL grants temporary access to a **private** object. Not every
URL needs to be signed — public assets should go through CloudFront + OAC
instead, with no signing involved. Reach for a presigned URL only when the
object must stay private and the request is a browser or client action
against a specific object.

**A presigned URL is a bearer token.** Whoever holds the URL — in a browser
tab, a forwarded email, a server log, a browser history entry, an analytics
tool that captured the full request URL — can use it until it expires, with
no further authentication check. Treat it with the same handling discipline
as a session cookie or an API key, not as an opaque link.

1. **Authorize before issuing, not after.** Check that the requesting user
   is allowed to access *this specific object* before generating the
   presigned URL — the signing step itself carries no authorization logic,
   so the check has to happen in application code first. Never presign an
   object key received or reconstructed from client input without this
   check: that is exactly how an IDOR (Insecure Direct Object Reference)
   happens — one user swaps an object key in a request and receives a URL
   into another user's private object.
2. **Short TTL.** 60–300 seconds for a `GET`, up to 900 seconds (15 minutes,
   the practical upper bound for SigV4) for a `PUT`. A long-lived presigned
   URL widens the exposure window for every way it might leak.
3. **Never log, cache, or embed the full URL.** The signature is part of the
   query string — logging the full request URL for observability purposes
   logs a working credential. Log the object key and requesting user
   instead.
4. **Generate object keys server-side.** Never accept a client-supplied path
   as the object key. Derive it from a server-known identifier (user ID +
   UUID, or similar) so a client cannot request a presigned URL for a key
   under a path traversal (`../other-user/secret.pdf`) or another tenant's
   prefix.
5. **Constrain uploads.** For `PUT`, set an explicit `ContentType` and rely
   on the signature covering it; for broader control (max size, allowed
   content types, required key prefix), use a presigned **POST** with
   conditions instead of a presigned PUT — POST conditions are enforced by
   S3 at upload time, not just suggested to the client.
6. **Validity is also capped by the signing credential's own lifetime.** A
   presigned URL signed with temporary role credentials (from an EC2/ECS/
   Lambda role) stops working when those credentials expire, even if the
   URL's own TTL hasn't elapsed yet. This is usually not a problem given
   short TTLs, but it means a presigned URL generated right before a
   credential refresh can fail earlier than its stated expiry.

See `assets/presigned-url.service.ts` for a NestJS implementation applying
all six rules.

## IDOR example (what rule 1 and rule 4 prevent)

```
# Bad: client controls the key entirely
GET /files/presign?key=invoices/2024/acme-corp/invoice-042.pdf
# → app signs whatever key is given, no ownership check

# Good: server resolves the key from the authenticated user + a database
# lookup of an invoice ID the user is confirmed to own
GET /files/invoices/042/download-url
# → app looks up invoice 042, checks req.user.id === invoice.ownerId,
#   then presigns the key it already knows: invoices/<ownerId>/<uuid>.pdf
```

## Verification: bucket must not be publicly listable or readable

```
curl -s -o /dev/null -w "%{http_code}\n" https://<BUCKET>.s3.amazonaws.com/
```

Expect `403` (AccessDenied), not `200` (listing succeeded) or a redirect to
a working object. Run this anonymously (no AWS credentials) as part of a
pre-deploy check — this is exactly the check `assets/audit-aws-exposure.sh`
automates across every bucket in an account.

## Quick checklist

- [ ] Block Public Access on at account and bucket level.
- [ ] `BucketOwnerEnforced`, SSE on, non-TLS denied by bucket policy.
- [ ] No public `s3:ListBucket` on any bucket.
- [ ] Public assets served via CloudFront + OAC, not a public bucket policy.
- [ ] Every presigned URL issuance point authorizes the object first.
- [ ] TTLs are short; the full URL is never logged.
- [ ] Object keys are server-generated, never taken from client input.
