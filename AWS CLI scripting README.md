# AWS CLI v2 — Verified Installer + Account Audit Script

A production-ready bash script for installing AWS CLI v2 with **full PGP signature verification**, **pre-installation account/credential audit**, and **automated credential management**.

Designed for infrastructure automation, system administration, and ISO 27001-compliant deployments.

---

## 📋 Table of Contents

- [Features](#features)
- [Prerequisites](#prerequisites)
- [Installation & Usage](#installation--usage)
- [What the Script Does](#what-the-script-does)
- [Credential Management Options](#credential-management-options)
- [Example Output](#example-output)
- [Report & Logging](#report--logging)
- [Troubleshooting](#troubleshooting)
- [Author & License](#author--license)

---

## ✨ Features

### 🔐 **PGP Signature Verification**
- Automatically imports AWS CLI public key
- Verifies fingerprint: `FB5D B77F D5C1 18B8 0511 ADA8 A631 0ACC 4672 475C`
- Validates ZIP integrity using GPG — ensures **zero tampering**
- Aborts installation if signature check fails

### 📊 **Pre-Installation Account Audit**
- Scans for existing AWS credentials (`~/.aws/credentials`)
- Lists all configured profiles with masked access keys (shows only first 4 + last 4 chars)
- **Live STS validation** — calls `aws sts get-caller-identity` per profile
  - Shows Account ID, User ARN, and validity status
  - Detects expired/invalid credentials before proceeding
- Displays Region, Output Format, and Session Token info per profile

### 🔄 **Intelligent Credential Management**
Four options before installation:
1. **Keep Existing** — preserve all credentials, continue install
2. **Wipe** — remove `~/.aws/` directory, fresh start
3. **Backup + Wipe** — save to `~/.aws_backup_<timestamp>`, then remove, fresh start
4. **Abort** — exit without making changes

### ✅ **Comprehensive Checks & Reporting**
- 12-point installation checklist (dependencies, downloads, verification, install, version check)
- Colored terminal output (PASS ✔, FAIL ✘, WARN ⚠, SKIP –)
- Full structured log file at `/var/log/awscli_install_<timestamp>.log`
- Final summary report with scores, credential action taken, and next steps
- Auto-detects fresh vs. update installation mode

### 🛡️ **Production-Ready**
- Root privilege check (requires `sudo`)
- Auto-installs missing dependencies (`curl`, `unzip`, `gpg`)
- Works on Ubuntu, Debian, CentOS, Amazon Linux, RHEL
- Handles `sudo` user context correctly (reads actual user's `~/.aws/`, not `/root/.aws/`)
- Safe temp directory cleanup
- ISO 27001 / Change Management compatible

---

## 📦 Prerequisites

### System Requirements
- **OS**: Ubuntu 22.04+, Debian 11+, CentOS 7+, Amazon Linux 2, RHEL 8+
- **User**: Must run as `root` or with `sudo`
- **Internet**: Access to AWS official download URLs (`awscli.amazonaws.com`)
- **Disk Space**: ~300 MB free (for download + extraction)

### Tools (Auto-Installed if Missing)
- `curl` — download installer and signature
- `unzip` — extract ZIP archive
- `gpg` — PGP signature verification

### Optional (for credential validation)
- Existing AWS CLI binary (if you want live STS checks during audit)

---

## 🚀 Installation & Usage

### Step 1: Download the Script

```bash
# Clone the repository
git clone https://github.com/arun641/AWS-Cloud_Engineer.git
cd AWS-Cloud_Engineer

# Or download directly
curl -O https://raw.githubusercontent.com/arun641/AWS-Cloud_Engineer/main/install_awscli_verified.sh
chmod +x install_awscli_verified.sh
```

### Step 2: Run the Script

```bash
# With sudo (recommended)
sudo bash install_awscli_verified.sh

# Or if already root
./install_awscli_verified.sh
```

### Step 3: Follow the Prompts

If existing credentials are found:
```
╔══════════════════════════════════════════════════════════════╗
║           EXISTING AWS CREDENTIALS DETECTED                  ║
║                                                              ║
║  [1]  Keep credentials  — continue with existing config      ║
║  [2]  Wipe credentials  — configure fresh after install      ║
║  [3]  Backup + Wipe     — backup saved, configure fresh      ║
║  [4]  Abort             — exit without installing            ║
╚══════════════════════════════════════════════════════════════╝

Enter choice [1/2/3/4]: 
```

### Step 4: Configure AWS Credentials (if not kept)

```bash
aws configure
```

Prompts:
```
AWS Access Key ID [None]: AKIA...
AWS Secret Access Key [None]: wJal...
Default region name [None]: ap-south-1
Default output format [None]: json
```

---

## 📝 What the Script Does

### Execution Flow

```
┌─────────────────────────────────────────────────┐
│  Preflight Checks                               │
│  ✓ Root privilege verify                        │
│  ✓ Dependency check (curl, unzip, gpg)          │
│  ✓ Detect existing CLI binary                   │
└─────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────┐
│  AWS Account & Credential Audit                 │
│  ✓ Scan ~/.aws/credentials for profiles         │
│  ✓ Mask access keys (show first 4 + last 4)    │
│  ✓ Live STS identity check per profile          │
│  ✓ Show Account ID, ARN, validity status        │
└─────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────┐
│  Credential Management Decision                 │
│  ✓ Prompt: Keep / Wipe / Backup+Wipe / Abort   │
│  ✓ Execute user choice                          │
└─────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────┐
│  Download & Verify                              │
│  ✓ Download ZIP from awscli.amazonaws.com       │
│  ✓ Download .sig (signature file)               │
│  ✓ Import AWS public PGP key                    │
│  ✓ Verify fingerprint                           │
│  ✓ Validate ZIP signature                       │
└─────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────┐
│  Installation                                   │
│  ✓ Extract ZIP to /tmp/                         │
│  ✓ Run installer (fresh or update mode)         │
│  ✓ Binary installed to /usr/local/aws-cli       │
│  ✓ Symlink created at /usr/local/bin/aws        │
└─────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────┐
│  Post-Install Verification                      │
│  ✓ Confirm aws --version                        │
│  ✓ Check credentials file existence             │
└─────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────┐
│  Final Report & Cleanup                         │
│  ✓ Print colorized summary report               │
│  ✓ Log to /var/log/awscli_install_*.log         │
│  ✓ Remove temp files                            │
└─────────────────────────────────────────────────┘
```

---

## 🔐 Credential Management Options

### Option 1: Keep Existing
**Use when:** Updating CLI binary while keeping current AWS account credentials.
```bash
[1]  Keep credentials  — continue with existing config
```
- No changes to `~/.aws/credentials` or `~/.aws/config`
- Existing profiles remain active post-install
- **Useful for**: Production environments, scheduled updates

### Option 2: Wipe
**Use when:** Starting fresh, removing all old credentials.
```bash
[2]  Wipe credentials  — configure fresh after install
```
- Removes entire `~/.aws/` directory
- Forces `aws configure` after install
- **Useful for**: Clean machines, credential rotation, new setups
- **Warning**: No backup — use with caution

### Option 3: Backup + Wipe
**Use when:** Safe credential rotation with recovery option.
```bash
[3]  Backup + Wipe     — backup saved, configure fresh
```
- Copies `~/.aws/` to `~/.aws_backup_<YYYYMMDD_HHMMSS>`
- Removes original `~/.aws/` directory
- Can restore from backup: `cp -r ~/.aws_backup_* ~/.aws/`
- **Useful for**: Production systems (ISO 27001 compliant), audit trails
- **Recommended**: Most secure option for infrastructure management

### Option 4: Abort
**Use when:** You changed your mind or need to investigate first.
```bash
[4]  Abort             — exit without installing
```
- No changes made to system or credentials
- Script exits cleanly
- Can run again later

---

## 📊 Example Output

### Running the Script

```bash
$ sudo bash install_awscli_verified.sh

╔════════════════════════════════════════════════════════════╗
║      AWS CLI v2 — Verified Installer + Account Audit       ║
╚════════════════════════════════════════════════════════════╝
  Started   : Wednesday 13 May 2026 04:07:54 PM IST
  Log file  : /var/log/awscli_install_20260513_160754.log
  Host      : AM-LT-23-0096
  User      : root

━━━  PREFLIGHT CHECKS
[PASS]   curl found → /usr/bin/curl
[PASS]   unzip found → /usr/bin/unzip
[PASS]   gpg found → /usr/bin/gpg
[WARN]   Existing AWS CLI binary detected: aws-cli/2.34.45

━━━  AWS ACCOUNT & CREDENTIAL AUDIT
  Scanning: /home/arunkumar/.aws
  ─────────────────────────────────────────────────────────
[INFO]   No credentials file at /home/arunkumar/.aws/credentials — clean machine

━━━  DOWNLOADING INSTALLER
[PASS]   ZIP downloaded → /tmp/awscli_install_20260513_160754/awscliv2.zip (67M)
[PASS]   Signature downloaded → /tmp/awscli_install_20260513_160754/awscliv2.sig

━━━  PGP SIGNATURE VERIFICATION
[PASS]   Key fingerprint verified: FB5DB77FD5C118B80511ADA8A6310ACC4672475C
[PASS]   PGP Signature: VALID — ZIP is authentic and untampered

━━━  INSTALLING AWS CLI v2
[PASS]   AWS CLI installed to /usr/local/aws-cli

━━━  POST-INSTALL VERIFICATION
[PASS]   Version confirmed: aws-cli/2.34.45 Python/3.14.4 Linux/6.8.0
[WARN]   No AWS credentials found — run 'aws configure' to set up

━━━  CLEANUP
[PASS]   Temp files removed: /tmp/awscli_install_20260513_160754
```

### With Existing Credentials

```
━━━  AWS ACCOUNT & CREDENTIAL AUDIT
  Scanning: /home/arunkumar/.aws
  ─────────────────────────────────────────────────────────
  Found 2 profile(s) in credentials file

  ┌─ Profile: [default]
  │  Access Key ID    :  AKIA****WXYZ
  │  Secret Key       :  **************************
  │  Session Token    :  No
  │  Region           :  ap-south-1
  │  Output Format    :  json
  │  Calling sts get-caller-identity...
  │  Identity Check   :  ✔ ACTIVE & VALID
  │  Account ID       :  123456789012
  │  User ID          :  AIDAXXXXXXXXXXXXXXXXXX
  │  ARN              :  arn:aws:iam::123456789012:user/arun
  └──────────────────────────────────────────────────────

  ┌─ Profile: [prod-account]
  │  Access Key ID    :  AKIA****ABCD
  │  Secret Key       :  **************************
  │  Session Token    :  Yes (temporary/STS token present)
  │  Region           :  us-east-1
  │  Output Format    :  (not set)
  │  Calling sts get-caller-identity...
  │  Identity Check   :  ✔ ACTIVE & VALID
  │  Account ID       :  987654321098
  │  User ID          :  AIDAYYYYYYYYYYYYYYYYY
  │  ARN              :  arn:aws:iam::987654321098:role/cross-account-role
  └──────────────────────────────────────────────────────

╔══════════════════════════════════════════════════════════════╗
║           EXISTING AWS CREDENTIALS DETECTED                  ║
║  [1]  Keep credentials  — continue with existing config      ║
║  [2]  Wipe credentials  — configure fresh after install      ║
║  [3]  Backup + Wipe     — backup saved, configure fresh      ║
║  [4]  Abort             — exit without installing            ║
╚══════════════════════════════════════════════════════════════╝

Enter choice [1/2/3/4]: 3
[WARN]   Choice [3]: Backing up to /home/arunkumar/.aws_backup_20260513_160754 then wiping
[PASS]   Backup saved: /home/arunkumar/.aws_backup_20260513_160754
[PASS]   Original credentials removed: /home/arunkumar/.aws
```

### Final Report

```
╔════════════════════════════════════════════════════════════╗
║              INSTALLATION REPORT SUMMARY                   ║
╚════════════════════════════════════════════════════════════╝
  Timestamp         : Wednesday 13 May 2026 04:08:06 PM IST
  Host              : AM-LT-23-0096
  Install Mode      : UPDATE
  Credential Action : NONE
  Account Audit     : No existing credentials — clean machine
  Log File          : /var/log/awscli_install_20260513_160754.log

  CHECK RESULTS:
  ┌───────────────────────────────────────────────────────────┐
  │  ✔ PASS  GPG tool available
  │  ✔ PASS  curl tool available
  │  ✔ PASS  unzip tool available
  │  ✔ PASS  Existing AWS account/profile audit
  │  ✔ PASS  Credential action decision
  │  ✔ PASS  Installer ZIP downloaded
  │  ✔ PASS  Signature (.sig) downloaded
  │  ✔ PASS  AWS PGP key imported + fingerprint matched
  │  ✔ PASS  PGP signature verification (ZIP authentic)
  │  ✔ PASS  AWS CLI installed successfully
  │  ✔ PASS  aws --version confirmed
  │  ⚠ WARN  AWS credentials configured
  └───────────────────────────────────────────────────────────┘

  SCORE :  11 PASS  │  0 FAIL  │  1 WARN  │  0 SKIP

  CREDENTIAL ACTION TAKEN:
  →  No prior credentials existed — run: aws configure

  INSTALLED VERSION  :  aws-cli/2.34.45 Python/3.14.4 Linux/6.8.0
  BINARY PATH        :  /usr/local/bin/aws

  RESULT: INSTALLATION SUCCESSFUL ✔

  Next step → run:  aws configure
    Prompts for:
      AWS Access Key ID     : <your key>
      AWS Secret Access Key : <your secret>
      Default region        : ap-south-1  (Mumbai)
      Default output format : json

════════════════════════════════════════════════════════════
  Full log saved to: /var/log/awscli_install_20260513_160754.log
════════════════════════════════════════════════════════════
```

---

## 📄 Report & Logging

### Log File Location
```
/var/log/awscli_install_<YYYYMMDD_HHMMSS>.log
```

**Example:** `/var/log/awscli_install_20260513_160754.log`

### View Full Log
```bash
# View last install log
ls -lh /var/log/awscli_install_*.log | tail -1

# Cat the file
cat /var/log/awscli_install_20260513_160754.log

# Watch in real-time (if script is running)
tail -f /var/log/awscli_install_*.log
```

### Log Contents
- All console output (PASS/FAIL/WARN/SKIP)
- PGP key import details
- GPG signature verification output
- Installer command output
- Errors (if any)
- Timestamps for compliance/audit trail

### Audit Trail Usage
Perfect for:
- **ISO 27001 / ISO 27002** compliance documentation
- **Change Management** (CAB approval records)
- **Security Audits** (who installed CLI, when, with what verification)
- **Infrastructure as Code** (IaC) pipeline logs
- **Incident Response** (troubleshooting, root cause analysis)

---

## 🔧 Troubleshooting

### Issue: Script requires root but you forgot sudo

**Error:**
```
[FAIL]   Script must be run as root. Use: sudo bash $0
```

**Solution:**
```bash
sudo bash install_awscli_verified.sh
```

---

### Issue: Network error downloading ZIP

**Error:**
```
[FAIL]   Failed to download ZIP from https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip
```

**Solutions:**
1. Check internet connectivity:
   ```bash
   ping awscli.amazonaws.com
   ```
2. Check DNS:
   ```bash
   nslookup awscli.amazonaws.com
   ```
3. Check if firewall is blocking:
   ```bash
   curl -I https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip
   ```
4. Try manual download:
   ```bash
   curl -O https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip
   ```

---

### Issue: PGP verification failed

**Error:**
```
[FAIL]   PGP VERIFICATION FAILED — do not proceed. Check log: /var/log/awscli_install_*.log
```

**Causes & Solutions:**
1. **Corrupted ZIP**: Re-download
   ```bash
   rm -f /tmp/awscli_install_*/awscliv2.zip
   sudo bash install_awscli_verified.sh
   ```
2. **Man-in-the-middle (MITM)**: Check network security
   ```bash
   openssl s_client -connect awscli.amazonaws.com:443
   ```
3. **GPG issue**: Reinstall GPG
   ```bash
   sudo apt-get remove --purge gnupg
   sudo apt-get install gnupg
   sudo bash install_awscli_verified.sh
   ```

---

### Issue: aws --version returns empty after install

**Error:**
```
[FAIL]   aws --version returned empty output
```

**Solutions:**
1. Check binary exists:
   ```bash
   which aws
   ls -la /usr/local/bin/aws
   ls -la /usr/local/aws-cli/v2/current/bin/aws
   ```
2. Restart terminal session:
   ```bash
   exec bash
   aws --version
   ```
3. Check PATH:
   ```bash
   echo $PATH
   # Should include /usr/local/bin
   ```
4. Manual test:
   ```bash
   /usr/local/bin/aws --version
   ```

---

### Issue: Credentials won't configure

**Problem:** After `aws configure`, credentials aren't working

**Debug:**
```bash
# Check credentials file exists
cat ~/.aws/credentials

# Check permissions (must be readable)
ls -la ~/.aws/

# Test with a simple command
aws sts get-caller-identity --region ap-south-1

# If error, check:
aws configure list   # Shows current config
```

---

### Issue: STS identity check shows "INVALID / EXPIRED"

**Problem:** During account audit, a profile shows expired credentials

**Meaning:** The access key is no longer valid (expired, revoked, or deleted from AWS)

**Solution:**
1. Regenerate access key in AWS IAM Console
2. Update locally:
   ```bash
   aws configure --profile <profile_name>
   ```
3. Or delete and reconfigure:
   ```bash
   rm ~/.aws/credentials
   aws configure
   ```

---

### Issue: Permission denied on /var/log/

**Error:**
```
bash: /var/log/awscli_install_*.log: Permission denied
```

**Solution:**
Make sure you're running with `sudo`:
```bash
sudo bash install_awscli_verified.sh
```

---

## 🛠️ Advanced Usage

### Non-Interactive Mode (for automation)

You can pass credential action as environment variable:

```bash
# Keep existing (option 1)
CRED_ACTION=1 sudo bash install_awscli_verified.sh

# Wipe (option 2)
CRED_ACTION=2 sudo bash install_awscli_verified.sh

# Backup + Wipe (option 3)
CRED_ACTION=3 sudo bash install_awscli_verified.sh
```

*Note: This requires modifying the script to accept ENV var. Current version is interactive.*

---

### Integration with Infrastructure Tools

#### Ansible Playbook
```yaml
- name: Install AWS CLI v2
  hosts: all
  become: yes
  tasks:
    - name: Download installer script
      get_url:
        url: https://raw.githubusercontent.com/arun641/AWS-Cloud_Engineer/main/install_awscli_verified.sh
        dest: /tmp/install_awscli_verified.sh
        mode: '0755'

    - name: Run AWS CLI installer
      shell: bash /tmp/install_awscli_verified.sh
      register: awscli_install
      changed_when: "'SUCCESSFUL' in awscli_install.stdout"

    - name: Verify installation
      shell: aws --version
      register: aws_version
      
    - name: Print version
      debug:
        msg: "{{ aws_version.stdout }}"
```

#### Terraform
```hcl
resource "null_resource" "install_awscli" {
  provisioner "local-exec" {
    command = "sudo bash ${path.module}/install_awscli_verified.sh"
  }
}
```

---

## 📋 Supported Operating Systems

| OS | Version | Status |
|---|---|---|
| Ubuntu | 22.04, 24.04 | ✅ Tested |
| Debian | 11, 12 | ✅ Tested |
| Amazon Linux | 2, 2023 | ✅ Supported |
| CentOS | 7, 8, 9 | ✅ Supported |
| RHEL | 8, 9 | ✅ Supported |
| Fedora | 38, 39, 40 | ✅ Supported |

---

## 🔑 Security Considerations

### Why PGP Verification?
- **Supply Chain Security**: Ensures AWS CLI ZIP hasn't been intercepted or modified
- **Authenticity**: Confirms the binary is genuinely from Amazon Web Services
- **Zero Trust**: No assumptions — cryptographic proof required
- **Compliance**: Meets ISO 27001 / SOC 2 requirements for software integrity verification

### Credential Security
- Access keys are **masked** during display (first 4 + last 4 chars only)
- Secret keys shown as `**` (never displayed)
- Backup feature uses timestamp (e.g., `~/.aws_backup_20260513_160754`)
- Script runs as root but respects actual user's `~/.aws/` directory

### Network Security
- Uses HTTPS for all downloads
- Verifies fingerprint (`FB5D B77F D5C1 18B8...`)
- Validates signature against AWS public key
- No third-party mirrors or CDNs

---

## 📞 Support & Contributions

### Issues or Questions?
1. Check **Troubleshooting** section above
2. Review log file: `/var/log/awscli_install_*.log`
3. Open GitHub Issue: [AWS-Cloud_Engineer Issues](https://github.com/arun641/AWS-Cloud_Engineer/issues)

### Want to Contribute?
1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-improvement`
3. Commit changes: `git commit -m 'Add feature'`
4. Push to branch: `git push origin feature/my-improvement`
5. Open Pull Request

### Improvements Welcome
- Platform-specific optimizations
- Additional credential audit checks
- Terraform/Ansible integration examples
- Non-interactive mode support

---

## 📜 Author & License

**Author:** Arun Kumar  
**Organization:** ATI Motors Pvt. Ltd., Bengaluru  
**Role:** System Administrator  
**Repository:** [arun641/AWS-Cloud_Engineer](https://github.com/arun641/AWS-Cloud_Engineer)

**License:** MIT  
Free to use, modify, and distribute in compliance with MIT terms.

---

## 📚 Additional Resources

- [AWS CLI Official Documentation](https://docs.aws.amazon.com/cli/latest/userguide/)
- [AWS CLI v2 GitHub](https://github.com/aws/aws-cli)
- [GnuPG Documentation](https://www.gnupg.org/documentation/)
- [ISO 27001 Compliance Guide](https://www.iso.org/isoiec-27001-information-security-management.html)

---

**Last Updated:** May 13, 2026  
**Version:** 1.0  
**Status:** Production Ready ✅
