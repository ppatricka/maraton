# Maratón infrastructure (AWS + HCP Terraform)

All AWS infrastructure for the exercise is defined here and deployed through **HCP Terraform**:
HCP Terraform stores the state, runs `plan`/`apply`, and gets **short-lived AWS credentials for
every run through OIDC** (dynamic provider credentials). No AWS access keys are stored anywhere.

```
terraform/
  bootstrap/      one-time: OIDC trust + IAM role that HCP Terraform runs assume
                  (runs on the laptop; state in HCP workspace `maraton-bootstrap`)
  versions.tf     HCP Terraform `cloud` block + provider versions
  providers.tf    AWS provider with default tags
  variables.tf    inputs (region, CIDRs, names)
  network.tf      VPC: 2 public + 2 private subnets, NAT gateway, EKS subnet tags
  outputs.tf      IDs later steps use
```

## Three configurations, three HCP Terraform workspaces (project `wiz`)

| Folder | Workspace | Runs where | What it manages |
| --- | --- | --- | --- |
| `bootstrap/` | `maraton-bootstrap` | Locally (Local execution mode) | OIDC trust + run role for HCP Terraform |
| `.` (this folder) | `maraton-aws` | HCP, via the `iac` pipeline | App environment: VPC, EKS, ECR, MongoDB VM, backups |
| `security/` | `maraton-security` | HCP, via the `iac` pipeline | Security baseline: CloudTrail, audit bucket, Config, Security Hub, Inspector, GuardDuty |

The security baseline has its own state and lifecycle, so the app environment can be destroyed and
rebuilt while audit logging and detection keep running. It refers to the backup bucket by naming
convention rather than by reading the app workspace's state, so the two stay independent.
`.terraformignore` keeps `security/` and `bootstrap/` out of the `maraton-aws` upload.

## One-time setup

### 1. HCP Terraform

Current setup: organization **`patriciarojas-sandbox`**, project **`wiz`**.

1. Sign in at https://app.terraform.io (the free tier is enough).
2. In project `wiz`, create two **CLI-driven** workspaces:
   - **`maraton-aws`**: the main infrastructure. Leave execution mode on **Remote**.
     (We'll switch it to VCS-driven when we set up the IaC pipeline.)
   - **`maraton-bootstrap`**: under **Settings → General**, set execution mode to **Local**.
     HCP only stores its state; plan/apply run on your laptop with your AWS keys.
3. On your laptop, run `terraform login` and follow the prompt to store an API token.

> The project name matters: the role's trust policy only accepts tokens whose subject is
> `organization:patriciarojas-sandbox:project:wiz:workspace:maraton-aws:run_phase:*`.
> If you move or rename the workspace or project, update `bootstrap/variables.tf` and re-apply the
> bootstrap, or runs fail with `AccessDenied ... sts:AssumeRoleWithWebIdentity`.

### 2. Bootstrap the AWS trust (from your laptop, once)

Export your CloudLabs AWS credentials in your terminal (`AWS_ACCESS_KEY_ID`,
`AWS_SECRET_ACCESS_KEY`, plus `AWS_SESSION_TOKEN` if given), then check they work:

```bash
aws sts get-caller-identity
```

Then create the OIDC trust and role:

```bash
cd terraform/bootstrap
terraform init
terraform apply      # org, project and workspace come from variables.tf defaults
```

Get the role ARN without quotes: `terraform output -raw hcp_terraform_run_role_arn`.

### 3. Point the workspace at the role

In the `maraton-aws` workspace, go to **Variables** and add two **environment variables**
(category *Environment*, not *Terraform*; HCP ignores `TFC_AWS_*` set as Terraform variables):

| Key                     | Value                    |
| ----------------------- | ------------------------ |
| `TFC_AWS_PROVIDER_AUTH` | `true`                   |
| `TFC_AWS_RUN_ROLE_ARN`  | the role ARN from step 2 |

## Deploying

From the `terraform/` folder:

```bash
terraform init      # connects this folder to the maraton-aws workspace
terraform plan      # runs remotely in HCP Terraform; your terminal streams the output
terraform apply
```

You can watch each run (and its plan) in the HCP Terraform UI as well.

## Cost note

The NAT gateway bills by the hour (roughly a few US dollars a day). If the CloudLabs voucher has a
spending cap, `terraform destroy` when you're not working, and re-apply before the demo.
