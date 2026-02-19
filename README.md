# Cost Guardian

**Serverless AWS cost hygiene engine built with Terraform, Lambda, KMS, CI/CD, and observability.**

Cost Guardian scans an AWS account for idle resources (e.g., unattached EBS volumes, unassociated Elastic IPs), estimates monthly waste, stores encrypted reports in S3, publishes CloudWatch metrics, and sends Slack notifications.

This project demonstrates real-world cloud engineering patterns including Infrastructure as Code, least-privilege IAM, KMS encryption, remote state management, and GitHub Actions CI/CD using OIDC.

---

## Architecture Overview

**Execution Flow**

EventBridge (scheduled daily)  
→ Lambda function  
→ Rule engine scans AWS regions  
→ Encrypted report stored in S3  
→ CloudWatch metrics published  
→ Slack notification sent  

All infrastructure is provisioned with Terraform.

---

## Core AWS Services Used

- AWS Lambda  
- Amazon S3 (KMS-encrypted)  
- AWS KMS (customer-managed key)  
- AWS Systems Manager Parameter Store (SecureString)  
- Amazon EventBridge  
- Amazon CloudWatch (Logs + Custom Metrics)  
- DynamoDB (Terraform state locking)  
- GitHub Actions (OIDC federation)  

---

## Security Design

Security was built into the system from the beginning.

### Secrets Management

- Slack webhook stored in **SSM Parameter Store (SecureString)**
- Encrypted with customer-managed **KMS key**
- Terraform configured with `ignore_changes` to prevent accidental secret overwrite
- No hardcoded credentials anywhere in the repository

### Encryption

- S3 reports bucket enforces **KMS encryption by default**
- Lambda does not manually manage encryption (infrastructure-level enforcement)
- KMS permissions scoped to the specific key ARN

### IAM

Lambda execution role limited to:

- `ec2:Describe*`
- `ssm:GetParameter`
- `s3:PutObject`
- `cloudwatch:PutMetricData`
- `kms:Decrypt`
- `kms:GenerateDataKey`

GitHub Actions uses OIDC federation with scoped trust:

```
repo:Hurricaneia/cost-guardian:*
```

No static AWS credentials are used in CI/CD.

---

## Infrastructure

Provisioned entirely with Terraform.

### Remote State

- State stored in encrypted S3
- State locking via DynamoDB
- Versioning enabled
- Prevent-destroy on state bucket

### Lambda Configuration

- Python 3.11
- 512 MB memory
- 60 second timeout
- Environment variables for SSM parameter and report bucket

---

## Observability

Lambda publishes custom CloudWatch metrics:

Namespace: `CostGuardian`

Metrics:

- `TotalEstimatedMonthlyWaste`
- `TotalFindings`

This enables dashboards or alerting for cost drift over time.

---

## Rule Engine Design

Rules follow a pluggable engine pattern:

```python
class BaseRule:
    RULE_NAME = "..."

    def run(self):
        return [Finding(...)]
```

The engine:

- Scans all enabled regions
- Aggregates findings
- Calculates total estimated monthly waste
- Returns structured JSON report

Currently implemented:

- Unattached EBS volumes
- Unassociated Elastic IPs

Designed for extension.

---

## CI/CD

GitHub Actions pipeline:

- Terraform init
- Terraform validate
- Terraform plan
- Terraform apply (main branch only)

Uses OIDC federation for secure AWS access.

---

## Project Structure

```
cost-guardian/
├── infra/
│   └── envs/dev/
│       ├── main.tf
│       ├── providers.tf
│       ├── backend.tf
│       └── lambda.zip
├── src/
│   └── cost_guardian/
│       ├── handler.py
│       ├── engine.py
│       ├── models.py
│       └── rules/
└── .github/workflows/deploy.yml
```

---

## Why This Project Matters

Many cloud projects stop at:

- Basic Lambda deployment
- Hardcoded secrets
- No remote state
- No CI/CD
- No encryption discipline

Cost Guardian demonstrates:

- Infrastructure safety
- IAM correctness
- Secret lifecycle control
- Secure CI/CD practices
- Observability integration
- Production-style structure

This is not a demo script — it is a deployable cloud platform component.

---

## Future Enhancements

- Additional cost rules (RDS idle, old snapshots)
- Multi-account scanning via STS assume role
- Slack remediation links
- Automated CloudWatch dashboards
- Cost anomaly detection integration

