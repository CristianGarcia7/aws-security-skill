// env.validation.ts
//
// Fail-fast environment schema. Wire into @nestjs/config's `validate`
// option (see references/nestjs.md) so the app refuses to boot on a
// missing or malformed variable, and refuses to boot in production if it
// finds static AWS credentials that should never be present — the app
// should be getting its AWS access from the attached role, not from env
// vars (see references/secrets-and-env.md).

import { z } from "zod";

const envSchema = z
  .object({
    NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
    PORT: z.coerce.number().int().positive().default(3000),

    AWS_REGION: z.string().min(1, "AWS_REGION is required"),

    // Non-AWS secrets only belong here, and only provisionally — prefer a
    // secrets manager. These are still validated so a missing value fails
    // at boot instead of at the first call site.
    DATABASE_URL: z.string().url(),
    JWT_SECRET: z.string().min(32, "JWT_SECRET must be at least 32 characters"),

    // These should never be set on AWS compute. Declared here only so the
    // refinement below can detect and reject their presence explicitly.
    AWS_ACCESS_KEY_ID: z.string().optional(),
    AWS_SECRET_ACCESS_KEY: z.string().optional(),
  })
  .superRefine((env, ctx) => {
    if (env.NODE_ENV === "production" && (env.AWS_ACCESS_KEY_ID || env.AWS_SECRET_ACCESS_KEY)) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message:
          "AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY must not be set in production. " +
          "Use the attached instance/task/Lambda role instead (see references/secrets-and-env.md).",
        path: ["AWS_ACCESS_KEY_ID"],
      });
    }
  });

export type Env = z.infer<typeof envSchema>;

/**
 * Pass as the `validate` option to @nestjs/config's ConfigModule.forRoot().
 * Throws synchronously on the first invalid environment, which stops the
 * app from starting rather than failing later at an arbitrary call site.
 */
export function validateEnv(config: Record<string, unknown>): Env {
  const result = envSchema.safeParse(config);
  if (!result.success) {
    const issues = result.error.issues
      .map((issue) => `  - ${issue.path.join(".")}: ${issue.message}`)
      .join("\n");
    throw new Error(`Invalid environment configuration:\n${issues}`);
  }
  return result.data;
}
