# App Hardening (Framework-Agnostic)

Organized around the OWASP API Security Top 10 categories most relevant to
a typical backend API. Framework-agnostic; see `references/nestjs.md` for
how each item maps onto NestJS.

## 1. Broken Object Level Authorization (BOLA)

Every endpoint that accepts an object identifier (`/orders/:id`,
`/files/:key`) must verify the authenticated caller is authorized for
*that specific object*, not just authenticated in general. This is the
single most common API vulnerability class and the same root cause behind
presigned-URL IDOR (`references/s3-and-presigned-urls.md`).

```
# Bad: any authenticated user can fetch any order by guessing/incrementing IDs
GET /orders/:id  → return db.orders.findById(id)

# Good: ownership check before returning
GET /orders/:id  → order = db.orders.findById(id);
                    if (order.userId !== req.user.id) throw new ForbiddenException();
                    return order;
```

## 2. Broken Authentication

- Every route requires authentication by default; exceptions are explicit,
  not implicit. A new route added without thinking about auth should fail
  closed, not open.
- Session/token expiry is enforced server-side, not just assumed from token
  claims the client could tamper with (verify signatures, verify `exp`).
- Passwords hashed with a modern algorithm (bcrypt/argon2), never stored or
  logged in plaintext.

## 3. Broken Object Property Level Authorization (mass assignment)

Reject unknown properties on input instead of accepting and silently
persisting whatever the client sends. A request body with an unexpected
`role: "admin"` or `isVerified: true` field should be rejected outright,
not accepted and ignored — "ignored" often means "assigned via an ORM's
mass-assignment convenience method that maps every provided key."

## 4. Unrestricted Resource Consumption

- Rate limit every route, with tighter limits on expensive or abusable
  endpoints (auth, search, anything that sends email or triggers a
  downstream paid API call).
- Enforce request body size limits.
- Enforce pagination — never allow an unbounded `?limit=999999` on a list
  endpoint.

## 5. Broken Function Level Authorization

Authorization is deny-by-default per route/handler, not a single global
"is logged in" check with admin logic scattered in conditionals. An admin
endpoint should require an explicit admin-role check enforced at the
routing/guard layer, not inside a handler that's easy to forget to update.

## 6. Server-Side Request Forgery (SSRF)

Any endpoint that fetches a URL supplied by a client (webhook validation,
image-from-URL upload, link preview) must validate and restrict the target:
block private/link-local IP ranges (`127.0.0.0/8`, `169.254.0.0/16`,
`10.0.0.0/8`, etc.), block the cloud metadata address, and prefer an
allowlist of expected hosts over a denylist.

## 7. Security Misconfiguration

- Security headers set (Helmet or equivalent): `X-Content-Type-Options`,
  `X-Frame-Options`, `Strict-Transport-Security`, a reasonable
  `Content-Security-Policy`.
- CORS is a strict allowlist of known origins, never `*` combined with
  credentialed requests, and never a reflected-origin wildcard.
- Default/sample credentials and debug endpoints are removed before
  deploy, not left "temporarily."
- No API documentation UI (Swagger/OpenAPI explorer) publicly reachable in
  production — it hands an attacker the full endpoint/parameter map.

## 8. Improper Inventory Management

Old or deprecated API versions still reachable are still attack surface.
Retire and remove unused routes and API versions rather than leaving them
running unmonitored alongside the current version.

## 9. Unsafe Consumption of Third-Party APIs

Treat data from third-party APIs and webhooks as untrusted input: validate
shape and content, verify webhook signatures where offered, and don't
assume a "trusted" partner's response is safe to pass through unvalidated
into a database query, a template, or a shell command.

## 10. Logging and error handling

- No stack traces, internal error messages, or secrets returned in API
  responses — return a generic message to the client and log the detail
  server-side.
- No secrets (tokens, passwords, full presigned URLs, API keys) written to
  application logs.
- Dependency audit runs in CI (`npm audit`, Dependabot/Renovate, or
  equivalent) so known-vulnerable dependencies are flagged before deploy,
  not discovered after.

## Quick checklist

- [ ] Object-level authorization on every endpoint taking an ID.
- [ ] Deny-by-default authn+authz on every route.
- [ ] Unknown request properties rejected, not silently accepted.
- [ ] Rate limiting, body size limits, pagination enforced.
- [ ] SSRF-prone endpoints validate/allowlist target hosts.
- [ ] Security headers, strict CORS allowlist, no public debug/Swagger.
- [ ] No stack traces/secrets in responses or logs.
- [ ] Dependency audit wired into CI.
