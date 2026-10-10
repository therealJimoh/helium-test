# helium test

A small REST API (`helium-test`) onboarded to the platform end to end: container image, CI pipeline, Kubernetes manifests and the AWS infrastructure behind them, all managed with Terraform.

```
.
├── app/                    Go REST API (stdlib only) + unit tests
├── docker/                 Dockerfile + Dockerfile.dockerignore
├── .github/workflows/      ci.yml (lint, test, validate, build, scan, push)
├── .github/dependabot.yml  Weekly updates for actions, base images, Go, Terraform
├── k8s/                    Kustomize base: Deployment, Service, Ingress, NetworkPolicy, ConfigMap, Secret, PDB…
├── terraform/
│   ├── modules/            ecr, ci-iam-role, state-bucket (reusable)
│   ├── bootstrap/          Creates the remote-state bucket (local state, then migrated)
│   └── environments/dev/   ECR repo + CI role, S3 remote backend
└── Makefile                Local shortcuts (test, build, run, scan, k8s-render, tf-validate)
```

## The application

| Endpoint | Purpose |
|---|---|
| `GET /healthz` | Liveness: the process is up |
| `GET /readyz` | Readiness: returns 503 before startup and after SIGTERM |
| `GET /api/v1/hello` | Returns `APP_GREETING` (from the ConfigMap) |
| `GET /api/v1/items` | Lists items (in memory) |
| `POST /api/v1/items` | Creates an item; needs `Authorization: Bearer $API_TOKEN` (from the Secret) |

It logs structured JSON to stdout, sets server timeouts, and shuts down gracefully on SIGTERM (it fails readiness first, then drains in-flight requests).

```bash
make test          # go test -race
make run           # build image, run on :8080 with a read-only root fs
curl localhost:8080/api/v1/hello
```

## 1. Containerisation

[docker/Dockerfile](docker/Dockerfile). The build context is the repo root: `docker build -f docker/Dockerfile .`

- **Multi-stage build.** `golang:1.24-alpine` compiles a static, stripped binary (`CGO_ENABLED=0`, `-trimpath`, `-s -w`). The version is injected through `-ldflags`.
- **Minimal runtime.** `gcr.io/distroless/static-debian12:nonroot` has no shell or package manager, and the final image is about 8 MB. This gives a very small CVE surface for Trivy to report on.
- **Non-root.** The image runs as UID/GID `65532`. Kubernetes enforces this again with `runAsNonRoot`, a read-only root fs and all capabilities dropped.
- **Build cache.** A BuildKit cache mount for Go modules, and a separate dependency layer so changing the source doesn't re-download modules.
- **`.dockerignore`.** [docker/Dockerfile.dockerignore](docker/Dockerfile.dockerignore) is an **allow-list** (`*` and then `!app/`). New files such as `.env`, `*.tfstate` or `.git` are excluded by default rather than leaking into the build context. BuildKit picks it up automatically because it sits next to the Dockerfile (`<Dockerfile>.dockerignore`), so it works even though the Dockerfile isn't at the context root.

## 2. CI pipeline

[.github/workflows/ci.yml](.github/workflows/ci.yml)

```
lint-test ─────────┐
                   ├──► build-scan-push ──(main only)──► ECR
validate-infra ────┘
```

| Job | What it does |
|---|---|
| `lint-test` | `gofmt`, `go vet`, `golangci-lint`, `go test -race` |
| `validate-infra` | `hadolint` on the Dockerfile, `kubeconform` on the rendered kustomize output, `terraform fmt` + `validate` for every root |
| `build-scan-push` | Buildx build (GHA layer cache), then two Trivy passes: a full SARIF report uploaded to the GitHub Security tab, and a **gate that fails the job on fixable HIGH/CRITICAL findings**. Only after the gate passes, and only on `main`, does it assume the AWS role over OIDC and push. |

**Tagging.** Images are tagged `sha-<7-char commit>`. The ECR repo uses **immutable tags**, so a tag always points at the commit it names, and there is deliberately no `latest`. Deployments refer to the exact sha tag.

### How to trigger it

| Event | Result |
|---|---|
| Open or update a PR targeting `main` | Lint, test, validate, build, scan. **No push**, and no AWS credentials are ever issued to PR runs (this includes forks). |
| Merge or push to `main` | Everything above, plus a push to ECR |
| Actions tab → `ci` → **Run workflow** | Manual run (`workflow_dispatch`). It pushes only when run on `main`. |

Superseded PR runs are cancelled automatically. Runs on `main` are never cancelled mid-push.

### One-time setup (no secrets stored in GitHub)

CI authenticates to AWS with **GitHub OIDC**, so no access keys are stored anywhere. After `terraform apply` in `environments/dev`, set these **repository variables** (Settings → Secrets and variables → Actions → *Variables*). They are identifiers, not secrets:

| Variable | Value from |
|---|---|
| `AWS_ROLE_ARN` | `terraform output ci_role_arn` |
| `AWS_REGION` | e.g. `eu-west-2` |
| `ECR_REPOSITORY` | `terraform output ecr_repository_name` (`helium-test`) |

To use GCR/Artifact Registry instead, the swap is confined to the two auth steps (`google-github-actions/auth` with Workload Identity Federation) and the registry hostname.

## 3. Kubernetes

[k8s/](k8s/) is a Kustomize base. Everything is namespaced to `helium-test`.

| Manifest | Notes |
|---|---|
| `namespace.yaml` | Enforces the **restricted** Pod Security Standard |
| `serviceaccount.yaml` | Dedicated SA with `automountServiceAccountToken: false` (the app never calls the API server) |
| `configmap.yaml` / `secret.yaml` | Injected as env vars. **The Secret is a placeholder**, see [Secrets](#secrets). |
| `deployment.yaml` | 2 replicas, `maxUnavailable: 0`, requests and limits, startup/liveness/readiness probes, `preStop` sleep, non-root + read-only fs + drop ALL + seccomp `RuntimeDefault`, spread across nodes |
| `service.yaml` | ClusterIP `80 → http(8080)` |
| `ingress.yaml` | `ingressClassName: nginx`, TLS through cert-manager, exposes only `/api` (health endpoints stay internal) |
| `networkpolicy.yaml` | **Default-deny all** in the namespace, then allow ingress to `:8080` only from ingress-nginx controller pods, and egress only to kube-dns on 53/UDP+TCP. The service has no upstream dependencies, so nothing else is opened. |
| `pdb.yaml` | `minAvailable: 1`, so node drains can't take both replicas down |

**Probe design.** Liveness (`/healthz`) only says the process is alive, so a slow dependency can't trigger a restart loop. Readiness (`/readyz`) controls traffic and goes false on SIGTERM. The `preStop` sleep gives kube-proxy and the ingress controller time to remove the endpoint before the process starts draining.

**Resources.** Requests of `50m`/`32Mi` and limits of `250m`/`64Mi` suit a tiny Go binary. These are starting points to be tuned from real usage metrics (or VPA recommendations). The CPU limit is there because the brief asks for one. Many teams drop CPU limits to avoid CFS throttling and keep only memory limits, and I'd raise that as a conversation.

### How to apply

Prerequisites: a cluster on **k8s ≥ 1.30** (for `preStop.sleep`), a CNI that enforces NetworkPolicy (Calico, Cilium, VPC CNI with network policy enabled…), ingress-nginx in the `ingress-nginx` namespace, cert-manager with a `letsencrypt` ClusterIssuer, and nodes that can pull from the ECR repo.

```bash
# 1. Point the base at the image CI pushed (the sha tag from the run summary)
cd k8s
kustomize edit set image helium-test=<account>.dkr.ecr.<region>.amazonaws.com/helium-test:sha-abc1234

# 2. Provide the real secret out-of-band (don't apply the placeholder to a real cluster)
kubectl create namespace helium-test --dry-run=client -o yaml | kubectl apply -f -
kubectl -n helium-test create secret generic helium-test-secrets \
  --from-literal=API_TOKEN="$(openssl rand -hex 32)" --dry-run=client -o yaml | kubectl apply -f -

# 3. Preview, then apply
kubectl diff -k .
kubectl apply -k .

# 4. Verify
kubectl -n helium-test rollout status deploy/helium-test
kubectl -n helium-test port-forward svc/helium-test 8080:80 &
curl localhost:8080/api/v1/hello
```

If you skip step 2, the dummy `dummy-api-token` Secret is applied and the API runs with a known token. That's fine for a throwaway cluster, but not acceptable anywhere real.

## 4. Terraform

```
terraform/
├── modules/
│   ├── ecr/            repo, immutable tags, scan-on-push, encryption, lifecycle policy
│   ├── ci-iam-role/    GitHub OIDC provider (optional) + least-privilege push role
│   └── state-bucket/   versioned, KMS-encrypted, public-blocked, TLS-only S3 bucket
├── bootstrap/          uses state-bucket; starts on local state
└── environments/dev/   uses ecr + ci-iam-role; S3 backend
```

Each module has `variables.tf` (typed and described, with validation where it helps), `outputs.tf` and `versions.tf`. The roots stay thin: they only wire modules together. Adding `environments/prod` means copying a directory and changing the tfvars/backend key, not changing any modules.

**ECR lifecycle policy.** Untagged images expire after 7 days, and only the 30 most recent tagged images are kept (both configurable).

**CI role (least privilege).**
- *Trust.* Only GitHub's OIDC provider, audience `sts.amazonaws.com`, and an **exact** `sub` of `repo:<owner>/<repo>:ref:refs/heads/main`. PRs, other branches, forks and other repos can't assume the role.
- *Permissions.* `ecr:GetAuthorizationToken` (it can't be resource-scoped, an AWS limitation), plus the push/pull layer actions **scoped to this repository ARN only**. It has no `ecr:*`, no create/delete, and no access to other repos.
- Sessions last at most 1 hour.
- The OIDC provider is an account-wide singleton, so the module can create it or accept an existing ARN (`create_oidc_provider = false`).

**Remote state.** S3 with **native lockfile locking** (`use_lockfile = true`, Terraform ≥ 1.10), so no DynamoDB table is needed. The bucket is versioned (old state versions are kept for 90 days for recovery), SSE-KMS encrypted, has all public access blocked, uses `BucketOwnerEnforced`, denies non-TLS requests, and is set to `prevent_destroy`.

### How to run it

```bash
# 1. Bootstrap the state bucket (once per account)
cd terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars   # set a globally unique bucket name
terraform init && terraform apply
# Optional: add a backend "s3" block here, then `terraform init -migrate-state`
# so the bucket's own state also lives in the bucket.

# 2. Service infrastructure
cd ../environments/dev
cp backend.hcl.example backend.hcl             # bucket = output of step 1
cp terraform.tfvars.example terraform.tfvars   # github_repository = "owner/repo"
terraform init -backend-config=backend.hcl
terraform plan -out=tfplan && terraform apply tfplan
terraform output                               # → GitHub repo variables (see CI setup)
```

The backend uses **partial configuration**, so bucket names and account-specific values never get committed. `*.tfvars` and `backend.hcl` are git-ignored, and only the `.example` files are tracked. Provider lock files are committed so every run uses the same provider build.

### Migration question: importing a manually created resource with no downtime

Importing only writes to Terraform **state**. It never touches the real resource. The risk is the *first apply afterwards*, if the code doesn't match reality (for example, a ForceNew attribute that differs causes a destroy/create). So the approach is: import, make the plan a no-op, and only then hand the resource over to Terraform.

Example: a hand-made ECR repo called `legacy-api`.

1. **Freeze and back up.** Announce a change freeze on the resource. Make sure the state bucket is versioned (it is), so a bad state write can be rolled back.
2. **Declare the import in code** (Terraform ≥ 1.5). This is reviewable in a PR, unlike the imperative `terraform import` CLI:
   ```hcl
   import {
     to = module.legacy_ecr.aws_ecr_repository.this
     id = "legacy-api"
   }
   ```
   For a resource with no module yet, `terraform plan -generate-config-out=generated.tf` drafts the HCL from the live resource.
3. **Iterate on the code until `terraform plan` shows `1 to import, 0 to add, 0 to change, 0 to destroy`.** Pay particular attention to anything marked `forces replacement`. That is exactly the downtime risk, and it must be fixed in code (match the real value), never accepted. Remember the child resources that usually hide behind a manual setup (lifecycle policy, repo policy and so on) and import those too.
4. **Mitigate anything that can't be matched.** Use `lifecycle { prevent_destroy = true }` as a safety net during the migration, and `ignore_changes` for attributes that something else owns, or that you'll fix in a separate, planned change.
5. **Apply in CI** with the import block, through the normal PR plan → review → apply flow. Then remove the `import` block in a follow-up PR (it's a no-op once imported, but leaving it in is noise).
6. **Moving between modules or stacks later** uses `moved {}` blocks, or `removed { lifecycle { destroy = false } }` followed by an import in the new stack, again with no change to the real resource.

## Secrets

Nothing sensitive is committed. Here is where each secret lives:

| Secret | Approach here | Intended production approach |
|---|---|---|
| AWS credentials for CI | **None stored**: OIDC → short-lived STS creds | Same |
| App `API_TOKEN` | Placeholder `k8s/secret.yaml`, real value created with `kubectl create secret` | Store it in **AWS Secrets Manager**, sync it with **External Secrets Operator** (an `ExternalSecret` replaces `secret.yaml`), with ESO using IRSA/Pod Identity. Sealed Secrets/SOPS are the alternative if the secret must live in Git. |
| Terraform inputs | Git-ignored `*.tfvars` / `backend.hcl` | Same, plus `sensitive = true` variables sourced from the CI secret store if any are added |
| Terraform state | Encrypted, private, TLS-only bucket | Same, plus a CMK with a key policy limited to the Terraform role(s) |

etcd encryption at rest, plus RBAC that limits `get secrets` in the namespace, are assumed to be cluster-level controls.

## Assumptions, trade-offs & shortcuts

**Assumptions**
- AWS (ECR, IAM, S3) in `eu-west-2`, with the AWS account ID left empty. The kustomization uses a dummy image (`helium-test/dummy:0.0.0`) until a real ECR tag is set. The repo is `github.com/helium-test/helium-test`.
- An existing cluster with the add-ons listed under [How to apply](#how-to-apply). Provisioning the cluster (EKS) was out of scope.
- Kubelet probes aren't blocked by NetworkPolicy. This is true for mainstream CNIs, because node-originated traffic is allowed.

**Trade-offs**
- **Kustomize over Helm.** One service and one environment don't need templating. Kustomize keeps the manifests plain YAML and gives overlays (`overlays/dev`, `overlays/prod`) once a second environment arrives.
- **Plain ConfigMap rather than `configMapGenerator`.** It's more readable for review, but changing the ConfigMap doesn't roll the pods automatically. A generator (hash-suffixed name) or Reloader would fix that.
- **Two Trivy passes.** The full report goes to the Security tab, and the gate only blocks on *fixable* HIGH/CRITICAL. Blocking on unfixable CVEs trains people to ignore the scanner.
- **Scan before push.** Nothing reaches the registry without passing the gate, and ECR scan-on-push adds a second, continuous check (new CVEs found after push).
- **One CI role** for push only. Deployment isn't done by CI (see GitOps below), so CI never holds cluster credentials.
- **ingress-nginx.** I chose it as the most common controller. Its upstream project has been retired, so for a new platform I'd target the **Gateway API** (an `HTTPRoute` instead of an `Ingress`). The NetworkPolicy selector would change accordingly.

**Shortcuts taken (not production-ready)**
- **GitHub Actions are pinned to version tags, not commit SHAs.** In production I'd pin to full SHAs (Dependabot, which is configured, keeps them updated). This matters especially for third-party actions such as Trivy, given past supply-chain compromises of popular actions.
- The distroless base image isn't pinned by digest. Dependabot (docker ecosystem) is configured to manage that once a digest is pinned.
- In-memory storage, so data doesn't survive across replicas or restarts. That's intentional, because the app isn't the focus.
- No image signing, SBOM or provenance. Next steps would be `cosign sign` with keyless OIDC, `--sbom`/`--provenance` on buildx, and admission verification with Kyverno or Sigstore policy-controller.
- No HPA, no `ServiceMonitor`, no dev/prod overlays. A single `dev` Terraform environment.
- The bootstrap stack starts on local state, and migrating it into the bucket is a manual step.
- Some checks weren't run in this environment: the kubeconform, hadolint and golangci-lint steps, and an actual `terraform apply` against AWS. Go tests, `docker build/run`, `kubectl kustomize`, and `terraform fmt`/`validate` were run locally.

## What I'd do next (in-person discussion topics)

- **GitOps.** Argo CD or Flux watches an env repo or overlay. CI's last step would open a PR (or let Argo CD Image Updater) bump the image tag, so deploys are auditable, reviewable and reverted with `git revert`. CI keeps zero cluster access.
- **Progressive delivery.** Argo Rollouts canary, gated on error-rate and latency SLOs.
- **Observability.** A `/metrics` endpoint (Prometheus client, RED metrics), a `ServiceMonitor` plus a NetworkPolicy rule allowing the Prometheus namespace, OpenTelemetry traces, JSON logs shipped by the node agent (already structured), and SLO-based alerts rather than CPU alerts.
- **Policy as code.** Kyverno/OPA in-cluster, plus `checkov`/`tfsec` and `conftest` in CI.
- **Terraform in CI.** `plan` on PR (posted as a comment) and `apply` on merge, with a separate, more privileged role that only `main` can assume.
