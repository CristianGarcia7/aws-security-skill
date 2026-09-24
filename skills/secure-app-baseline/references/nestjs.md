# NestJS Mapping

How each Hard Rule and `references/app-hardening.md` item maps onto NestJS
specifically. This is the framework-specific layer over the
framework-agnostic core in `SKILL.md`.

## Config and env validation

Use `@nestjs/config` with a validation schema so the app fails fast on boot
instead of failing at the first call site that touches a missing variable:

```ts
// app.module.ts
ConfigModule.forRoot({
  isGlobal: true,
  validate: validateEnv, // from assets/env.validation.ts
});
```

`assets/env.validation.ts` shows a Zod schema that also rejects
`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` when `NODE_ENV=production`,
enforcing the "no explicit AWS keys" hard rule at boot time rather than
relying on code review to catch it.

## Input validation (mass assignment / BOLA support)

```ts
// main.ts
app.useGlobalPipes(new ValidationPipe({
  whitelist: true,            // strips unknown properties
  forbidNonWhitelisted: true, // rejects the request instead of silently stripping
  transform: true,            // coerces payloads into typed DTO instances
}));
```

`whitelist` + `forbidNonWhitelisted` together implement the
"reject unknown properties" rule from `references/app-hardening.md` #3 —
without `forbidNonWhitelisted`, unexpected fields are dropped silently,
which hides the problem instead of surfacing it.

## Deny-by-default authorization

Register a global guard and opt individual routes *out* with a decorator,
rather than opting routes *in* to auth one at a time — a forgotten `@UseGuards`
on a new route is a silent hole; a forgotten `@Public()` fails closed.

```ts
// app.module.ts
{ provide: APP_GUARD, useClass: AuthGuard }

// public.decorator.ts
export const IS_PUBLIC_KEY = "isPublic";
export const Public = () => SetMetadata(IS_PUBLIC_KEY, true);

// auth.guard.ts
canActivate(context: ExecutionContext) {
  const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
    context.getHandler(),
    context.getClass(),
  ]);
  if (isPublic) return true;
  return super.canActivate(context); // normal auth check
}
```

Object-level authorization (BOLA) still needs an explicit ownership check
inside the handler or a resource-scoped guard — the global guard only
proves *who* the caller is, not *what* they're allowed to touch.

## Rate limiting

```ts
// app.module.ts
ThrottlerModule.forRoot([{ ttl: 60000, limit: 100 }]);

// on a sensitive route
@Throttle({ default: { limit: 5, ttl: 60000 } })
@Post("auth/login")
login() { /* ... */ }
```

## Security headers and CORS

```ts
// main.ts
app.use(helmet());
app.enableCors({
  origin: ["https://app.example.com"], // explicit allowlist, never "*"
  credentials: true,
});
```

## Hiding internals on error

A global exception filter ensures an unhandled error never leaks a stack
trace or internal message to the client:

```ts
@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  catch(exception: unknown, host: ArgumentsHost) {
    const res = host.switchToHttp().getResponse();
    const status = exception instanceof HttpException ? exception.getStatus() : 500;
    // log the full exception server-side here
    res.status(status).json({ statusCode: status, message: "Internal error" });
  }
}
```

## AWS SDK v3 clients without credentials

```ts
// Good: default credential chain (role via IMDS on AWS compute)
const s3 = new S3Client({ region: process.env.AWS_REGION });

// Bad: never do this in a NestJS provider
const s3 = new S3Client({
  credentials: { accessKeyId: ..., secretAccessKey: ... },
});
```

Provide the client via a NestJS provider/factory so every module injects
the same correctly-configured instance instead of constructing its own.

## Disabling Swagger in production

```ts
// main.ts
if (process.env.NODE_ENV !== "production") {
  const config = new DocumentBuilder().setTitle("API").build();
  const document = SwaggerModule.createDocument(app, config);
  SwaggerModule.setup("docs", app, document);
}
```

Gate it on environment, not on a flag that could be left on by mistake —
default to *not* mounting the docs route in production.

## Quick checklist

- [ ] `@nestjs/config` + schema validation wired at boot.
- [ ] `ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true })` global.
- [ ] Global guard denies by default; `@Public()` is the explicit exception.
- [ ] `@nestjs/throttler` configured, tighter limits on sensitive routes.
- [ ] `helmet()` and `enableCors` with an explicit origin allowlist.
- [ ] Global exception filter hides internals from responses.
- [ ] AWS SDK v3 clients built with no explicit `credentials`.
- [ ] Swagger mounted only outside production.
