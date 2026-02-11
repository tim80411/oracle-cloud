#!/bin/bash
set -euo pipefail

# ──────────────────────────────────────────────
# NLB Health Check Script
# Checks NLB connectivity, Reserved IP binding,
# and backend health
# ──────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(dirname "$SCRIPT_DIR")/terraform"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

FIX_MODE=false
FAILED=false

# Parse arguments
for arg in "$@"; do
  case "$arg" in
    --fix) FIX_MODE=true ;;
    -h|--help)
      echo "Usage: ./check-nlb.sh [--fix]"
      echo ""
      echo "Checks NLB connectivity, Reserved IP binding, and backend health."
      echo ""
      echo "Options:"
      echo "  --fix    Show taint commands to fix detected issues"
      echo "  -h       Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg"
      echo "Usage: ./check-nlb.sh [--fix]"
      exit 1
      ;;
  esac
done

# ──────────────────────────────────────────────
# Gather Terraform values
# ──────────────────────────────────────────────

info "Reading Terraform state from $TERRAFORM_DIR ..."

NLB_IP=$(cd "$TERRAFORM_DIR" && AWS_PROFILE=oci terraform output -raw nlb_public_ip 2>/dev/null) || {
  error "Failed to read nlb_public_ip from terraform output. Is Terraform initialized?"
  exit 1
}

RESERVED_IP_OCID=$(cd "$TERRAFORM_DIR" && AWS_PROFILE=oci terraform state show oci_core_public_ip.nlb 2>/dev/null | grep '^\s*id\s' | head -1 | awk '{print $NF}' | tr -d '"') || {
  error "Failed to read Reserved IP OCID from terraform state."
  exit 1
}

NLB_OCID=$(cd "$TERRAFORM_DIR" && AWS_PROFILE=oci terraform state show oci_network_load_balancer_network_load_balancer.k8s 2>/dev/null | grep '^\s*id\s' | head -1 | awk '{print $NF}' | tr -d '"') || {
  error "Failed to read NLB OCID from terraform state."
  exit 1
}

info "NLB IP: $NLB_IP"
info "Reserved IP OCID: $RESERVED_IP_OCID"
info "NLB OCID: $NLB_OCID"
echo ""

# ──────────────────────────────────────────────
# Check 1: TCP connectivity
# ──────────────────────────────────────────────

if command -v curl &>/dev/null; then
  HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://$NLB_IP:80" 2>/dev/null || true)
  if [[ "$HTTP_CODE" != "000" ]]; then
    info "NLB reachable on port 80 (HTTP $HTTP_CODE)"
  else
    error "NLB unreachable on port 80 (connection timeout)"
    FAILED=true
  fi
else
  warn "curl not found. Run manually:"
  echo "  curl --max-time 5 http://$NLB_IP:80"
fi

# ──────────────────────────────────────────────
# Check 2: Reserved IP binding
# ──────────────────────────────────────────────

if command -v oci &>/dev/null && command -v jq &>/dev/null; then
  ASSIGNED_ENTITY=$(oci network public-ip get --public-ip-id "$RESERVED_IP_OCID" 2>/dev/null | jq -r '.data["assigned-entity-id"] // "null"')
  if [[ "$ASSIGNED_ENTITY" != "null" && -n "$ASSIGNED_ENTITY" ]]; then
    info "Reserved IP is bound (assigned-entity-id: ${ASSIGNED_ENTITY:0:20}...)"
  else
    error "Reserved IP is UNBOUND (assigned-entity-id is null)"
    FAILED=true
  fi
else
  warn "oci CLI or jq not found. Run manually:"
  echo "  oci network public-ip get --public-ip-id $RESERVED_IP_OCID | jq '.data[\"assigned-entity-id\"]'"
fi

# ──────────────────────────────────────────────
# Check 3: Backend health
# ──────────────────────────────────────────────

if command -v oci &>/dev/null && command -v jq &>/dev/null; then
  BACKEND_STATUS=$(oci nlb backend-set-health get \
    --backend-set-name "k8s-ingress-backend-set" \
    --network-load-balancer-id "$NLB_OCID" 2>/dev/null | jq -r '.data.status // "UNKNOWN"')
  if [[ "$BACKEND_STATUS" == "OK" ]]; then
    info "Backend set 'k8s-ingress-backend-set' is healthy"
  else
    warn "Backend set 'k8s-ingress-backend-set' status: $BACKEND_STATUS"
    FAILED=true
  fi
else
  warn "oci CLI or jq not found. Run manually:"
  echo "  oci nlb backend-set-health get --backend-set-name k8s-ingress-backend-set --network-load-balancer-id $NLB_OCID | jq '.data.status'"
fi

# ──────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────

echo ""
if [[ "$FAILED" == true ]]; then
  error "NLB health check FAILED — issues detected above"
  if [[ "$FIX_MODE" == true ]]; then
    echo ""
    warn "Suggested fix — taint and rebuild NLB resources:"
    echo "  cd $TERRAFORM_DIR"
    echo "  tf-oci taint oci_network_load_balancer_network_load_balancer.k8s"
    echo "  tf-oci taint oci_network_load_balancer_backend.control_plane_http"
    echo "  tf-oci taint oci_network_load_balancer_backend.control_plane_https"
    echo "  tf-oci plan && tf-oci apply"
  else
    echo "  Run with --fix to see suggested remediation commands."
  fi
  exit 1
else
  info "All NLB health checks PASSED"
  exit 0
fi
