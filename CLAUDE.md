# CLAUDE.md — Windows Certificate Rotation Demo (Full End-to-End)

## What This Project Does

When fully built and executed, this project will:

1. Create a GitHub repository with all demo code (playbooks, rulebooks, scripts, docs)
2. Auto-discover the AAP instance's AWS network configuration (VPC, subnet, security group) by looking up the EC2 instance behind `aap-nostromo.demoredhat.com`
3. Provision a Windows Server 2022 VM in the SAME AWS VPC/subnet as the AAP instance
4. Configure WinRM on the Windows VM for Ansible management
5. Install IIS and create demo TLS/SSL certificates on the Windows VM
6. Configure the AAP instance with all required objects (inventory, credentials, project, job templates, EDA event stream, EDA rulebook activation)
7. Leave everything ready to demo — the user just fires the test event and films the result

**Existing AAP Instance:** `http://aap-nostromo.demoredhat.com`

## Prerequisites — What Must Be Done BEFORE Running Anything

### 1. AWS CLI Must Be Authenticated

```bash
aws configure
# Provide: Access Key ID, Secret Access Key, Region, Output format
# Verify:
aws sts get-caller-identity
```

Required IAM permissions:
- EC2: `RunInstances`, `DescribeInstances`, `TerminateInstances`, `CreateSecurityGroup`, `AuthorizeSecurityGroupIngress`, `DeleteSecurityGroup`, `DescribeSecurityGroups`, `CreateKeyPair`, `DeleteKeyPair`, `DescribeImages`, `DescribeSubnets`, `DescribeVpcs`, `GetPasswordData`, `CreateTags`
- Route53 or DNS resolution capability (to resolve the AAP hostname to an IP)

### 2. GitHub CLI Must Be Authenticated

```bash
gh auth login
# Verify:
gh auth status
```

### 3. AAP Credentials as Environment Variables

```bash
export AAP_HOSTNAME="aap-nostromo.demoredhat.com"
export AAP_USERNAME="admin"
export AAP_PASSWORD="your-password-here"
export AAP_PROTOCOL="http"
export AAP_VALIDATE_CERTS="false"
```

That's it. No AWS VPC IDs, no subnet IDs, no manual lookups. The playbooks discover everything automatically from the AAP instance.

### 4. Your Public IP (for RDP Access)

```bash
export MY_PUBLIC_IP="$(curl -s https://checkip.amazonaws.com)"
```

### 5. Required Tools Installed Locally

- `ansible-core` >= 2.15
- `python3` with `pip`
- `aws` CLI v2
- `gh` CLI
- `git`

## AWS Tagging Policy

**ALL AWS resources created by this project MUST include the tag `Owner: atrotter`.** This applies to:
- EC2 instances
- Security groups
- Key pairs (note: key pairs don't support tags in all regions — tag only if supported)
- Any other resource created

Every task that creates an AWS resource must include:
```yaml
tags:
  Owner: atrotter
  Environment: Demo
  Purpose: cert-rotation-demo
```

These three tags must be present on EVERY AWS resource. No exceptions.

## Execution Order

### Step 0: Install Dependencies

```bash
pip install boto3 botocore pywinrm requests
ansible-galaxy collection install -r requirements.yml --force
```

### Step 1: Create GitHub Repo and Push Code

```bash
gh repo create windows-cert-rotation-demo --public --clone --description "Windows Certificate Rotation Demo with AAP 2.6 and EDA"
cd windows-cert-rotation-demo
# (Claude CLI creates all files here)
git add -A
git commit -m "Initial commit: Windows cert rotation demo with AAP 2.6 and EDA"
git push origin main
```

### Step 2: Provision the Windows VM

```bash
ansible-playbook infrastructure/provision_aws.yml
```

### Step 3: Setup IIS and Demo Certs

```bash
source .env.demo
ansible-playbook playbooks/setup_iis.yml -i inventory/hosts.yml -e "ansible_user=Administrator ansible_password=$WINDOWS_ADMIN_PASSWORD"
```

### Step 4: Configure AAP

```bash
ansible-playbook configure_aap/configure_aap.yml
```

### Step 5: Demo Time

```bash
source .env.demo
bash scripts/send_test_event.sh
```

Open browser to `https://<WINDOWS_PUBLIC_IP>` and AAP UI at `http://aap-nostromo.demoredhat.com` to watch it happen.

## Architecture

```
Windows Server 2022 (AWS EC2, same VPC as AAP)
  └── IIS with short-lived SSL cert bound to HTTPS
  └── Test event script POSTs webhook to AAP Event Stream
         ↓
AAP Event Stream (receives webhook)
         ↓
EDA Rulebook: if days_left <= 7 → run_job_template
         ↓
Job Template: "Rotate Windows Certificate"
  ├── ansible.windows.win_certificate_info (verify expiring cert)
  ├── ansible.windows.win_shell (find replacement, rebind IIS)
  ├── ansible.windows.win_certificate_store (remove old cert)
  └── ansible.windows.win_uri (verify HTTPS works)
```

## Repository Structure

```
windows-cert-rotation-demo/
├── CLAUDE.md
├── README.md
├── requirements.yml
├── .gitignore
│
├── infrastructure/
│   ├── provision_aws.yml
│   └── teardown_aws.yml
│
├── configure_aap/
│   ├── configure_aap.yml
│   └── vars/
│       ├── controller_config.yml
│       └── eda_config.yml
│
├── playbooks/
│   ├── setup_iis.yml
│   ├── rotate_certificate.yml
│   ├── verify_certificate.yml
│   └── setup_monitoring.yml
│
├── extensions/
│   └── eda/
│       └── rulebooks/
│           └── cert_expiry_watcher.yml
│
├── scripts/
│   ├── send_cert_event.ps1
│   ├── send_test_event.sh
│   └── winrm_userdata.ps1
│
├── inventory/
│   ├── hosts.yml                       # Auto-populated by provision_aws.yml
│   └── group_vars/
│       └── windows.yml
│
├── vars/
│   ├── demo_vars.yml
│   └── cert_thumbprints.yml            # Auto-populated by setup_iis.yml
│
└── docs/
    ├── prerequisites.md
    ├── step_by_step.md
    └── demo_walkthrough.md
```

## Critical Requirements

- EDA rulebooks MUST be at `extensions/eda/rulebooks/` — this is the standard path EDA projects expect
- `.gitignore` MUST exclude: `*.pem`, `.env.demo`, `vars/cert_thumbprints.yml`, `*.retry`, `__pycache__/`
- ALL AWS resources MUST be tagged with `Owner: atrotter`, `Environment: Demo`, `Purpose: cert-rotation-demo`
- ALL Ansible tasks MUST use FQCNs (e.g., `ansible.windows.win_shell` not `win_shell`)
- ALL playbook tasks MUST have a `name`
- NEVER hardcode passwords, IPs, or thumbprints — use variables, extra_vars, or env lookups
- NEVER commit secrets to Git

## Collections

### `requirements.yml`

```yaml
---
collections:
  - name: amazon.aws
  - name: community.aws
  - name: ansible.windows
  - name: community.windows
  - name: infra.windows_ops
  - name: infra.aap_configuration
  - name: ansible.controller
    version: ">=4.6.0"
  - name: ansible.eda
  - name: ansible.platform
  - name: community.crypto
```

Python: `pip install boto3 botocore pywinrm requests`

## Credential Handling

- **AWS:** Via `boto3` from `~/.aws/credentials` or environment. Never hardcode.
- **AAP:** From `AAP_HOSTNAME`, `AAP_USERNAME`, `AAP_PASSWORD`, `AAP_PROTOCOL`, `AAP_VALIDATE_CERTS` env vars.
- **Windows admin password:** Decrypted from EC2 using key pair. Saved to `.env.demo` (gitignored).
- **Git:** Public repo = no creds. Private repo = user sets `GIT_USERNAME` and `GIT_PAT` env vars.
- **NEVER commit passwords, tokens, or .pem files to Git.**

## Variables

### `vars/demo_vars.yml`

```yaml
---
cert_dns_name: "demo.contoso.com"
cert_store_location: LocalMachine
cert_store_name: My
cert_expiry_threshold_days: 7
demo_cert_validity_minutes: 20
replacement_cert_validity_years: 1
iis_site_name: "Default Web Site"
iis_https_port: 443
cert_check_interval_minutes: 5
```

### `inventory/group_vars/windows.yml`

```yaml
---
ansible_connection: winrm
ansible_winrm_transport: ntlm
ansible_winrm_server_cert_validation: ignore
ansible_port: 5986
ansible_winrm_scheme: https
```

## Phase 1: Provision AWS Infrastructure

### `infrastructure/provision_aws.yml`

**Hosts:** localhost
**Connection:** local
**Gather facts:** yes

**Purpose:** Auto-discover AAP's AWS network, provision Windows VM in same network.

### Tasks:

1. **Validate environment variables** — assert `AAP_HOSTNAME` and `MY_PUBLIC_IP` are set, fail with helpful message if not.

2. **Set AAP hostname fact** — `aap_hostname: "{{ lookup('env', 'AAP_HOSTNAME') }}"` and `my_public_ip: "{{ lookup('env', 'MY_PUBLIC_IP') }}"`

3. **Resolve AAP hostname to IP** using `ansible.builtin.shell`:
   ```bash
   getent hosts {{ aap_hostname }} | awk '{print $1}'
   ```
   Register as `aap_ip_result`. Fail if empty: "Cannot resolve AAP hostname. Check DNS."

4. **Find the AAP EC2 instance by IP** using `amazon.aws.ec2_instance_info`:
   - Try multiple filters in sequence until one matches:
     - First try: `private-ip-address: "{{ aap_ip }}"`
     - If no results, try: `ip-address: "{{ aap_ip }}"`
     - If no results, try: `network-interface.addresses.association.public-ip: "{{ aap_ip }}"`
   - Assert at least one instance found. Fail with: "Could not find EC2 instance for AAP hostname. Ensure AAP runs in this AWS account/region."

5. **Extract AAP network details** — set_fact:
   - `aap_vpc_id` from `instances[0].vpc_id`
   - `aap_subnet_id` from `instances[0].subnet_id`
   - `aap_az` from `instances[0].placement.availability_zone`
   - `aap_region` from AZ with last char stripped
   - `aap_private_ip` from `instances[0].private_ip_address`

6. **Display discovered info** — debug:
   ```
   AAP Instance Network Discovery:
     VPC: {{ aap_vpc_id }}
     Subnet: {{ aap_subnet_id }}
     AZ: {{ aap_az }}
     Region: {{ aap_region }}
     AAP Private IP: {{ aap_private_ip }}
   ```

7. **Get VPC CIDR** using `amazon.aws.ec2_vpc_net_info`:
   - vpc_ids: `{{ aap_vpc_id }}`
   - Extract CIDR block, set_fact `vpc_cidr`

8. **Find latest Windows Server 2022 AMI** using `amazon.aws.ec2_ami_info`:
   - Filters: `name: "Windows_Server-2022-English-Full-Base-*"`, `state: available`
   - Owners: `amazon`
   - Region: `{{ aap_region }}`
   - Sort by `creation_date`, pick last

9. **Create EC2 key pair** using `amazon.aws.ec2_key`:
   - Name: `cert-rotation-demo-key`
   - Region: `{{ aap_region }}`
   - Tags: `{Owner: atrotter, Environment: Demo, Purpose: cert-rotation-demo}`
   - Save private key to `./cert-rotation-demo-key.pem` mode 0600 when changed

10. **Create security group** using `amazon.aws.ec2_security_group`:
    - Name: `cert-rotation-demo-sg`
    - Description: "Windows cert rotation demo - managed by Ansible"
    - VPC: `{{ aap_vpc_id }}`
    - Region: `{{ aap_region }}`
    - Tags: `{Owner: atrotter, Environment: Demo, Purpose: cert-rotation-demo}`
    - Rules:
      - proto: tcp, ports: 3389, cidr_ip: `{{ my_public_ip }}/32`, rule_desc: "RDP from user IP"
      - proto: tcp, ports: 5986, cidr_ip: `{{ vpc_cidr }}`, rule_desc: "WinRM HTTPS from VPC"
      - proto: tcp, ports: 443, cidr_ip: `0.0.0.0/0`, rule_desc: "HTTPS for IIS demo"
      - proto: tcp, ports: 80, cidr_ip: `0.0.0.0/0`, rule_desc: "HTTP for IIS test"

11. **Launch EC2 instance** using `amazon.aws.ec2_instance`:
    - Name: `cert-rotation-demo-windows`
    - Image ID: from step 8
    - Instance type: `t3.medium`
    - Key name: `cert-rotation-demo-key`
    - VPC subnet ID: `{{ aap_subnet_id }}`
    - Security groups: `["cert-rotation-demo-sg"]`
    - Network: `assign_public_ip: true`
    - User data: `"{{ lookup('file', '../scripts/winrm_userdata.ps1') }}"`
    - Volumes: `[{device_name: "/dev/sda1", ebs: {volume_size: 30, volume_type: "gp3", delete_on_termination: true}}]`
    - Tags: `{Owner: atrotter, Environment: Demo, Purpose: cert-rotation-demo}`
    - State: running
    - Wait: yes
    - Region: `{{ aap_region }}`

12. **Wait for WinRM** — `ansible.builtin.wait_for`, host: public IP, port: 5986, timeout: 600, delay: 120

13. **Decrypt Windows password** — `community.aws.ec2_win_password`, instance_id, key_file, wait: yes, wait_timeout: 300

14. **Write inventory/hosts.yml** with Windows VM private IP

15. **Write .env.demo**:
    ```bash
    export WINDOWS_PUBLIC_IP="<value>"
    export WINDOWS_PRIVATE_IP="<value>"
    export WINDOWS_ADMIN_PASSWORD="<value>"
    export WINDOWS_INSTANCE_ID="<value>"
    export AAP_VPC_ID="<value>"
    export AAP_SUBNET_ID="<value>"
    export AAP_REGION="<value>"
    export AAP_PRIVATE_IP="<value>"
    ```

16. **Add host to in-memory inventory** — `ansible.builtin.add_host` with all WinRM vars, ansible_user: Administrator, ansible_password from decrypted password

17. **Test WinRM** — new play targeting the Windows host, `ansible.windows.win_ping`, retries: 5, delay: 60

18. **Display summary**:
    ```
    =============================================
    ✅ Windows VM Provisioned Successfully!
    =============================================
    Public IP (RDP/browser): {{ public_ip }}
    Private IP (AAP inventory): {{ private_ip }}
    Admin Password: {{ password }}
    Instance ID: {{ instance_id }}
    
    RDP: mstsc /v:{{ public_ip }}
    IIS: https://{{ public_ip }}
    
    All details saved to .env.demo
    All resources tagged: Owner=atrotter
    =============================================
    ```

### `scripts/winrm_userdata.ps1`

```
<powershell>
Set-ExecutionPolicy Unrestricted -Scope LocalMachine -Force
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$url = "https://raw.githubusercontent.com/ansible/ansible-documentation/devel/examples/scripts/ConfigureRemotingForAnsible.ps1"
$file = "$env:temp\ConfigureRemotingForAnsible.ps1"
(New-Object -TypeName System.Net.WebClient).DownloadFile($url, $file)
& $file -SkipNetworkProfileCheck

Set-Service -Name WinRM -StartupType Automatic
Start-Service -Name WinRM

netsh advfirewall firewall add rule name="WinRM HTTPS" dir=in action=allow protocol=TCP localport=5986
netsh advfirewall firewall add rule name="HTTPS" dir=in action=allow protocol=TCP localport=443
netsh advfirewall firewall add rule name="HTTP" dir=in action=allow protocol=TCP localport=80
</powershell>
```

### `infrastructure/teardown_aws.yml`

**Hosts:** localhost, **Connection:** local

Tasks:
1. Source .env.demo to get region, or discover region the same way provision does
2. Terminate EC2 by name tag `cert-rotation-demo-windows` — `amazon.aws.ec2_instance` state: absent, filters by tag Name
3. Wait 30 seconds
4. Delete SG `cert-rotation-demo-sg` — `amazon.aws.ec2_security_group` state: absent
5. Delete key pair `cert-rotation-demo-key` — `amazon.aws.ec2_key` state: absent
6. Remove local files: `cert-rotation-demo-key.pem`, `.env.demo`
7. Debug: "All demo AWS resources cleaned up. Owner=atrotter resources removed."

## Phase 2: Setup IIS (`playbooks/setup_iis.yml`)

**Hosts:** windows
**Gather facts:** no
**Vars files:** `../vars/demo_vars.yml`

### Tasks:

1. Install IIS — `ansible.windows.win_feature`, name: `Web-Server`, include_management_tools: yes
2. Start IIS — `ansible.windows.win_service`, name: W3SVC, state: started, start_mode: auto
3. Create demo HTML page — `ansible.windows.win_copy`, content: simple HTML ("Certificate Rotation Demo — Protected by auto-rotating TLS via Red Hat AAP"), dest: `C:\inetpub\wwwroot\index.html`
4. Create short-lived cert — `ansible.windows.win_shell`:
   ```powershell
   $cert = New-SelfSignedCertificate -DnsName "{{ cert_dns_name }}" -CertStoreLocation "Cert:\LocalMachine\My" -NotAfter (Get-Date).AddMinutes({{ demo_cert_validity_minutes }}) -KeyExportPolicy Exportable -KeySpec KeyExchange -KeyLength 2048 -FriendlyName "Demo Cert - Expiring Soon"
   Write-Output $cert.Thumbprint
   ```
   Register, parse stdout_lines[0] as thumbprint, set_fact `old_cert_thumbprint`
5. Create replacement cert — same pattern, `AddYears({{ replacement_cert_validity_years }})`, FriendlyName "Demo Cert - Renewed", set_fact `new_cert_thumbprint`
6. Bind cert to IIS — `ansible.windows.win_shell`:
   ```powershell
   Import-Module WebAdministration
   Get-WebBinding -Name "{{ iis_site_name }}" -Protocol https -ErrorAction SilentlyContinue | Remove-WebBinding -ErrorAction SilentlyContinue
   New-WebBinding -Name "{{ iis_site_name }}" -Protocol https -Port {{ iis_https_port }} -IPAddress "*"
   $binding = Get-WebBinding -Name "{{ iis_site_name }}" -Protocol https
   $binding.AddSslCertificate("{{ old_cert_thumbprint }}", "My")
   ```
7. Verify HTTPS — `ansible.windows.win_uri`, url: `https://localhost`, validate_certs: no, return_content: yes
8. Save thumbprints — `ansible.builtin.copy`, delegate_to: localhost, dest: `vars/cert_thumbprints.yml`, content:
   ```yaml
   old_cert_thumbprint: "{{ old_cert_thumbprint }}"
   new_cert_thumbprint: "{{ new_cert_thumbprint }}"
   ```
9. Debug: display both thumbprints

## Phase 3: Rotation Playbook (`playbooks/rotate_certificate.yml`)

**Hosts:** `"{{ target_host | default('windows') }}"`
**Gather facts:** no
**Vars files:** `../vars/demo_vars.yml`
**Extra vars from EDA:** `target_host`, `cert_thumbprint`

### Tasks (in block/rescue):

**Block:**
1. Debug: "🔄 Starting certificate rotation on {{ inventory_hostname }}"
2. Verify expiring cert — `ansible.windows.win_certificate_info`, thumbprint: `{{ cert_thumbprint }}`, store_location: LocalMachine, store_name: My. Assert `certificates | length > 0` fail_msg: "Expiring certificate {{ cert_thumbprint }} not found in store"
3. Debug: "✅ Found expiring certificate: {{ cert_thumbprint }}"
4. Find replacement — `ansible.windows.win_shell`:
   ```powershell
   $certs = Get-ChildItem Cert:\LocalMachine\My | Where-Object {
       $_.Subject -like "*{{ cert_dns_name }}*" -and
       $_.Thumbprint -ne "{{ cert_thumbprint }}" -and
       $_.NotAfter -gt (Get-Date)
   } | Sort-Object NotAfter -Descending
   if ($certs) { Write-Output $certs[0].Thumbprint } else { throw "No replacement certificate found" }
   ```
   Register, parse, set_fact `new_cert_thumbprint`
5. Debug: "✅ Found replacement certificate: {{ new_cert_thumbprint }}"
6. Rebind IIS — `ansible.windows.win_shell`:
   ```powershell
   Import-Module WebAdministration
   $binding = Get-WebBinding -Name "{{ iis_site_name }}" -Protocol https
   $binding.AddSslCertificate("{{ new_cert_thumbprint }}", "My")
   ```
7. Debug: "✅ IIS HTTPS binding updated to new certificate"
8. Remove old cert — `ansible.windows.win_certificate_store`, thumbprint: `{{ cert_thumbprint }}`, state: absent, store_location: LocalMachine, store_name: My
9. Debug: "✅ Old certificate removed from store"
10. Verify HTTPS — `ansible.windows.win_uri`, url: `https://localhost`, validate_certs: no. Assert status_code == 200, success_msg: "IIS is serving HTTPS with the new certificate!"
11. Debug: "🎉 Certificate rotation complete! New cert: {{ new_cert_thumbprint }}"

**Rescue:**
- Debug: "❌ Certificate rotation FAILED: {{ ansible_failed_result.msg | default('Unknown error') }}"

## Phase 4: Verify Playbook (`playbooks/verify_certificate.yml`)

**Hosts:** windows
**Gather facts:** no

### Tasks:
1. Query all certs — `ansible.windows.win_certificate_info`, store_location: LocalMachine, store_name: My
2. Debug loop: display each cert's subject, thumbprint, not_after, friendly_name
3. Get IIS binding — `ansible.windows.win_shell`: `Import-Module WebAdministration; Get-WebBinding -Protocol https | ForEach-Object { $_.certificateHash }`
4. Debug: "Current IIS HTTPS cert: {{ binding_thumbprint }}"
5. Flag certs expiring within threshold days

## Phase 5: Monitoring Setup (`playbooks/setup_monitoring.yml`)

**Hosts:** windows
**Gather facts:** no
**Vars files:** `../vars/demo_vars.yml`
**Extra vars:** `eda_event_stream_url`

### Tasks:
1. Create `C:\Scripts` — `ansible.windows.win_file`, path: `C:\Scripts`, state: directory
2. Register event source — `ansible.windows.win_shell`:
   ```powershell
   if (-not [System.Diagnostics.EventLog]::SourceExists("CertExpiryCheck")) {
       New-EventLog -LogName Application -Source "CertExpiryCheck"
   }
   ```
3. Template monitoring script — `ansible.windows.win_template`, src: `../scripts/send_cert_event.ps1.j2`, dest: `C:\Scripts\send_cert_event.ps1`
4. Create scheduled task — `community.windows.win_scheduled_task`:
   - Name: CertExpiryCheck
   - Actions: execute `powershell.exe`, arguments: `-ExecutionPolicy Bypass -File C:\Scripts\send_cert_event.ps1`
   - Triggers: repetition interval `PT{{ cert_check_interval_minutes }}M`
   - Run as: SYSTEM
   - State: present
   - Enabled: yes
5. Debug: "Monitoring scheduled task created — runs every {{ cert_check_interval_minutes }} minutes"

## Phase 6: EDA Rulebook

### `extensions/eda/rulebooks/cert_expiry_watcher.yml`

```yaml
---
- name: Windows Certificate Expiry Watcher
  hosts: all
  sources:
    - ansible.eda.webhook:
        host: 0.0.0.0
        port: 5000

  rules:
    - name: Certificate expiring within 7 days - trigger rotation
      condition: event.payload.days_left <= 7 and event.payload.event_type == "cert_expiring"
      action:
        run_job_template:
          name: "Rotate Windows Certificate"
          organization: "Default"
          job_args:
            extra_vars:
              target_host: "{{ event.payload.host }}"
              cert_thumbprint: "{{ event.payload.thumbprint }}"
```

## Phase 7: Configure AAP (`configure_aap/configure_aap.yml`)

**Hosts:** localhost
**Connection:** local
**Gather facts:** no

### Variables:
```yaml
controller_hostname: "{{ lookup('env', 'AAP_PROTOCOL') }}://{{ lookup('env', 'AAP_HOSTNAME') }}"
controller_username: "{{ lookup('env', 'AAP_USERNAME') }}"
controller_password: "{{ lookup('env', 'AAP_PASSWORD') }}"
controller_validate_certs: "{{ lookup('env', 'AAP_VALIDATE_CERTS') | default(false) }}"
```

### Pre-tasks:
1. Assert AAP env vars are set
2. Assert `.env.demo` exists
3. Parse `.env.demo` — read `WINDOWS_PRIVATE_IP` and `WINDOWS_ADMIN_PASSWORD` using `ansible.builtin.shell`:
   ```bash
   source .env.demo && echo $WINDOWS_PRIVATE_IP
   ```
   Register and set_fact for each
4. Get Git repo URL — `ansible.builtin.command: gh repo view --json url -q .url`, register as `git_repo_url`

### Load var files:
- `vars/controller_config.yml`

### Roles:
- `infra.aap_configuration.dispatch` — applies all controller objects in dependency order

### Post-tasks (EDA Configuration):

Since `infra.aap_configuration` may not fully cover EDA objects, use `ansible.builtin.uri` for direct API calls:

1. **Create EDA Project** — POST to `{{ controller_hostname }}/api/eda/v1/projects/`:
   ```json
   {
     "name": "Windows Cert Rotation EDA",
     "url": "{{ git_repo_url }}",
     "description": "EDA rulebooks for Windows cert rotation demo"
   }
   ```
   Register project ID. Poll project status until sync is complete.

2. **Create EDA Event Stream** — POST to `{{ controller_hostname }}/api/eda/v1/external-event-streams/` (or appropriate endpoint):
   ```json
   {
     "name": "Windows Cert Expiry Stream",
     "organization_id": 1
   }
   ```
   Register response — extract the Event Stream URL from the response.
   Append `EDA_EVENT_STREAM_URL` to `.env.demo`.

3. **Get Decision Environment** — GET `{{ controller_hostname }}/api/eda/v1/decision-environments/`:
   - Find the first available DE, register its ID
   - If none exist, create one pointing to `registry.redhat.io/ansible-automation-platform-25/de-supported-rhel9:latest`

4. **Create Rulebook Activation** — POST to `{{ controller_hostname }}/api/eda/v1/activations/`:
   ```json
   {
     "name": "Windows Cert Expiry Watcher",
     "description": "Watches for cert expiry events and triggers rotation",
     "project_id": "<from step 1>",
     "rulebook_name": "cert_expiry_watcher.yml",
     "decision_environment_id": "<from step 3>",
     "is_enabled": true
   }
   ```

5. **Update send_test_event.sh** — use `ansible.builtin.template` or `ansible.builtin.lineinfile` to inject the Event Stream URL into the test script.

6. **Display summary**:
   ```
   =============================================
   ✅ AAP Configuration Complete!
   =============================================
   Controller UI: {{ controller_hostname }}
   Job Template: Rotate Windows Certificate
   EDA Rulebook Activation: Windows Cert Expiry Watcher
   Event Stream URL: {{ eda_event_stream_url }}
   
   To fire a test event:
     source .env.demo
     bash scripts/send_test_event.sh
   =============================================
   ```

**NOTE on EDA API:** The AAP 2.6 API paths for EDA may vary. The playbook should handle 401/403 errors gracefully and suggest the user check their AAP credentials. If the EDA API is not at the expected path, try alternative paths:
- `/eda/api/v1/` instead of `/api/eda/v1/`
- The gateway may proxy EDA at the same hostname

**NOTE on authentication for EDA API:** The EDA API may require the same credentials as the controller, or it may require a separate token. Try basic auth first (username/password). If that fails, try creating an OAuth2 token via the controller API and using bearer auth.

### `configure_aap/vars/controller_config.yml`

```yaml
---
controller_credentials:
  - name: "Windows Demo Credential"
    description: "Machine credential for Windows cert rotation demo"
    organization: "Default"
    credential_type: "Machine"
    inputs:
      username: "Administrator"
      password: "{{ windows_admin_password }}"

controller_inventories:
  - name: "Windows Demo Inventory"
    description: "Inventory for Windows cert rotation demo"
    organization: "Default"

controller_hosts:
  - name: "{{ windows_private_ip }}"
    inventory: "Windows Demo Inventory"
    variables:
      ansible_connection: winrm
      ansible_winrm_transport: ntlm
      ansible_winrm_server_cert_validation: ignore
      ansible_port

