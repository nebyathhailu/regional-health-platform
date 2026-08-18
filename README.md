# Regional Health — Rehost Platform (Assignment 2)

Shared **group platform** for rehosting our Regional Health services onto AWS
(via LocalStack). This repo holds the reusable Terraform modules and the golden
CI pipeline. **Each member's service rehost lives in their own individual repo**
and consumes these modules by git source.

> Built against [LocalStack](https://www.localstack.cloud/localstack-for-aws).
> The Terraform is real AWS Terraform; only the endpoints point at LocalStack.

## Layout

```
terraform/modules/
  data/      RDS MySQL + Secrets Manager        (owner: Rigbe)
  service/   EC2 + nginx + user-data + health   (owner: Nebyat)
.github/workflows/
  golden-ci.yml   reusable gitleaks + trivy + zizmor pipeline (owner: Meron)
docs/
  MODULE-CONTRACTS.md   the input/output contract each module must honour
```

## How an individual repo consumes the platform

Source the modules by pinned git ref (never a moving branch):

```hcl
module "data" {
  source = "git::https://github.com/<group>/regional-health-platform.git//terraform/modules/data?ref=<sha>"
  # ...
}

module "service" {
  source = "git::https://github.com/<group>/regional-health-platform.git//terraform/modules/service?ref=<sha>"
  # ...
}
```

The reusable CI workflow is called from each repo with `uses:`:

```yaml
jobs:
  ci:
    uses: <group>/regional-health-platform/.github/workflows/golden-ci.yml@<sha>
```

## Ownership & review (graded from git history)

Every member is **sole author of at least one module PR** and **approving
reviewer on at least two others**. See [CONTRIBUTIONS.md](CONTRIBUTIONS.md).

| Module | Owner | Status |
|---|---|---|
| `terraform/modules/service` | Nebyat | PR open |
| `terraform/modules/data` | Rigbe | PR open |
| `.github/workflows/golden-ci.yml` | Meron | PR open |

## Conventions

- **OpenTofu** (`tofu`), Terraform `>= 1.10`, AWS provider `~> 5.60`.
- `tofu fmt` + `tofu validate` clean before every PR.
- Remote state on S3 + DynamoDB lock (bootstrap is provided by the assignment —
  we don't hand-write it).
- Pin every GitHub Action to a full commit SHA and every base image by digest.
