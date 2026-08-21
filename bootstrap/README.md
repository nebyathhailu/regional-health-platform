# `bootstrap` — Terraform remote state store

Creates the S3 bucket + DynamoDB lock table every individual repo's root
module points its `backend "s3" {}` block at. Run **once**, by hand, against
LocalStack — not something CI applies on every run, and not a module other
Terraform sources (bootstrapping the state store can't itself depend on the
state store existing).

## Running it

```bash
cd bootstrap
tflocal init
TF_CMD=tofu tflocal apply
```

(`TF_CMD=tofu` if your shell doesn't already export it — see the group
README's OpenTofu convention.)

This uses **local** state for itself (no `backend` block) — that's
deliberate, not an oversight.

## Using the output in your own repo

Each individual repo's root module (`terraform/versions.tf`) has an empty
`backend "s3" {}` block, populated at `init` time via `-backend-config` so
every person's state lands under a distinct `key` in the same shared bucket:

```bash
tflocal init \
  -backend-config="bucket=devops-g1-ls-tfstate" \
  -backend-config="key=<your-repo-name>/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="dynamodb_table=devops-g1-ls-tflock"
```

Swap `<your-repo-name>` for something that uniquely identifies your
individual rehost (e.g. `db-capacity-engineering-lab`) so nobody's state
overwrites anyone else's in the shared bucket.

## Why this exists as a separate root, not a module

- It's the one piece of this lab that's genuinely run once, not on every
  `tflocal apply` — CI's `tflocal-apply` job in `golden-ci.yml` never touches
  this directory.
- It can't have a remote backend itself (chicken-and-egg: the thing that
  creates the state store can't depend on the state store existing).

## What it satisfies

`ASSIGNMENT.md`, C1: *"Remote state on S3 + DynamoDB lock (the bootstrap
script is provided — you don't write it)."* This is that script — group-owned
per the brief's own table ("Bootstrap scripts and repo conventions" is listed
under what the group builds once, reused by everyone).
