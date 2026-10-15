# Deploying Maratón to EKS

**Run every command from the repo root (`maraton/`), not from inside `k8s/`**, in a terminal with
your CloudLabs AWS keys exported. After a destroy/re-apply, first run
`aws eks update-kubeconfig --region us-east-1 --name maraton-eks` (the endpoint changes).

| File | What it creates |
| --- | --- |
| `namespace.yaml` | Namespace `maraton` |
| `rbac.yaml` | ServiceAccount `maraton`, bound to **cluster-admin** (intentional weakness) |
| `deployment.yaml` | 2 app pods; `MONGODB_URI` and `SESSION_SECRET` come from a Secret as env vars |
| `service.yaml` | Stable in-cluster address for the pods |
| `ingress.yaml` | Ingress the AWS Load Balancer Controller turns into a public ALB |
| `kustomization.yaml` | Lists the files and pins the image (`kubectl apply -k k8s/`) |

## 1. Install the AWS Load Balancer Controller (once per cluster)

```bash
brew install helm                                  # first time only
helm repo add eks https://aws.github.io/eks-charts
helm repo update
eval "$(terraform -chdir=terraform output -raw lb_controller_helm_command)"
kubectl get deploy -n kube-system aws-load-balancer-controller   # wait for 2/2 READY
```

## 2. Build and push the image (manual for now; the pipeline does this later)

The Mac is ARM (Apple Silicon) and the EKS nodes are x86, so build for `linux/amd64`.
ECR tags are immutable: use a new tag for every push and update `newTag` in `kustomization.yaml`.

```bash
ECR=$(terraform -chdir=terraform output -raw ecr_repository_url)
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin "${ECR%%/*}"
docker buildx build --platform linux/amd64 \
  --build-arg CANDIDATE_NAME="Patricia Rojas Perez" \
  -t "$ECR:v1" --push app/
```

## 3. Create the namespace and the Secret

The Secret is created from Terraform's outputs, so the database password never lands in git.

```bash
kubectl apply -f k8s/namespace.yaml
kubectl create secret generic maraton-env -n maraton \
  --from-literal=MONGODB_URI="$(terraform -chdir=terraform output -raw mongodb_uri)" \
  --from-literal=SESSION_SECRET="$(openssl rand -hex 32)"
```

## 4. Deploy

```bash
kubectl apply -k k8s/
kubectl get pods -n maraton -w        # wait for 2 pods Running and 1/1 READY, then Ctrl-C
kubectl get ingress -n maraton        # ADDRESS = the ALB hostname (DNS takes ~2-3 min)
```

## 5. Seed the demo data and verify

```bash
kubectl exec -n maraton deploy/maraton -- node seed.js
kubectl exec -n maraton deploy/maraton -- cat /app/wizexercise.txt
kubectl auth can-i '*' '*' --as=system:serviceaccount:maraton:maraton   # "yes" = cluster-admin
```

Open `http://<ALB hostname>` and sign in as `patricia@maraton.demo` / `maraton-demo`.

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| Pod `CreateContainerConfigError` | The `maraton-env` Secret doesn't exist yet (step 3) |
| Pod `CrashLoopBackOff`, log says `exec format error` | Image built for ARM; rebuild with `--platform linux/amd64` |
| Pod `CrashLoopBackOff`, log says `Could not connect to MongoDB` | Wrong URI in the Secret, or the security group/auth on the VM |
| Ingress has no ADDRESS | Controller not running or lacking permissions: `kubectl logs -n kube-system deploy/aws-load-balancer-controller` |
| `ImagePullBackOff` | Tag in `kustomization.yaml` doesn't exist in ECR |
