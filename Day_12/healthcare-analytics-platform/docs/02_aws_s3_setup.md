# 2. AWS S3 Setup (beginner, step-by-step)

> Goal: get the three CSVs into an S3 folder and create an IAM role Snowflake can assume.

## A. Create an AWS account
1. Go to https://aws.amazon.com → **Create an AWS Account**.
2. Enter email, account name, verify, add a payment method (S3 for a few MB is effectively free).
3. Sign in to the **AWS Management Console**.

## B. Create the S3 bucket
1. Console search bar → **S3** → **Create bucket**.
2. **Bucket name**: globally unique, lowercase, e.g. `hc-analytics-<yourname>-2026`.
   - Naming rules: 3–63 chars, lowercase letters/numbers/hyphens, no spaces.
3. **Region**: pick the one nearest you (remember it — must match Snowflake later).
4. **Block Public Access**: leave **ON** (we use a private IAM role, never public).
5. Create.

## C. Create the folder & upload
1. Open the bucket → **Create folder** → name it `healthcare`.
2. Open `healthcare/` → **Upload** → add the three CSVs → **Upload**.
3. *(Screenshot moment: you should see 3 objects, ~2.5 MB each.)*

## D. IAM role that Snowflake can assume
1. Console → **IAM** → **Policies** → **Create policy** → JSON tab, paste (replace bucket):
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {"Effect":"Allow","Action":["s3:GetObject","s3:GetObjectVersion"],
     "Resource":"arn:aws:s3:::<YOUR_BUCKET>/healthcare/*"},
    {"Effect":"Allow","Action":["s3:ListBucket","s3:GetBucketLocation"],
     "Resource":"arn:aws:s3:::<YOUR_BUCKET>",
     "Condition":{"StringLike":{"s3:prefix":["healthcare/*"]}}}
  ]
}
```
   Name it `snowflake-hc-policy`.
2. **IAM → Roles → Create role → AWS account → This account** (temporary; fix trust later).
   Attach `snowflake-hc-policy`. Name it `snowflake-hc-role`. Copy its **Role ARN**.
3. You'll finish the trust relationship in Snowflake step 02 (storage integration),
   which hands you an IAM user ARN + external ID to paste back into this role's
   **Trust relationships**:
```json
{
  "Version":"2012-10-17",
  "Statement":[{"Effect":"Allow",
    "Principal":{"AWS":"<STORAGE_AWS_IAM_USER_ARN from Snowflake>"},
    "Action":"sts:AssumeRole",
    "Condition":{"StringEquals":{"sts:ExternalId":"<STORAGE_AWS_EXTERNAL_ID from Snowflake>"}}}]
}
```

## E. Security best practices
- Keep **Block Public Access ON**; never make the bucket public.
- Grant only `GetObject`/`ListBucket` on the single prefix (least privilege).
- Enable **default encryption (SSE-S3)** on the bucket.
- Never put AWS keys in SQL — the storage integration uses role assumption.

## F. Validate
- In Snowflake after step 03: `LIST @HC_DB.RAW.HC_S3_STAGE;` should list 3 files.
