#!/bin/bash
set -euo pipefail

# ──────────────────────────────────────────────
# OCI Identity Domain ← PocketID OIDC SSO setup
# Registers PocketID as a Social IdP on the Default
# Identity Domain via OCI CLI.
#
# Prereqs (do these BEFORE running):
#   1. In PocketID admin (https://id.<your-pocketid-domain>),
#      create an OAuth Client named "OCI Console SSO" with
#      redirect URI:
#        https://idcs-<your-domain-id>.identity.oraclecloud.com/oauth2/v1/social/callback
#   2. Export the required environment variables:
#        export OCI_DOMAIN_URL=https://idcs-<your-domain-id>.identity.oraclecloud.com
#        export POCKETID_DISCOVERY_URL=https://id.<your-pocketid-domain>/.well-known/openid-configuration
#        export POCKETID_CLIENT_ID=...
#        export POCKETID_CLIENT_SECRET=...
# ──────────────────────────────────────────────

DOMAIN_URL="${OCI_DOMAIN_URL:?OCI_DOMAIN_URL is not set — see prereqs above}"
DISCOVERY_URL="${POCKETID_DISCOVERY_URL:?POCKETID_DISCOVERY_URL is not set — see prereqs above}"
IDP_NAME="${OCI_IDP_NAME:-PocketID}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail() { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }

[ -n "${POCKETID_CLIENT_ID:-}" ] || fail "POCKETID_CLIENT_ID is not set"
[ -n "${POCKETID_CLIENT_SECRET:-}" ] || fail "POCKETID_CLIENT_SECRET is not set"

# ──────────────────────────────────────────────
# Design decisions — TODO(human)
#
# Fill in the values below based on the tradeoffs noted in
# docs/guides/pocketid-oci-sso.md (search for "Design decisions").
#
# ID_ATTRIBUTE       — which PocketID claim links to OCI user.
#                      Options: "email" (human-readable, mutable)
#                               "sub"   (immutable UUID, cryptic in Console)
#
# JIT_ENABLED        — auto-create OCI users on first PocketID login.
#                      Options: "true"  (lazy provisioning, one-admin friendly)
#                               "false" (must pre-create OCI users)
#
# JIT_GROUP_OCID     — which OCI group JIT-provisioned users land in.
#                      Get it from: oci identity-domains groups list \
#                                     --endpoint "$DOMAIN_URL" \
#                                     --filter 'displayName eq "<group-name>"'
#                      Recommended: create a dedicated, no-policy group
#                      (e.g. "PocketID-Users") and attach policies later.
#                      (Leave blank "" if JIT_ENABLED=false.)
# ──────────────────────────────────────────────

ID_ATTRIBUTE="sub"                            # immutable UUID; avoids collision with tenancy admin email
JIT_ENABLED="true"                            # auto-create OCI user on first login
JIT_GROUP_OCID="${OCI_JIT_GROUP_OCID:-}"      # set OCI_JIT_GROUP_OCID env var to your dedicated JIT group OCID

[ -n "$ID_ATTRIBUTE" ] || fail "ID_ATTRIBUTE not set — see TODO(human) block"
[ -n "$JIT_ENABLED" ]  || fail "JIT_ENABLED not set — see TODO(human) block"
if [ "$JIT_ENABLED" = "true" ] && [ -z "$JIT_GROUP_OCID" ]; then
  fail "JIT_ENABLED=true requires JIT_GROUP_OCID"
fi

# ──────────────────────────────────────────────
# Build payload and create Social IdP
# ──────────────────────────────────────────────

SCOPE_JSON='["openid","profile","email"]'

JIT_ARGS=()
if [ "$JIT_ENABLED" = "true" ]; then
  JIT_ARGS+=( --registration-enabled true )
  JIT_ARGS+=( --jit-prov-group-static-list-enabled true )
  JIT_ARGS+=( --jit-prov-assigned-groups "[{\"value\":\"$JIT_GROUP_OCID\"}]" )
else
  JIT_ARGS+=( --registration-enabled false )
fi

info "Creating Social IdP '$IDP_NAME' on $DOMAIN_URL ..."

oci identity-domains social-identity-provider create \
  --endpoint "$DOMAIN_URL" \
  --schemas '["urn:ietf:params:scim:schemas:oracle:idcs:SocialIdentityProvider"]' \
  --name "$IDP_NAME" \
  --service-provider-name "OpenID Connect" \
  --enabled true \
  --status "created" \
  --show-on-login true \
  --discovery-url "$DISCOVERY_URL" \
  --consumer-key "$POCKETID_CLIENT_ID" \
  --consumer-secret "$POCKETID_CLIENT_SECRET" \
  --scope "$SCOPE_JSON" \
  --id-attribute "$ID_ATTRIBUTE" \
  --account-linking-enabled false \
  --description "PocketID OIDC SSO" \
  "${JIT_ARGS[@]}"

info "Done. Next: add '$IDP_NAME' to the Default IdP Policy"
info "  Console: Identity → Domains → Default → Security → IdP policies"
