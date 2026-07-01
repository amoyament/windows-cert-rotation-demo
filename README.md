# Windows Certificate Rotation Demo with AAP 2.6 and EDA

Automated demo showing event-driven certificate rotation on Windows Server using Red Hat Ansible Automation Platform (AAP) 2.6 and Event-Driven Ansible (EDA).

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
