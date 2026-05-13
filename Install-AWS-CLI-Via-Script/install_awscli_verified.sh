#!/usr/bin/env bash
# =============================================================================
#  install_awscli_verified.sh
#  AWS CLI v2 Installer — PGP Verified + Pre-install Account Audit
#  Author  : Arun (ATI Motors - SysAdmin)
#  Usage   : sudo bash install_awscli_verified.sh
#  Output  : /var/log/awscli_install_<timestamp>.log + console summary
# =============================================================================

set -euo pipefail

# ── Colour palette ─────────────────────────────────────────────────────────────
RED='\033[0;31m';  GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m';     RESET='\033[0m'
DIM='\033[2m';     MAGENTA='\033[0;35m'

# ── Config ─────────────────────────────────────────────────────────────────────
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
WORKDIR="/tmp/awscli_install_${TIMESTAMP}"
LOG_FILE="/var/log/awscli_install_${TIMESTAMP}.log"
INSTALL_DIR="/usr/local/aws-cli"
BIN_DIR="/usr/local/bin"

ZIP_URL="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
SIG_URL="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip.sig"
ZIP_FILE="${WORKDIR}/awscliv2.zip"
SIG_FILE="${WORKDIR}/awscliv2.sig"
KEY_FILE="${WORKDIR}/aws-cli-public.asc"

AWS_KEY_ID="A6310ACC4672475C"
AWS_KEY_FINGERPRINT="FB5DB77FD5C118B80511ADA8A6310ACC4672475C"

# ── Report tracking ────────────────────────────────────────────────────────────
declare -A CHECKS
CHECKS=(
  [gpg_available]="SKIP"
  [curl_available]="SKIP"
  [unzip_available]="SKIP"
  [account_audit]="SKIP"
  [credential_action]="SKIP"
  [zip_downloaded]="SKIP"
  [sig_downloaded]="SKIP"
  [key_imported]="SKIP"
  [pgp_verified]="SKIP"
  [install_success]="SKIP"
  [version_confirmed]="SKIP"
  [aws_configured]="SKIP"
)

INSTALL_MODE="fresh"
INSTALLED_VERSION=""
ERRORS=()
CRED_ACTION="none"        # none | kept | wiped | backed_up_and_wiped
AUDIT_PROFILES=()
AUDIT_SUMMARY=""

# =============================================================================
#  Helpers
# =============================================================================

log()    { echo -e "${1}" | tee -a "${LOG_FILE}"; }
info()   { log "${CYAN}[INFO]${RESET}   ${1}"; }
ok()     { log "${GREEN}[PASS]${RESET}   ${1}"; }
warn()   { log "${YELLOW}[WARN]${RESET}   ${1}"; }
fail()   { log "${RED}[FAIL]${RESET}   ${1}"; ERRORS+=("${1}"); }
step()   { log "\n${BOLD}━━━  ${1}${RESET}"; }

mark() {
  local key="${1}" status="${2}"
  CHECKS["${key}"]="${status}"
}

abort() {
  fail "${1}"
  log "\n${RED}${BOLD}Installation aborted. Check log: ${LOG_FILE}${RESET}"
  print_report
  exit 1
}

mask_key() {
  # Show first 4 + last 4 chars, mask the rest
  local key="${1}"
  local len="${#key}"
  if [[ "${len}" -gt 8 ]]; then
    echo "${key:0:4}$(printf '*%.0s' $(seq 1 $((len-8))))${key: -4}"
  else
    echo "****"
  fi
}

# =============================================================================
#  Step 0 – Banner + Preflight
# =============================================================================
mkdir -p "${WORKDIR}"
touch "${LOG_FILE}"

log ""
log "${BOLD}${CYAN}╔════════════════════════════════════════════════════════════╗${RESET}"
log "${BOLD}${CYAN}║      AWS CLI v2 — Verified Installer + Account Audit       ║${RESET}"
log "${BOLD}${CYAN}╚════════════════════════════════════════════════════════════╝${RESET}"
log "  Started   : $(date)"
log "  Log file  : ${LOG_FILE}"
log "  Host      : $(hostname -f 2>/dev/null || hostname)"
log "  User      : $(whoami)"

step "PREFLIGHT CHECKS"

# Root check
if [[ "${EUID}" -ne 0 ]]; then
  abort "Script must be run as root. Use: sudo bash $0"
fi
info "Running as root — OK"

# Dependency checks
for tool in curl unzip gpg; do
  if command -v "${tool}" &>/dev/null; then
    ok "${tool} found → $(command -v ${tool})"
    mark "${tool}_available" "PASS"
  else
    info "Installing missing dependency: ${tool}"
    if command -v apt-get &>/dev/null; then
      apt-get install -y "${tool}" >> "${LOG_FILE}" 2>&1 \
        && mark "${tool}_available" "PASS" \
        || abort "${tool} could not be installed"
    elif command -v yum &>/dev/null; then
      yum install -y "${tool}" >> "${LOG_FILE}" 2>&1 \
        && mark "${tool}_available" "PASS" \
        || abort "${tool} could not be installed"
    else
      abort "Cannot install ${tool}: no supported package manager found"
    fi
    ok "${tool} installed successfully"
  fi
done

# Detect CLI binary
if command -v aws &>/dev/null; then
  EXISTING_VER=$(aws --version 2>&1 | awk '{print $1}')
  warn "Existing AWS CLI binary detected: ${EXISTING_VER}"
  INSTALL_MODE="update"
else
  info "No existing AWS CLI binary — performing fresh install"
fi

# =============================================================================
#  Step 1 – AWS ACCOUNT / CREDENTIAL AUDIT
# =============================================================================
step "AWS ACCOUNT & CREDENTIAL AUDIT"

# Resolve real home dir (sudo shifts HOME to /root)
REAL_HOME="${HOME}"
if [[ -n "${SUDO_USER:-}" ]]; then
  REAL_HOME=$(getent passwd "${SUDO_USER}" | cut -d: -f6)
fi
AWS_CRED_FILE="${REAL_HOME}/.aws/credentials"
AWS_CONF_FILE="${REAL_HOME}/.aws/config"
AWS_DIR="${REAL_HOME}/.aws"

log ""
log "  ${BOLD}Scanning: ${AWS_DIR}${RESET}"
log "  ${DIM}─────────────────────────────────────────────────────────${RESET}"

FOUND_CREDS=false
PROFILE_COUNT=0

if [[ -f "${AWS_CRED_FILE}" ]]; then
  FOUND_CREDS=true

  # Parse all profile names
  mapfile -t AUDIT_PROFILES < <(grep '^\[' "${AWS_CRED_FILE}" | tr -d '[]')
  PROFILE_COUNT="${#AUDIT_PROFILES[@]}"
  log "  ${GREEN}Found ${PROFILE_COUNT} profile(s) in credentials file${RESET}"
  log ""

  for profile in "${AUDIT_PROFILES[@]}"; do

    # Read value from credentials file for this profile
    get_cred_val() {
      awk -v prof="[$1]" -v key="$2" '
        /^\[/ { in_block = ($0 == prof) }
        in_block && $0 ~ "^"key" *=" {
          split($0, a, "="); gsub(/^[ \t]+|[ \t]+$/, "", a[2]); print a[2]; exit
        }
      ' "${AWS_CRED_FILE}"
    }

    # Read value from config file for this profile
    get_conf_val() {
      awk -v prof="[profile $1]" -v altprof="[$1]" -v key="$2" '
        /^\[/ { in_block = ($0 == prof || $0 == altprof) }
        in_block && $0 ~ "^"key" *=" {
          split($0, a, "="); gsub(/^[ \t]+|[ \t]+$/, "", a[2]); print a[2]; exit
        }
      ' "${AWS_CONF_FILE}" 2>/dev/null || true
    }

    ACCESS_KEY=$(get_cred_val "${profile}" "aws_access_key_id")
    SESSION_TK=$(get_cred_val "${profile}" "aws_session_token")
    REGION=$(get_conf_val "${profile}" "region")
    OUTPUT=$(get_conf_val "${profile}" "output")

    [[ -z "${REGION}" ]]  && REGION="(not set)"
    [[ -z "${OUTPUT}" ]]  && OUTPUT="(not set)"
    [[ -z "${ACCESS_KEY}" ]] && ACCESS_KEY="(not found)"

    MASKED_KEY=$(mask_key "${ACCESS_KEY}")
    HAS_SESSION="No"
    [[ -n "${SESSION_TK}" ]] && HAS_SESSION="Yes (temporary/STS token present)"

    log "  ${BOLD}${CYAN}┌─ Profile: [${profile}]${RESET}"
    log "  ${CYAN}│${RESET}  Access Key ID    : ${YELLOW}${MASKED_KEY}${RESET}"
    log "  ${CYAN}│${RESET}  Secret Key       : ${YELLOW}**************************${RESET}"
    log "  ${CYAN}│${RESET}  Session Token    : ${HAS_SESSION}"
    log "  ${CYAN}│${RESET}  Region           : ${REGION}"
    log "  ${CYAN}│${RESET}  Output Format    : ${OUTPUT}"

    # Live identity via STS
    log "  ${CYAN}│${RESET}  ${DIM}Calling sts get-caller-identity...${RESET}"
    STS_OUT=""
    if command -v aws &>/dev/null; then
      if [[ "${profile}" == "default" ]]; then
        STS_OUT=$(aws sts get-caller-identity --output text 2>&1) || true
      else
        STS_OUT=$(aws sts get-caller-identity --profile "${profile}" --output text 2>&1) || true
      fi
    else
      STS_OUT="SKIP_NO_CLI"
    fi

    if [[ "${STS_OUT}" == "SKIP_NO_CLI" ]]; then
      log "  ${CYAN}│${RESET}  Identity Check   : ${YELLOW}⚠ Skipped (aws binary not installed yet)${RESET}"
    elif echo "${STS_OUT}" | grep -qiE "not authorized|InvalidClientToken|ExpiredToken|NoCredentials|AccessDenied|error"; then
      log "  ${CYAN}│${RESET}  Identity Check   : ${RED}✘ INVALID / EXPIRED / NO ACCESS${RESET}"
      log "  ${CYAN}│${RESET}  ${DIM}${STS_OUT}${RESET}"
    else
      ACCT_ID=$(echo "${STS_OUT}" | awk 'NR==1{print $1}')
      USER_ID=$(echo "${STS_OUT}" | awk 'NR==1{print $2}')
      ARN=$(echo "${STS_OUT}"     | awk 'NR==1{print $3}')
      log "  ${CYAN}│${RESET}  Identity Check   : ${GREEN}✔ ACTIVE & VALID${RESET}"
      log "  ${CYAN}│${RESET}  Account ID       : ${GREEN}${ACCT_ID}${RESET}"
      log "  ${CYAN}│${RESET}  User ID          : ${GREEN}${USER_ID}${RESET}"
      log "  ${CYAN}│${RESET}  ARN              : ${GREEN}${ARN}${RESET}"
    fi

    log "  ${CYAN}└──────────────────────────────────────────────────────${RESET}"
    log ""
  done

  mark "account_audit" "PASS"
  AUDIT_SUMMARY="${PROFILE_COUNT} profile(s) found in ${AWS_DIR}"

else
  info "No credentials file at ${AWS_CRED_FILE} — clean machine"
  mark "account_audit" "PASS"
  AUDIT_SUMMARY="No existing credentials — clean machine"
fi

# =============================================================================
#  Step 2 – CREDENTIAL ACTION PROMPT
# =============================================================================

if [[ "${FOUND_CREDS}" == "true" ]]; then

  log ""
  log "${BOLD}${YELLOW}╔══════════════════════════════════════════════════════════════╗${RESET}"
  log "${BOLD}${YELLOW}║           EXISTING AWS CREDENTIALS DETECTED                  ║${RESET}"
  log "${BOLD}${YELLOW}║                                                              ║${RESET}"
  log "${BOLD}${YELLOW}║  What would you like to do before installation?              ║${RESET}"
  log "${BOLD}${YELLOW}║                                                              ║${RESET}"
  log "${BOLD}${YELLOW}║  [1]  Keep credentials  — continue with existing config      ║${RESET}"
  log "${BOLD}${YELLOW}║  [2]  Wipe credentials  — configure fresh after install      ║${RESET}"
  log "${BOLD}${YELLOW}║  [3]  Backup + Wipe     — backup saved, configure fresh      ║${RESET}"
  log "${BOLD}${YELLOW}║  [4]  Abort             — exit without installing             ║${RESET}"
  log "${BOLD}${YELLOW}╚══════════════════════════════════════════════════════════════╝${RESET}"
  log ""

  while true; do
    read -rp "$(echo -e "  ${BOLD}Enter choice [1/2/3/4]:${RESET} ")" CHOICE
    case "${CHOICE}" in
      1)
        info "Choice [1]: Keeping existing credentials — proceeding"
        CRED_ACTION="kept"
        mark "credential_action" "PASS"
        break
        ;;
      2)
        warn "Choice [2]: Wiping credentials at ${AWS_DIR}"
        rm -rf "${AWS_DIR}"
        ok "Credentials removed: ${AWS_DIR}"
        CRED_ACTION="wiped"
        mark "credential_action" "PASS"
        break
        ;;
      3)
        BACKUP_PATH="${AWS_DIR}_backup_${TIMESTAMP}"
        info "Choice [3]: Backing up to ${BACKUP_PATH} then wiping"
        cp -r "${AWS_DIR}" "${BACKUP_PATH}"
        ok "Backup saved: ${BACKUP_PATH}"
        rm -rf "${AWS_DIR}"
        ok "Original credentials removed: ${AWS_DIR}"
        CRED_ACTION="backed_up_and_wiped"
        mark "credential_action" "PASS"
        break
        ;;
      4)
        warn "Choice [4]: User chose to abort. No changes made."
        mark "credential_action" "WARN"
        ERRORS+=("User aborted at credential decision step")
        print_report
        exit 0
        ;;
      *)
        warn "Invalid input '${CHOICE}'. Please enter 1, 2, 3, or 4."
        ;;
    esac
  done

else
  CRED_ACTION="none"
  mark "credential_action" "PASS"
fi

# =============================================================================
#  Step 3 – Download ZIP + Signature
# =============================================================================
step "DOWNLOADING INSTALLER"

info "Downloading AWS CLI ZIP..."
if curl -fsSL "${ZIP_URL}" -o "${ZIP_FILE}" >> "${LOG_FILE}" 2>&1; then
  ZIP_SIZE=$(du -sh "${ZIP_FILE}" | cut -f1)
  ok "ZIP downloaded → ${ZIP_FILE} (${ZIP_SIZE})"
  mark "zip_downloaded" "PASS"
else
  abort "Failed to download ZIP from ${ZIP_URL}"
fi

info "Downloading signature file..."
if curl -fsSL "${SIG_URL}" -o "${SIG_FILE}" >> "${LOG_FILE}" 2>&1; then
  ok "Signature downloaded → ${SIG_FILE}"
  mark "sig_downloaded" "PASS"
else
  abort "Failed to download signature from ${SIG_URL}"
fi

# =============================================================================
#  Step 4 – PGP Verification
# =============================================================================
step "PGP SIGNATURE VERIFICATION"

cat > "${KEY_FILE}" << 'AWSPGPKEY'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBF2Cr7UBEADJZHcgusOJl7ENSyumXh85z0TRV0xJorM2B/JL0kHOyigQluUG
ZMLhENaG0bYatdrKP+3H91lvK050pXwnO/R7fB/FSTouki4ciIx5OuLlnJZIxSzx
PqGl0mkxImLNbGWoi6Lto0LYxqHN2iQtzlwTVmq9733zd3XfcXrZ3+LblHAgEt5G
TfNxEKJ8soPLyWmwDH6HWCnjZ/aIQRBTIQ05uVeEoYxSh6wOai7ss/KveoSNBbYz
gbdzoqI2Y8cgH2nbfgp3DSasaLZEdCSsIsK1u05CinE7k2qZ7KgKAUIcT/cR/grk
C6VwsnDU0OUCideXcQ8WeHutqvgZH1JgKDbznoIzeQHJD238GEu+eKhRHcz8/jeG
94zkcgJOz3KbZGYMiTh277Fvj9zzvZsbMBCedV1BTg3TqgvdX4bdkhf5cH+7NtWO
lrFj6UwAsGukBTAOxC0l/dnSmZhJ7Z1KmEWilro/gOrjtOxqRQutlIqG22TaqoPG
fYVN+en3Zwbt97kcgZDwqbuykNt64oZWc4XKCa3mprEGC3IbJTBFqglXmZ7l9ywG
EEUJYOlb2XrSuPWml39beWdKM8kzr1OjnlOm6+lpTRCBfo0wa9F8YZRhHPAkwKkX
XDeOGpWRj4ohOx0d2GWkyV5xyN14p2tQOCdOODmz80yUTgRpPVQUtOEhXQARAQAB
tCFBV1MgQ0xJIFRlYW0gPGF3cy1jbGlAYW1hem9uLmNvbT6JAlQEEwEIAD4CGwMF
CwkIBwIGFQoJCAsCBBYCAwECHgECF4AWIQT7Xbd/1cEYuAURraimMQrMRnJHXAUC
aGveYQUJDMpiLAAKCRCmMQrMRnJHXKBYD/9Ab0qQdGiO5hObchG8xh8Rpb4Mjyf6
0JrVo6m8GNjNj6BHkSc8fuTQJ/FaEhaQxj3pjZ3GXPrXjIIVChmICLlFuRXYzrXc
Pw0lniybypsZEVai5kO0tCNBCCFuMN9RsmmRG8mf7lC4FSTbUDmxG/QlYK+0IV/l
uJkzxWa+rySkdpm0JdqumjegNRgObdXHAQDWlubWQHWyZyIQ2B4U7AxqSpcdJp6I
S4Zds4wVLd1WE5pquYQ8vS2cNlDm4QNg8wTj58e3lKN47hXHMIb6CHxRnb947oJa
pg189LLPR5koh+EorNkA1wu5mAJtJvy5YMsppy2y/kIjp3lyY6AmPT1posgGk70Z
CmToEZ5rbd7ARExtlh76A0cabMDFlEHDIK8RNUOSRr7L64+KxOUegKBfQHb9dADY
qqiKqpCbKgvtWlds909Ms74JBgr2KwZCSY1HaOxnIr4CY43QRqAq5YHOay/mU+6w
hhmdF18vpyK0vfkvvGresWtSXbag7Hkt3XjaEw76BzxQH21EBDqU8WJVjHgU6ru+
DJTs+SxgJbaT3hb/vyjlw0lK+hFfhWKRwgOXH8vqducF95NRSUxtS4fpqxWVaw3Q
V2OWSjbne99A5EPEySzryFTKbMGwaTlAwMCwYevt4YT6eb7NmFhTx0Fis4TalUs+
j+c7Kg92pDx2uQ==
=OBAt
-----END PGP PUBLIC KEY BLOCK-----
AWSPGPKEY

info "Importing AWS CLI PGP public key..."
GPG_HOME=$(mktemp -d)
GNUPGHOME="${GPG_HOME}" gpg --batch --import "${KEY_FILE}" >> "${LOG_FILE}" 2>&1

IMPORTED_FP=$(GNUPGHOME="${GPG_HOME}" gpg --fingerprint --with-colons "${AWS_KEY_ID}" 2>/dev/null \
  | grep "^fpr" | head -1 | cut -d: -f10 | tr -d ' ')

if [[ "${IMPORTED_FP}" == "${AWS_KEY_FINGERPRINT}" ]]; then
  ok "Key fingerprint verified: ${IMPORTED_FP}"
  mark "key_imported" "PASS"
else
  abort "Key fingerprint MISMATCH! Expected ${AWS_KEY_FINGERPRINT}, got ${IMPORTED_FP}"
fi

info "Verifying ZIP signature against AWS public key..."
GPG_VERIFY_OUT=$(GNUPGHOME="${GPG_HOME}" gpg --verify "${SIG_FILE}" "${ZIP_FILE}" 2>&1)
echo "${GPG_VERIFY_OUT}" >> "${LOG_FILE}"

if echo "${GPG_VERIFY_OUT}" | grep -q "Good signature"; then
  ok "PGP Signature: VALID — ZIP is authentic and untampered"
  mark "pgp_verified" "PASS"
else
  abort "PGP VERIFICATION FAILED — do not proceed. Check log: ${LOG_FILE}"
fi
rm -rf "${GPG_HOME}"

# =============================================================================
#  Step 5 – Install
# =============================================================================
step "INSTALLING AWS CLI v2"

info "Extracting ZIP..."
unzip -q -o "${ZIP_FILE}" -d "${WORKDIR}" >> "${LOG_FILE}" 2>&1

info "Running installer (mode: ${INSTALL_MODE})..."
if [[ "${INSTALL_MODE}" == "update" ]]; then
  "${WORKDIR}/aws/install" \
    --bin-dir "${BIN_DIR}" \
    --install-dir "${INSTALL_DIR}" \
    --update >> "${LOG_FILE}" 2>&1 \
    && mark "install_success" "PASS" \
    || abort "Installation command failed — check ${LOG_FILE}"
else
  "${WORKDIR}/aws/install" \
    --bin-dir "${BIN_DIR}" \
    --install-dir "${INSTALL_DIR}" >> "${LOG_FILE}" 2>&1 \
    && mark "install_success" "PASS" \
    || abort "Installation command failed — check ${LOG_FILE}"
fi
ok "AWS CLI installed to ${INSTALL_DIR}"

# =============================================================================
#  Step 6 – Post-install verification
# =============================================================================
step "POST-INSTALL VERIFICATION"

INSTALLED_VERSION=$(aws --version 2>&1)
if [[ -n "${INSTALLED_VERSION}" ]]; then
  ok "Version confirmed: ${INSTALLED_VERSION}"
  mark "version_confirmed" "PASS"
else
  fail "aws --version returned empty output"
  mark "version_confirmed" "FAIL"
fi

if [[ -f "${AWS_CRED_FILE}" ]]; then
  ok "AWS credentials present at ${AWS_CRED_FILE}"
  mark "aws_configured" "PASS"
else
  warn "No AWS credentials found — run 'aws configure' to set up"
  mark "aws_configured" "WARN"
fi

# =============================================================================
#  Step 7 – Cleanup
# =============================================================================
step "CLEANUP"
rm -rf "${WORKDIR}"
ok "Temp files removed: ${WORKDIR}"

# =============================================================================
#  Final Report
# =============================================================================
print_report() {
  local PASS=0 FAIL=0 WARN=0 SKIP=0

  log ""
  log "${BOLD}${CYAN}╔════════════════════════════════════════════════════════════╗${RESET}"
  log "${BOLD}${CYAN}║              INSTALLATION REPORT SUMMARY                   ║${RESET}"
  log "${BOLD}${CYAN}╚════════════════════════════════════════════════════════════╝${RESET}"
  log "  Timestamp         : $(date)"
  log "  Host              : $(hostname -f 2>/dev/null || hostname)"
  log "  Install Mode      : ${INSTALL_MODE^^}"
  log "  Credential Action : ${CRED_ACTION^^}"
  log "  Account Audit     : ${AUDIT_SUMMARY}"
  log "  Log File          : ${LOG_FILE}"
  log ""
  log "  ${BOLD}CHECK RESULTS:${RESET}"
  log "  ┌───────────────────────────────────────────────────────────┐"

  declare -A LABELS=(
    [gpg_available]="GPG tool available"
    [curl_available]="curl tool available"
    [unzip_available]="unzip tool available"
    [account_audit]="Existing AWS account/profile audit"
    [credential_action]="Credential action decision"
    [zip_downloaded]="Installer ZIP downloaded"
    [sig_downloaded]="Signature (.sig) downloaded"
    [key_imported]="AWS PGP key imported + fingerprint matched"
    [pgp_verified]="PGP signature verification (ZIP authentic)"
    [install_success]="AWS CLI installed successfully"
    [version_confirmed]="aws --version confirmed"
    [aws_configured]="AWS credentials configured"
  )

  for key in gpg_available curl_available unzip_available \
             account_audit credential_action \
             zip_downloaded sig_downloaded key_imported pgp_verified \
             install_success version_confirmed aws_configured; do
    local status="${CHECKS[$key]}"
    local label="${LABELS[$key]}"
    case "${status}" in
      PASS) log "  │  ${GREEN}✔ PASS${RESET}  ${label}"; ((PASS++)) ;;
      FAIL) log "  │  ${RED}✘ FAIL${RESET}  ${label}"; ((FAIL++)) ;;
      WARN) log "  │  ${YELLOW}⚠ WARN${RESET}  ${label}"; ((WARN++)) ;;
      SKIP) log "  │  ${CYAN}– SKIP${RESET}  ${label}"; ((SKIP++)) ;;
    esac
  done

  log "  └───────────────────────────────────────────────────────────┘"
  log ""
  log "  ${BOLD}SCORE :${RESET}  ${GREEN}${PASS} PASS${RESET}  │  ${RED}${FAIL} FAIL${RESET}  │  ${YELLOW}${WARN} WARN${RESET}  │  ${CYAN}${SKIP} SKIP${RESET}"
  log ""

  if [[ "${#ERRORS[@]}" -gt 0 ]]; then
    log "  ${BOLD}${RED}ERRORS ENCOUNTERED:${RESET}"
    for err in "${ERRORS[@]}"; do
      log "    ${RED}→${RESET} ${err}"
    done
    log ""
  fi

  log "  ${BOLD}CREDENTIAL ACTION TAKEN:${RESET}"
  case "${CRED_ACTION}" in
    kept)                log "  ${GREEN}→${RESET}  Existing credentials kept as-is — no changes to ${AWS_DIR}" ;;
    wiped)               log "  ${YELLOW}→${RESET}  Credentials wiped — run: aws configure" ;;
    backed_up_and_wiped) log "  ${YELLOW}→${RESET}  Credentials backed up + wiped — run: aws configure" ;;
    none)                log "  ${CYAN}→${RESET}  No prior credentials existed — run: aws configure" ;;
  esac
  log ""

  if [[ -n "${INSTALLED_VERSION}" ]]; then
    log "  ${BOLD}INSTALLED VERSION  :${RESET}  ${INSTALLED_VERSION}"
  fi
  log "  ${BOLD}BINARY PATH        :${RESET}  $(command -v aws 2>/dev/null || echo 'not found')"
  log ""

  if [[ "${FAIL}" -eq 0 ]]; then
    log "  ${GREEN}${BOLD}RESULT: INSTALLATION SUCCESSFUL ✔${RESET}"
    if [[ "${CRED_ACTION}" != "kept" ]]; then
      log ""
      log "  ${CYAN}Next step → run:  aws configure${RESET}"
      log "  ${DIM}  Prompts for:${RESET}"
      log "  ${DIM}    AWS Access Key ID     : <your key>${RESET}"
      log "  ${DIM}    AWS Secret Access Key : <your secret>${RESET}"
      log "  ${DIM}    Default region        : ap-south-1  (Mumbai)${RESET}"
      log "  ${DIM}    Default output format : json${RESET}"
    fi
  else
    log "  ${RED}${BOLD}RESULT: INSTALLATION FAILED ✘${RESET}"
    log "  ${YELLOW}Review errors above and check full log: ${LOG_FILE}${RESET}"
  fi

  log ""
  log "${BOLD}${CYAN}════════════════════════════════════════════════════════════${RESET}"
  log "  Full log saved to: ${LOG_FILE}"
  log "${BOLD}${CYAN}════════════════════════════════════════════════════════════${RESET}"
  log ""
}

print_report
