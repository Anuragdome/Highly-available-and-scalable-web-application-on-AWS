# Highly Available and Scalable Web Application on AWS

A Terraform project that deploys a highly available, auto-scaling web application on AWS. A Node.js student-records app runs on EC2 instances spread across two Availability Zones behind an Application Load Balancer, and stores its data in a MySQL RDS instance placed in private subnets. Database credentials are kept in AWS Secrets Manager and fetched by each instance at boot.

## Architecture

```
                        Internet
                           │
                           ▼
              ┌─────────────────────────┐
              │ Application Load Balancer│  (HTTP :80, public subnets)
              └────────────┬────────────┘
                           │
          ┌────────────────┴────────────────┐
          ▼                                 ▼
 ┌─────────────────┐               ┌─────────────────┐
 │  EC2 (AZ 1)     │               │  EC2 (AZ 2)     │   Auto Scaling Group
 │  Node.js + PM2  │               │  Node.js + PM2  │   min 2 / desired 2 / max 4
 └────────┬────────┘               └────────┬────────┘
          │            MySQL :3306          │
          └────────────────┬────────────────┘
                           ▼
              ┌─────────────────────────┐
              │  RDS MySQL 8.0          │   (private subnets)
              └─────────────────────────┘

        AWS Secrets Manager ──► DB credentials read by EC2 at startup
```

## What Gets Deployed

| Component | Details |
|---|---|
| **VPC** | `10.0.0.0/16` with DNS hostnames and DNS support enabled |
| **Subnets** | 2 public (ALB + web servers) and 2 private (RDS), spread over 2 AZs |
| **Networking** | Internet Gateway and a public route table (no NAT Gateway, to save cost) |
| **Application Load Balancer** | Internet-facing, HTTP listener on port 80, health check on `/` |
| **Launch Template** | Ubuntu 22.04 LTS (latest Canonical AMI), `t2.micro`, `LabInstanceProfile` IAM profile, bootstrap via `user_data.sh` |
| **Auto Scaling Group** | Min 2, desired 2, max 4 instances across both public subnets, attached to the ALB target group |
| **RDS** | MySQL 8.0, `db.t3.micro`, 20 GB, not publicly accessible, single-AZ |
| **Secrets Manager** | Stores DB username, password, host and database name as JSON |
| **Security Groups** | ALB: HTTP from anywhere. Web: HTTP from ALB only, plus SSH. DB: MySQL from web SG only |

## Repository Structure

```
.
├── provider.tf      # AWS provider (us-east-1) and version constraint (~> 5.0)
├── variables.tf     # project_name, db_username, db_password
├── main.tf          # VPC, subnets, IGW, route tables, security groups
├── compute.tf       # AMI lookup, launch template, ALB, target group, listener, ASG
├── database.tf      # RDS subnet group, RDS instance, Secrets Manager secret
├── outputs.tf       # ALB DNS name and RDS endpoint
├── user_data.sh     # EC2 bootstrap script (installs app, configures DB, starts PM2)
└── .terraform.lock.hcl
```

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.0
- An AWS account or AWS Academy lab environment with credentials configured (`aws configure` or environment variables)
- An existing IAM instance profile named **`LabInstanceProfile`** (provided by AWS Academy labs). It must allow the instances to read from Secrets Manager. If your account uses a different name, update `data "aws_iam_instance_profile"` in `compute.tf`.

## Getting Started

### 1. Clone the repository

```bash
git clone https://github.com/<your-username>/Highly-available-and-scalable-web-application-on-AWS.git
cd Highly-available-and-scalable-web-application-on-AWS
```

### 2. Set your database credentials

Avoid editing passwords into the code. Pass them in at apply time instead:

```bash
export TF_VAR_db_username="your_db_user"
export TF_VAR_db_password="a-strong-password"
```

Or create a `terraform.tfvars` file (already git-ignored, see [Security Notes](#security-notes)):

```hcl
db_username = "your_db_user"
db_password = "a-strong-password"
```

### 3. Deploy

```bash
terraform init
terraform plan
terraform apply
```

### 4. Open the application

When the apply finishes, Terraform prints the outputs:

```
alb_dns_name = "student-records-app-alb-xxxxxxxx.us-east-1.elb.amazonaws.com"
rds_endpoint = "student-records-app-db.xxxxxxxx.us-east-1.rds.amazonaws.com"
```

Open `http://<alb_dns_name>` in your browser. Allow a few minutes after the apply for the instances to finish bootstrapping and pass their health checks.

### 5. Tear down

To avoid ongoing charges, destroy everything when you are done:

```bash
terraform destroy
```

## Configuration

| Variable | Description | Default |
|---|---|---|
| `project_name` | Prefix used to name all resources | `student-records-app` |
| `db_username` | RDS master username | set in `variables.tf`, override it |
| `db_password` | RDS master password (marked sensitive) | set in `variables.tf`, override it |

The AWS region is set to `us-east-1` in `provider.tf`. The bootstrap script also uses `us-east-1`, so change both if you switch regions.

## How the Bootstrap Works

Each instance launched by the Auto Scaling Group runs `user_data.sh`, which:

1. Installs Node.js, npm, the AWS CLI, `jq` and the MySQL client.
2. Downloads and unpacks the application code.
3. Installs the Node dependencies and PM2.
4. Retrieves the newest secret from Secrets Manager and extracts the DB host, user, password and name.
5. Creates the `students` table in RDS and seeds it with sample records.
6. Writes the app's `config.js` with the retrieved credentials.
7. Starts the app with PM2 and configures it to restart on reboot.

## Security Notes

This project is designed as a learning lab. Before using anything like it beyond that, review the following:

- **Do not commit Terraform state.** `terraform.tfstate` and its backup contain resource details and secrets in plain text. Add a `.gitignore` (below) and consider a remote backend such as S3 with DynamoDB locking.
- **Change the default database credentials.** Default values live in `variables.tf`. Override them and rotate any credentials that have already been pushed to a public repository.
- **Restrict SSH.** The web security group allows SSH from `0.0.0.0/0`. Limit it to your IP or remove it and use AWS Systems Manager Session Manager.
- **Add HTTPS.** The ALB only serves HTTP on port 80. Add an ACM certificate and an HTTPS listener for production use.
- **Instances sit in public subnets** to avoid NAT Gateway cost. For production, move them to private subnets behind a NAT Gateway.
- **RDS is single-AZ** (`multi_az = false`) and skips the final snapshot. Enable Multi-AZ and snapshots for real workloads.
- **Secret lookup is "newest secret wins".** The bootstrap script picks the most recently created secret in the account, which is fine in a dedicated lab account but fragile in a shared one. Pass the secret name explicitly instead.
- **The bootstrap script drops and recreates the `students` table** on every instance launch, so scaling events reset the data. Seed the schema once rather than on every boot.

### Recommended `.gitignore`

```gitignore
# Terraform
.terraform/
*.tfstate
*.tfstate.*
*.tfvars
crash.log
```

## Possible Improvements

- Target-tracking scaling policies (for example on average CPU) so the ASG actually scales between 2 and 4 instances
- HTTPS with ACM and a custom domain through Route 53
- Private subnets for the web tier with a NAT Gateway or VPC endpoints
- RDS Multi-AZ with automated backups
- Remote state backend (S3 + DynamoDB)
- Replace the hardcoded `config.js` approach with the app reading from Secrets Manager at runtime
- Break the configuration into reusable Terraform modules

## License

Add a license of your choice (for example MIT) to this repository.
