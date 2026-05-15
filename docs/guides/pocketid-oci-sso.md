# PocketID → OCI Console SSO

Federate the OCI Console sign-in with self-hosted PocketID via OIDC.

## Current state (provisioned 2026-05-15)

| Resource | ID | Status |
|----------|----|--------|
| OCI Social IdP `PocketID` | `<social-idp-ocid>` | enabled ✓ show-on-login ✓ |
| OCI Group `PocketID-Users` (JIT target) | `<jit-group-ocid>` | no policies attached (intentional) |
| `DefaultIDPRule` | userChoice=true | IdP picker enabled |
| PocketID OAuth Client | `<oauth-client-id>` | accepts OCI callback |

> Specific OCIDs and domain URLs in this guide are placeholders — substitute your own. Live values are kept out of version control.

Live config: `id-attribute=email`, `account-linking=true`, `registration(JIT)=true`, `social-jit-provisioning=true`, `auto-redirect=false`, `scope=[openid,profile,email]`.

**DefaultIDPRule `-return`** — the actual canonical structure (as written by OCI Console UI):

```json
[
  {"name": "LocalIDPs",  "value": "[\"UserNamePassword\"]"},
  {"name": "SamlIDPs",   "value": "[]"},
  {"name": "SocialIDPs", "value": "[\"<social-idp-ocid>\"]"},
  {"name": "X509IDPs",   "value": "[]"},
  {"name": "userChoice", "value": "false"}
]
```

> **Critical:** Names are **plural** (`LocalIDPs`, `SocialIDPs`, …), values are **JSON-stringified arrays**, and `userChoice=false` is correct (it's not a toggle for picker visibility — picker shows whenever any non-empty `SocialIDPs`/`SamlIDPs` is present). Setting these via SCIM PATCH with the wrong shape (singular names / raw IdP-id values) is silently accepted but produces no UI change.

> **IdP Policy must be assigned to OCI Console app**, otherwise no rule's `-return` reaches the sign-in page. UI path: Federation → IdP policy → **Applications** tab → Add app → OCI Console. There is no documented CLI command for this association (the `app.identity-providers` field is null and OciConsole_APPID is a protected app).

> **`account-linking-enabled=true` + `id-attribute=email` is a trap** when the federated email matches the tenancy admin's email. OCI links the federated session to the admin user → "MFA for administrators" SignOn rule rejects social IdP as MFA factor → session immediately deleted → user sees "您的帳戶發生問題. 請洽詢客戶服務部.". Fix: `id-attribute=sub` + `account-linking-enabled=false` so JIT creates a fresh user untouched by admin policy.

After first successful login, attach IAM policies to the `PocketID-Users` group as needed (e.g. read-only, specific compartments). Without policies, JIT users can sign in but see nothing in Console.

## Topology

```
Browser ──(1) sign-in──> idcs-<id>.identity.oraclecloud.com
              ├──(2) "Sign in with PocketID"─> id.<your-pocketid-domain>  (authorize)
              ├──(3) passkey / login───────────> PocketID
              └──(4) code ──> OCI IDCS exchanges for tokens ──> Session
```

| Component | Endpoint |
|-----------|----------|
| PocketID issuer | `https://id.<your-pocketid-domain>` |
| PocketID discovery | `https://id.<your-pocketid-domain>/.well-known/openid-configuration` |
| OCI Identity Domain | Default (Foundation/free tier) |
| OCI Domain URL | `https://idcs-<your-domain-id>.identity.oraclecloud.com` |
| OIDC redirect URI | `https://idcs-<your-domain-id>.identity.oraclecloud.com/oauth2/v1/social/callback` |

## Step 1 — Create OAuth client in PocketID

1. Log in to `https://id.<your-pocketid-domain>` as admin.
2. **OAuth Clients → Add Client**.
3. Fill in:
   - Name: `OCI Console SSO`
   - Callback URLs: `https://idcs-<your-domain-id>.identity.oraclecloud.com/oauth2/v1/social/callback`
   - Public client: **no** (we'll use Client Secret)
   - PKCE: enabled (default; OCI sends `S256`)
4. Save. Copy the generated **Client ID** and **Client Secret**.

## Step 2 — Choose design parameters

Three decisions need user judgement before running the script. See [Design decisions](#design-decisions) below for tradeoffs.

## Step 3 — Register IdP in OCI

```bash
export POCKETID_CLIENT_ID=<from step 1>
export POCKETID_CLIENT_SECRET=<from step 1>

# Edit scripts/setup-oci-pocketid-sso.sh — fill in the TODO(human) block
./scripts/setup-oci-pocketid-sso.sh
```

## Step 4 — Add IdP to the sign-in policy

OCI Console:

1. **Identity → Domains → Default → Security → IdP policies → Default Identity Provider Policy**
2. Edit the only rule → **Assign identity providers** → add `PocketID`.
3. Save.

Or via CLI: `oci identity-domains identity-provider-policy ...` (more complex; UI is faster for one-off).

## Step 5 — Test

1. Open OCI Console sign-in page in a **private window** (so you don't hit cached session):
   `https://cloud.oracle.com`
2. Enter your OCI tenancy name → continue.
3. On the Identity Domain sign-in page, click the **PocketID** button.
4. PocketID prompts for passkey / login → authorize.
5. Browser redirects back; OCI either:
   - logs you in (account linking succeeded), or
   - if JIT enabled, creates a new user in OCI Default Domain and logs in.

## Design decisions

### `ID_ATTRIBUTE` — claim used to link PocketID identity to OCI user

| Choice | Pros | Cons |
|--------|------|------|
| `email` | Human-readable; users in OCI Console look like `user@example.com` | If user changes email in PocketID, account linking breaks |
| `sub` | Immutable, survives PocketID profile changes | Cryptic UUID shown as username in OCI Console |

For a homelab with stable admin emails, `email` *seems* friendlier. **However**: if the PocketID user's email matches the OCI tenancy admin's email, `account-linking=true` will attach the federated session to the admin user — and the OCI Console SignOn policy's "MFA for administrators" rule will then **immediately delete the session** because social IdP isn't a recognized MFA factor for admin accounts. Symptom: "您的帳戶發生問題. 請洽詢客戶服務部." after passkey succeeds.

**For any tenancy where you are both the PocketID user and the tenancy admin, use `sub` and disable account linking.** This forces JIT to create a separate federated user (userName = PocketID UUID) under `PocketID-Users` group, untouched by admin-protection rules.

### `JIT_ENABLED` — auto-create OCI users on first login

| Choice | Pros | Cons |
|--------|------|------|
| `true` | One-admin friendly; no pre-provisioning | Anyone with a PocketID account can land in OCI (control who has PocketID access carefully) |
| `false` | Tight access control; must pre-create OCI users with matching `userName` | Have to manage users in two places |

For Always Free single-tenant + PocketID already gating membership, `true` is fine.

### `JIT_GROUP_OCID` — OCI group JIT users land in

Lookup OCI group OCIDs:

```bash
oci identity-domains groups list \
  --endpoint "https://idcs-<your-domain-id>.identity.oraclecloud.com" \
  --query 'data.resources[*].{name:"display-name",id:id}' --output table
```

Current groups on this tenancy:

| Group | ID | Notes |
|-------|----|-------|
| `Administrators` | `<admin-group-ocid>` | Full admin — only safe for trusted single-user homelab |
| `<service-group-name>` | `<service-group-ocid>` | Service group — not for human users |
| `All Domain Users` | `AllUsersId` | System group, auto-membership, can't be a JIT target |

For a stricter setup, create a new `PocketID-Users` group first and grant only the policies you actually need.

## Troubleshooting

### "redirect_uri mismatch" from PocketID
Verify exact URL (no trailing slash, https, full domain). OCI's callback path is fixed at `/oauth2/v1/social/callback`.

### "Authentication failed - invalid_id_token" in OCI
Discovery URL must be reachable from OCI; PocketID must serve `id_token_signing_alg: RS256` (it does by default).

### "User does not exist" after PocketID login
JIT is disabled and no pre-existing user matches the `ID_ATTRIBUTE` claim. Either pre-create the OCI user with matching userName, or re-run with `JIT_ENABLED=true`.

### Roll back
```bash
DOMAIN_URL="https://idcs-<your-domain-id>.identity.oraclecloud.com"
IDP_ID=$(oci identity-domains social-identity-provider list \
  --endpoint "$DOMAIN_URL" \
  --filter 'name eq "PocketID"' \
  --query 'data.resources[0].id' --raw-output)
oci identity-domains social-identity-provider delete \
  --endpoint "$DOMAIN_URL" --social-identity-provider-id "$IDP_ID" --force
```
