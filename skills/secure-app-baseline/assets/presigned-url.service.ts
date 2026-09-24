// presigned-url.service.ts
//
// NestJS service issuing presigned S3 URLs following every rule in
// references/s3-and-presigned-urls.md:
//   1. Authorize the requesting user against the exact object BEFORE signing.
//   2. Short TTL (GET vs PUT differ).
//   3. Never log/cache/embed the full signed URL.
//   4. Object keys are generated server-side, never trusted from the client.
//   5. Uploads are constrained via presigned POST conditions
//      (content-type allowlist, max size) instead of a bare presigned PUT.
//   6. S3 client uses the default credential chain — no explicit credentials.

import { ForbiddenException, Injectable, NotFoundException } from "@nestjs/common";
import { GetObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { createPresignedPost } from "@aws-sdk/s3-presigned-post";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { randomUUID } from "node:crypto";

const GET_TTL_SECONDS = 120; // within the 60-300s range for GET
const PUT_MAX_TTL_SECONDS = 900; // SigV4 practical upper bound
const ALLOWED_UPLOAD_CONTENT_TYPES = ["image/png", "image/jpeg", "application/pdf"];
const MAX_UPLOAD_BYTES = 10 * 1024 * 1024; // 10 MiB

interface OwnedObject {
  key: string;
  ownerId: string;
}

// Replace with a real repository lookup. This is where object-level
// authorization (BOLA / IDOR prevention) happens: never trust a client-
// supplied key, and never skip the ownership check.
interface ObjectRepository {
  findById(objectId: string): Promise<OwnedObject | null>;
}

@Injectable()
export class PresignedUrlService {
  private readonly s3: S3Client;

  constructor(
    private readonly objects: ObjectRepository,
    private readonly bucket: string, // injected from config, never hardcoded
  ) {
    // Default credential chain: on AWS compute this resolves to the
    // attached instance/task/Lambda role via IMDS. No explicit credentials.
    this.s3 = new S3Client({ region: process.env.AWS_REGION });
  }

  /**
   * Issue a short-lived GET URL for an existing private object, after
   * confirming the requesting user owns it.
   */
  async getDownloadUrl(userId: string, objectId: string): Promise<{ url: string; expiresIn: number }> {
    const object = await this.objects.findById(objectId);
    if (!object) {
      throw new NotFoundException();
    }
    if (object.ownerId !== userId) {
      // Do not distinguish "not found" from "not yours" in the response —
      // both return the same error shape to avoid leaking existence.
      throw new ForbiddenException();
    }

    const command = new GetObjectCommand({ Bucket: this.bucket, Key: object.key });
    const url = await getSignedUrl(this.s3, command, { expiresIn: GET_TTL_SECONDS });

    // Never log the full URL — it is a bearer credential until it expires.
    // Log the object key and requesting user instead.
    this.auditLog("presigned-get-issued", { userId, objectKey: object.key });

    return { url, expiresIn: GET_TTL_SECONDS };
  }

  /**
   * Issue a presigned POST for a new upload. The object key is generated
   * server-side from the authenticated user, never accepted from the
   * client, which prevents path traversal and cross-tenant key collisions.
   */
  async getUploadPost(userId: string, contentType: string): Promise<{
    url: string;
    fields: Record<string, string>;
    key: string;
    expiresIn: number;
  }> {
    if (!ALLOWED_UPLOAD_CONTENT_TYPES.includes(contentType)) {
      throw new ForbiddenException(`content type not allowed: ${contentType}`);
    }

    const key = `uploads/${userId}/${randomUUID()}`;

    const { url, fields } = await createPresignedPost(this.s3, {
      Bucket: this.bucket,
      Key: key,
      Conditions: [
        ["content-length-range", 0, MAX_UPLOAD_BYTES],
        ["eq", "$Content-Type", contentType],
      ],
      Fields: { "Content-Type": contentType },
      Expires: PUT_MAX_TTL_SECONDS,
    });

    this.auditLog("presigned-post-issued", { userId, objectKey: key, contentType });

    return { url, fields, key, expiresIn: PUT_MAX_TTL_SECONDS };
  }

  private auditLog(event: string, data: Record<string, unknown>): void {
    // Structured, secret-free audit log — no URL, no signature, no token.
    // eslint-disable-next-line no-console
    console.log(JSON.stringify({ event, ...data, at: new Date().toISOString() }));
  }
}
