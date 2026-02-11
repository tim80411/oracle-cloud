#!/bin/bash
set -euo pipefail

# ──────────────────────────────────────────────
# Oracle Cloud Setup Script
# Generates all configuration files from .env
# ──────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ──────────────────────────────────────────────
# Load .env
# ──────────────────────────────────────────────

ENV_FILE="$PROJECT_ROOT/.env"

if [[ ! -f "$ENV_FILE" ]]; then
    error ".env file not found. Copy .env.example to .env and fill in your values."
fi

# shellcheck source=/dev/null
source "$ENV_FILE"

# Validate required variables
REQUIRED_VARS=(
    OCI_TENANCY_OCID
    OCI_USER_OCID
    OCI_FINGERPRINT
    OCI_NAMESPACE
    OCI_REGION
    OCI_S3_ACCESS_KEY
    OCI_S3_SECRET_KEY
    BUDGET_ALERT_EMAIL
)

for var in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!var:-}" ]] || [[ "${!var}" == *"xxxxx"* ]] || [[ "${!var}" == "your-"* ]]; then
        error "Required variable $var is not set or still has placeholder value"
    fi
done

# Set defaults for optional variables
OCI_API_KEY_PATH="${OCI_API_KEY_PATH:-$HOME/.ssh/oci_api_key.pem}"
OCI_SSH_KEY_PATH="${OCI_SSH_KEY_PATH:-$HOME/.ssh/id_rsa_oracle_cloud}"

# Expand ~ to $HOME
OCI_API_KEY_PATH="${OCI_API_KEY_PATH/#\~/$HOME}"
OCI_SSH_KEY_PATH="${OCI_SSH_KEY_PATH/#\~/$HOME}"

info "Configuration loaded from .env"

# ──────────────────────────────────────────────
# Generate SSH Keys (if not exist)
# ──────────────────────────────────────────────

if [[ ! -f "$OCI_SSH_KEY_PATH" ]]; then
    info "Generating SSH key for VM access..."
    ssh-keygen -t rsa -b 4096 -f "$OCI_SSH_KEY_PATH" -N ""
    info "SSH key generated: $OCI_SSH_KEY_PATH"
else
    info "SSH key already exists: $OCI_SSH_KEY_PATH"
fi

# ──────────────────────────────────────────────
# Generate OCI API Key (if not exist)
# ──────────────────────────────────────────────

if [[ ! -f "$OCI_API_KEY_PATH" ]]; then
    info "Generating OCI API key..."
    openssl genrsa -out "$OCI_API_KEY_PATH" 2048
    chmod 600 "$OCI_API_KEY_PATH"

    PUBLIC_KEY_PATH="${OCI_API_KEY_PATH%.pem}_public.pem"
    openssl rsa -pubout -in "$OCI_API_KEY_PATH" -out "$PUBLIC_KEY_PATH"

    warn "API key generated. Upload the public key to OCI Console:"
    echo "  Profile → User Settings → API Keys → Add API Key"
    echo "  Public key location: $PUBLIC_KEY_PATH"
    echo ""
    echo "After uploading, update OCI_FINGERPRINT in .env and re-run this script."
else
    info "OCI API key already exists: $OCI_API_KEY_PATH"
fi

# ──────────────────────────────────────────────
# Generate ~/.oci/config
# ──────────────────────────────────────────────

OCI_CONFIG_DIR="$HOME/.oci"
OCI_CONFIG_FILE="$OCI_CONFIG_DIR/config"

mkdir -p "$OCI_CONFIG_DIR"

OCI_PROFILE_CONTENT="[oci]
user=$OCI_USER_OCID
fingerprint=$OCI_FINGERPRINT
tenancy=$OCI_TENANCY_OCID
region=$OCI_REGION
key_file=$OCI_API_KEY_PATH"

if [[ -f "$OCI_CONFIG_FILE" ]]; then
    if grep -q "^\[oci\]" "$OCI_CONFIG_FILE"; then
        warn "[oci] profile already exists in $OCI_CONFIG_FILE"
        warn "Skipping OCI config update. Please update manually if needed."
    else
        cp "$OCI_CONFIG_FILE" "${OCI_CONFIG_FILE}.bak"
        info "Backup created: ${OCI_CONFIG_FILE}.bak"
        echo "" >> "$OCI_CONFIG_FILE"
        echo "$OCI_PROFILE_CONTENT" >> "$OCI_CONFIG_FILE"
        info "OCI CLI config [oci] profile appended to: $OCI_CONFIG_FILE"
    fi
else
    echo "$OCI_PROFILE_CONTENT" > "$OCI_CONFIG_FILE"
    chmod 600 "$OCI_CONFIG_FILE"
    info "OCI CLI config written to: $OCI_CONFIG_FILE"
fi

# ──────────────────────────────────────────────
# Generate ~/.aws/credentials (for S3-compatible access)
# ──────────────────────────────────────────────

AWS_CREDS_DIR="$HOME/.aws"
AWS_CREDS_FILE="$AWS_CREDS_DIR/credentials"

mkdir -p "$AWS_CREDS_DIR"

AWS_PROFILE_CONTENT="[oci]
aws_access_key_id = $OCI_S3_ACCESS_KEY
aws_secret_access_key = $OCI_S3_SECRET_KEY"

if [[ -f "$AWS_CREDS_FILE" ]]; then
    if grep -q "^\[oci\]" "$AWS_CREDS_FILE"; then
        warn "[oci] profile already exists in $AWS_CREDS_FILE"
        warn "Skipping AWS credentials update. Please update manually if needed."
    else
        cp "$AWS_CREDS_FILE" "${AWS_CREDS_FILE}.bak"
        info "Backup created: ${AWS_CREDS_FILE}.bak"
        echo "" >> "$AWS_CREDS_FILE"
        echo "$AWS_PROFILE_CONTENT" >> "$AWS_CREDS_FILE"
        info "AWS credentials [oci] profile appended to: $AWS_CREDS_FILE"
    fi
else
    echo "$AWS_PROFILE_CONTENT" > "$AWS_CREDS_FILE"
    chmod 600 "$AWS_CREDS_FILE"
    info "AWS credentials (OCI S3) written to: $AWS_CREDS_FILE"
fi

# ──────────────────────────────────────────────
# Generate terraform.tfvars
# ──────────────────────────────────────────────

SSH_PUBLIC_KEY=$(cat "${OCI_SSH_KEY_PATH}.pub")

# Main terraform.tfvars
cat > "$PROJECT_ROOT/terraform/terraform.tfvars" <<EOF
tenancy_ocid       = "$OCI_TENANCY_OCID"
region             = "$OCI_REGION"
ssh_public_key     = "$SSH_PUBLIC_KEY"
budget_alert_email = "$BUDGET_ALERT_EMAIL"
EOF

info "Terraform tfvars written to: terraform/terraform.tfvars"

# Bootstrap terraform.tfvars
cat > "$PROJECT_ROOT/terraform/bootstrap/terraform.tfvars" <<EOF
tenancy_ocid = "$OCI_TENANCY_OCID"
region       = "$OCI_REGION"
EOF

info "Bootstrap tfvars written to: terraform/bootstrap/terraform.tfvars"

# ──────────────────────────────────────────────
# Update provider.tf with correct S3 endpoint
# ──────────────────────────────────────────────

S3_ENDPOINT="https://${OCI_NAMESPACE}.compat.objectstorage.${OCI_REGION}.oraclecloud.com"
PROVIDER_FILE="$PROJECT_ROOT/terraform/provider.tf"

if grep -q "endpoint" "$PROVIDER_FILE"; then
    # Use sed to replace the endpoint line
    if [[ "$(uname)" == "Darwin" ]]; then
        sed -i '' "s|endpoint.*=.*\"https://.*oraclecloud.com\"|endpoint                    = \"$S3_ENDPOINT\"|" "$PROVIDER_FILE"
    else
        sed -i "s|endpoint.*=.*\"https://.*oraclecloud.com\"|endpoint                    = \"$S3_ENDPOINT\"|" "$PROVIDER_FILE"
    fi
    info "Updated S3 endpoint in provider.tf"
fi

# Also update region in provider.tf backend block
if [[ "$(uname)" == "Darwin" ]]; then
    sed -i '' "s|region.*=.*\"ap-.*\"|region                      = \"$OCI_REGION\"|" "$PROVIDER_FILE"
else
    sed -i "s|region.*=.*\"ap-.*\"|region                      = \"$OCI_REGION\"|" "$PROVIDER_FILE"
fi

# ──────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────

echo ""
echo "════════════════════════════════════════════"
echo -e "${GREEN}Setup complete!${NC}"
echo "════════════════════════════════════════════"
echo ""
echo "Generated files:"
echo "  - $OCI_CONFIG_FILE"
echo "  - $AWS_CREDS_FILE [oci] profile"
echo "  - terraform/terraform.tfvars"
echo "  - terraform/bootstrap/terraform.tfvars"
echo "  - Updated terraform/provider.tf (S3 endpoint)"
echo ""
echo "Next steps:"
echo "  1. cd terraform/bootstrap && terraform init && terraform apply"
echo "  2. cd .. && tf-oci init && tf-oci plan && tf-oci apply"
echo ""
