#!/bin/bash
set -euo pipefail

# ──────────────────────────────────────────────
# Verify PocketID OCI SSO end-to-end state.
# Run after waiting 15-30 min post-setup, or after
# poking the rule in OCI Console UI.
# ──────────────────────────────────────────────

DOMAIN_URL="${OCI_DOMAIN_URL:?OCI_DOMAIN_URL not set (e.g. https://idcs-<id>.identity.oraclecloud.com)}"
IDP_ID="${OCI_IDP_ID:?OCI_IDP_ID not set (Social IdP OCID — find via 'oci identity-domains social-identity-provider list')}"
GROUP_ID="${OCI_JIT_GROUP_OCID:?OCI_JIT_GROUP_OCID not set (target JIT group OCID)}"
POCKETID_DISCOVERY_URL="${POCKETID_DISCOVERY_URL:?POCKETID_DISCOVERY_URL not set (e.g. https://id.<domain>/.well-known/openid-configuration)}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()  { echo -e "${GREEN}✓${NC} $1"; }
bad() { echo -e "${RED}✗${NC} $1"; }
warn(){ echo -e "${YELLOW}!${NC} $1"; }

echo "═══ PocketID SSO verification ═══"
echo

# 1. IdP config
IDP=$(oci identity-domains social-identity-provider get \
  --endpoint "$DOMAIN_URL" --social-identity-provider-id "$IDP_ID" 2>/dev/null)
if [ -z "$IDP" ]; then bad "IdP $IDP_ID not found"; exit 1; fi

for field in enabled show-on-login registration-enabled social-jit-provisioning-enabled; do
  val=$(echo "$IDP" | python3 -c "import sys,json;print(json.load(sys.stdin)['data'].get('$field'))")
  if [ "$val" = "True" ]; then ok "IdP.$field = True"; else bad "IdP.$field = $val (expected True)"; fi
done

JIT=$(echo "$IDP" | python3 -c "import sys,json;d=json.load(sys.stdin)['data'].get('jit-prov-assigned-groups',[]);print(d[0]['value'] if d else 'none')")
[ "$JIT" = "$GROUP_ID" ] && ok "JIT group = PocketID-Users" || bad "JIT group = $JIT (expected $GROUP_ID)"

# 2. IdP Policy Rule
RULE=$(oci identity-domains rule get --endpoint "$DOMAIN_URL" --rule-id "DefaultIDPRule" --attribute-sets all 2>/dev/null)
RET=$(echo "$RULE" | python3 -c "import sys,json;print(json.dumps(json.load(sys.stdin)['data']['-return']))")
echo "$RET" | grep -q "SocialIDPs.*$IDP_ID" \
  && ok "DefaultIDPRule SocialIDPs contains $IDP_ID" \
  || bad "DefaultIDPRule missing SocialIDPs ref to $IDP_ID"

echo "$RET" | python3 -c "
import sys, json
ret = json.loads(sys.stdin.read())
local = next((r['value'] for r in ret if r.get('name')=='LocalIDPs'), None)
print('  LocalIDPs:', local)
" 2>/dev/null

# 3. JIT group members (any users logged in yet?)
GROUP=$(oci identity-domains group get --endpoint "$DOMAIN_URL" --group-id "$GROUP_ID" 2>/dev/null)
COUNT=$(echo "$GROUP" | python3 -c "import sys,json;m=json.load(sys.stdin)['data'].get('members');print(len(m) if m else 0)")
if [ "$COUNT" -gt 0 ]; then
  ok "PocketID-Users has $COUNT member(s) — SSO has been used at least once"
  echo "$GROUP" | python3 -c "
import sys,json
for m in json.load(sys.stdin)['data'].get('members', []) or []:
    print('   -', m.get('name', m.get('display','?')))
"
else
  warn "PocketID-Users has 0 members — no PocketID user has signed in yet"
fi

# 4. PocketID OAuth client reachability
echo
CODE=$(curl -sf -o /dev/null -w "%{http_code}" --max-time 5 \
  "$POCKETID_DISCOVERY_URL" || echo "FAIL")
[ "$CODE" = "200" ] && ok "PocketID discovery reachable" || bad "PocketID discovery: $CODE"

echo
echo "Try sign-in:  https://cloud.oracle.com  →  tenant=<your-tenancy>  →  domain=Default"
echo "(use a private/incognito window to avoid cached sessions)"
