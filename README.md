# Windows Certificate Rotation Demo with AAP 2.6 and EDA

Automated demo showing event-driven certificate rotation on Windows Server using Red Hat Ansible Automation Platform (AAP) 2.6 and Event-Driven Ansible (EDA).

## What It Does

1. Provisions a Windows Server 2022 VM in the same AWS VPC as your AAP instance
2. Installs IIS with a short-lived TLS certificate (expires in 20 minutes)
3. Configures AAP with inventory, credentials, project, job template, and EDA rulebook
4. When EDA detects the cert is expiring (≤7 days), it automatically rotates it

## Prerequisites

- AWS CLI authenticated (`aws sts get-caller-identity`)
- GitHub CLI authenticated (`gh auth status`)
- AAP credentials exported as environment variables
- `ansible-core` >= 2.15, `python3`, `git`, `aws` CLI v2, `gh` CLI

## Quick Start

```bash
# 0. Set environment variables
export AAP_HOSTNAME="aap-nostromo.demoredhat.com"
export AAP_USERNAME="atrotter"
export AAP_PASSWORD="your-password"
export AAP_PROTOCOL="http"
export AAP_VALIDATE_CERTS="false"
export MY_PUBLIC_IP="$(curl -s https://checkip.amazonaws.com)"

# 1. Install dependencies
pip install boto3 botocore pywinrm requests
ansible-galaxy collection install -r requirements.yml --force

# 2. Provision Windows VM
ansible-playbook infrastructure/provision_aws.yml

# 3. Setup IIS and demo certs
source .env.demo
ansible-playbook playbooks/setup_iis.yml -i inventory/hosts.yml \
  -e "ansible_user=Administrator ansible_password=$WINDOWS_ADMIN_PASSWORD"

# 4. Configure AAP
ansible-playbook configure_aap/configure_aap.yml

# 5. Fire the test event
source .env.demo
bash scripts/send_test_event.sh
```

## Teardown

```bash
ansible-playbook infrastructure/teardown_aws.yml
```

All AWS resources are tagged `Owner: atrotter`, `Environment: Demo`, `Purpose: cert-rotation-demo`.

## Architecture

```
Windows Server 2022 (AWS EC2, same VPC as AAP)
  └── IIS with short-lived SSL cert bound to HTTPS
  └── Scheduled task POSTs webhook to AAP Event Stream every 5 min
         ↓
AAP EDA Event Stream (receives webhook)
         ↓
EDA Rulebook: if days_left <= 7 → run_job_template
         ↓
Job Template: "Rotate Windows Certificate"
  ├── win_certificate_info  (verify expiring cert exists)
  ├── win_shell             (find replacement cert, rebind IIS)
  ├── win_certificate_store (remove old cert)
  └── win_uri               (verify HTTPS works)
```
