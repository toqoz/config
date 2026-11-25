---
name: vgw-handoff
description: Transfer files and context between agents or machines through object storage. Use when the user asks to hand off files to another agent or machine using VersityGW, or names vgw-handoff.
---

# vgw-handoff

Transfer files and context between agents or machines through object storage.

This installation writes as `@VGW_HOST@`. Use `s3://handoff/@VGW_HOST@/<unique-task>/<filename>`.
The host prefix is an IAM boundary; never choose another host's prefix for writes.
Read access is available across both buckets.

Before any storage operation, check that `$HOME/.config/versitygw/credentials`
exists and is readable. If it is missing or unreadable, stop this skill and ask
the user to place their host-specific AWS credentials there, with profile
`@VGW_HOST@` and permissions `0600`. Do not provision keys, print secrets,
create placeholder credentials, or fall back to another identity.

The host configuration supplies `$HOME/.config/versitygw/config` with profile
`@VGW_HOST@`, region `us-east-1`, and endpoint `http://ras01:7070`.
Set the config and credentials paths only for each AWS command, as shown below.
Do not export global `AWS_*` settings or modify the user's normal AWS config.
Use the same command-local paths and profile for uploads, verification, and reads.

1. Identify the requested files and choose a unique task directory. Upload only
   the requested artifacts; exclude credentials and unrelated workspace files.
2. Upload each file, preserving its intended filename:

   ```sh
   AWS_CONFIG_FILE="$HOME/.config/versitygw/config" \
   AWS_SHARED_CREDENTIALS_FILE="$HOME/.config/versitygw/credentials" \
   aws --profile @VGW_HOST@ s3 cp '<local-file>' 's3://handoff/@VGW_HOST@/<unique-task>/<filename>'
   ```

3. Verify the object with `s3api head-object` using the same profile, region,
   endpoint, bucket `handoff`, and exact key. Report failures as failures.
4. Return the exact S3 URI and a download command using the recipient's own
   AWS profile with the same endpoint and region. Include a concise description
   of the contents, relevant revision, and the next action. For a handoff request
   that includes context, upload a small manifest alongside the requested files.
   Read the source object without moving or deleting it; do not write into the
   recipient's prefix or publish a web URL for the handoff bucket.
