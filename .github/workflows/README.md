# `golden-ci.yml` — the shared pipeline

Group-owned reusable workflow (`on: workflow_call`). Every teammate's
individual repo calls this by pinned SHA instead of writing its own gate
logic — one pipeline definition, one place to fix a gate, every rehost gets
the fix identically.

## Why a PR that only touches this file shows no CI checks

`golden-ci.yml` is `workflow_call`-only — it has no trigger of its own, so it
never runs against its own PRs, only when a caller repo invokes it. That's
intentional, not a gap: `lint-workflows.yml` (a separate, small workflow in
this same directory) runs `actionlint` against every workflow file on any PR
touching `.github/workflows/**`, catching structural mistakes — a bad action
reference, invalid expression syntax, malformed YAML — before merge, without
needing a real app or a `LOCALSTACK_AUTH_TOKEN` in this repo. It is
deliberately not a full exercise of the gates themselves; that only happens
when a caller repo (an individual rehost) actually invokes `golden-ci.yml`.

## What it does

Gate order is frozen by
[`docs/MODULE-CONTRACTS.md`](../../docs/MODULE-CONTRACTS.md):

```
gitleaks -> trivy config -> zizmor -> docker build -> trivy image -> tag AMI -> tflocal apply
```

| Job | Gate | Fails the build on |
|---|---|---|
| `gitleaks` | secrets in repo + full git history | any finding |
| `trivy-config` | Terraform + Dockerfile misconfig | CRITICAL/HIGH |
| `zizmor` | this repo's own GitHub Actions workflows | medium severity+ (pedantic persona) |
| `docker-build` | builds the app image, computes the AMI tag | build failure |
| `trivy-image` | the built image itself | CRITICAL/HIGH |
| `tflocal-apply` | stands the stack up on LocalStack (only when `run_apply: true`) | any `tflocal` step failing, or a non-empty plan after apply |

## Calling it from an individual repo

```yaml
jobs:
  ci:
    uses: <org>/regional-health-platform/.github/workflows/golden-ci.yml@<sha>
    with:
      app_dir: api
      image_name: regional-health-api
      terraform_dir: terraform
      run_apply: ${{ github.ref == 'refs/heads/main' }}
    secrets:
      localstack_auth_token: ${{ secrets.LOCALSTACK_AUTH_TOKEN }}
```

Pin `@<sha>`, never a branch — same discipline this workflow enforces on its
own actions. `run_apply` is `false` by default so a PR from a fork (no
`LOCALSTACK_AUTH_TOKEN` in scope) still runs all five scan/build gates; only a
push to `main` (or wherever the caller wires `run_apply: true`) actually
stands up infrastructure.

## Why zizmor runs as a raw CLI step, not `zizmorcore/zizmor-action`

Checked directly against the action's README before using it: with its
default (`advanced-security: true`), **the action does not fail the build on
findings** — it only uploads to GitHub Advanced Security, which isn't
guaranteed enabled on every member's repo. `advanced-security: false` has the
same non-blocking behavior; findings just print. Either way, that silently
violates the assignment's own rule — *"a scanner that runs but never fails the
build is theatre."*

The `zizmor` CLI itself does exit non-zero on a finding (11-14 depending on
the highest severity hit), so the gate installs and runs it directly:

```bash
pip install "zizmor==1.29.0"
zizmor --persona=pedantic --min-severity=medium .
```

Pinned to an exact version rather than `latest`, for the same reason every
action here is SHA-pinned — a gate whose tool version can drift out from under
it isn't reproducible.

## Supply-chain hardening (C5 "guard the guards")

- **Integrity.** Every action is pinned to a full commit SHA, verified
  directly against each repo's GitHub API (`git/refs/tags/<tag>`) rather than
  trusted from a release page summary or search result — two of the SHAs used
  in early drafts of this file were wrong on first lookup and only caught by
  cross-checking the API directly. Version bumps land as a reviewed PR that
  changes the pinned SHA, never an `@latest` or moving tag.
- **Blast radius.** Every scan job (`gitleaks`, `trivy-config`, `zizmor`,
  `trivy-image`) runs `permissions: contents: read` with no `secrets:`
  block — a compromised scanner step has nothing to exfiltrate. The one real
  secret in this pipeline, `localstack_auth_token`, is scoped to only the
  `tflocal-apply` job, and only reaches it when the caller explicitly passes
  it and `run_apply: true`.
- **Detection.** `step-security/harden-runner` runs first in every job with
  `egress-policy: audit`, so unexpected outbound network calls from any step —
  including a compromised action already sitting at its pinned SHA — are
  visible in the job's summary. Pinning stops a swapped tag; it does not stop
  a malicious commit already at the SHA you pinned, a compromised maintainer,
  or a zero-day in the tool's own logic. Detection is the layer for those.

## What each gate does **NOT** catch (per C5)

- **gitleaks** — pattern/entropy-based. A secret that doesn't look like a
  secret (no recognizable format, low entropy, split across multiple commits
  or files) can pass clean. It also only sees what's committed; a secret that
  lived only in a GitHub Actions log or an environment variable never
  committed to git is invisible to it.
- **trivy (config)** — checks known misconfiguration patterns against its
  policy set; a logically insecure design that doesn't match a known
  bad-pattern signature (e.g. an overly-permissive IAM policy shaped in an
  unusual way) can still pass.
- **trivy (image)** — only flags vulnerabilities already in trivy's CVE
  database as of the scan. A genuinely new (zero-day) vulnerability, or a
  vulnerable code path that isn't captured by the installed package's known
  CVEs, won't be caught. `ignore-unfixed` isn't set here, so a CVE with no
  available fix still fails the build — intentional for a lab, worth
  reconsidering for a real on-call rotation where that would page for
  something nobody can yet act on.
- **zizmor** — analyzes workflow *definitions* (permissions, injection
  vectors, unpinned actions). It cannot see what a third-party action
  actually does at its pinned SHA — pinning plus zizmor stops a swapped tag,
  not a malicious action that was already compromised at the commit you
  pinned to.

## Deliberately-red PR (C5 evidence)

Not yet produced — tracked as a follow-up once this workflow is merged and at
least one caller repo exercises it. Plan: commit a fake AWS-shaped credential
on a throwaway branch to trigger `gitleaks`, link the resulting red PR and the
fix commit in `evidence/05-gates/README.md` in the individual repo (per-person
evidence, not this shared one — each teammate produces their own gate-catch
proof against their own service).

## Testing

- YAML validated (`python3 -c "import yaml; yaml.safe_load(...)"`) — clean.
- Every `uses:` SHA verified against the source repo's GitHub API, not just
  copied from a release page or search result.
- **Not yet runtime-verified.** This workflow hasn't executed on GitHub
  Actions yet — needs a real PR (this one) to confirm: gitleaks correctly
  scans full history via `fetch-depth: 0`, the zizmor CLI step's exit code
  actually fails the job on a real finding, and the `docker save` /
  `download-artifact` handoff between `docker-build` and `trivy-image`
  round-trips the image correctly. Tracking on first PR run.
