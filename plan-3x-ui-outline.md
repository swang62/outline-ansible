# Plan: 3x-ui and Outline Coexistence

## Goal

Run 3x-ui beside the existing Outline server on one EC2 instance, with:

| Service                | Endpoint                         | Transport             |
| ---------------------- | -------------------------------- | --------------------- |
| 3x-ui panel            | `3xui.sss-vpn-proxy.xyz`         | TCP/443               |
| Outline access keys    | `outline.sss-vpn-proxy.xyz:8443` | TCP/8443 and UDP/8443 |
| AmneziaWG              | `wg.sss-vpn-proxy.xyz:3389`      | UDP/3389              |
| Outline management API | existing hostname:50443          | TCP/50443             |

Cloudflare records:

- `3xui.sss-vpn-proxy.xyz`: A and AAAA, proxied (orange cloud).
- `wg.sss-vpn-proxy.xyz`: A and AAAA, DNS-only (gray cloud).
- `outline.sss-vpn-proxy.xyz`: A and AAAA, DNS-only (gray cloud). (already setup)

## Scope

### In

- Move Outline TCP and UDP access-key traffic from 443 to 8443.
- Configure 3x-ui immediately after the existing Outline deployment, before the single final health-check phase.
- Install a pinned 3x-ui Docker image idempotently, make sure all env variables are correctly set.
- Serve the 3x-ui panel directly on TCP/443 with its built-in TLS support; do not add a reverse proxy.
- Maintain Cloudflare A and AAAA records as EC2 addresses change.
- Obtain and renew panel TLS using 3x-ui's Cloudflare DNS validation.
- Create one AmneziaWG inbound and one bootstrap client through the running 3x-ui API.
- Support server access over both public IPv4 and IPv6.

### Out

- No Caddy, Nginx, TCP multiplexer, or SNI router.
- No Cloudflare proxy for Outline/WireGuard/AmneziaWG UDP traffic.
- Keep all AmneziaWG secrets, client configurations, passwords, and downloaded VPS artifacts under `files/amneziawg/`, excluded from git and permission-restricted.

## Tasks

### [ ] Task 1: Define deployment variables

- **Files**: `terraform/variables.tf`, `terraform/global.auto.tfvars.json.example`, local `terraform/global.auto.tfvars.json`
- **Description**:
  - Change `outline_keys_port` from `443` to `8443`.
  - Add typed variables for the pinned 3x-ui image, state directory, panel hostname, WG hostname, panel port (`443`), AmneziaWG port (`3389`), and permitted Outline API CIDRs.
  - Use `ghcr.io/mhsanaei/3x-ui:latest`.
  - Keep the Cloudflare token in `CLOUDFLARE_API_TOKEN`; never add it to tfvars.
- **Acceptance criteria**:
  - All non-secret configuration is explicit and available through the current Ansible `include_vars` flow.
  - No secret is added to the repository or Terraform state.
- **Guardrails**:
  - Do not add settings for unused protocols or extra services.

### [ ] Task 2: Change security-group ingress

- **Files**: `terraform/main.tf`
- **Description**:
  - Replace public Outline `TCP/443` and `UDP/443` ingress with `TCP/8443` and `UDP/8443`.
  - Retain public `TCP/443` for the 3x-ui panel.
  - Add public `UDP/3389` ingress for AmneziaWG, for both IPv4 and IPv6.
  - `TCP/50443` is unchanged.
- **Acceptance criteria**:
  - Terraform plan exposes TCP/443, TCP+UDP/8443, and UDP/3389.
  - IPv4 and IPv6 rules exist for TCP/443, TCP+UDP/8443, and UDP/3389.
  - TCP/3389 is not exposed.
- **Guardrails**:
  - Do not remove SSH or necessary existing ICMP rules.

### [ ] Task 3: Maintain Cloudflare DNS records

- **Files**: `ansible/setup.yml`, `ansible/start.yml`
- **Description**:
  - Create/update A and AAAA records for `3xui.sss-vpn-proxy.xyz` from the EC2 public IPv4/IPv6 addresses, with `proxied: true`.
  - Create/update A and AAAA records for `wg.sss-vpn-proxy.xyz` from the same addresses, with `proxied: false`.
  - Run this reconciliation after each instance start, when public addresses may change.
  - Use `no_log: true` on all tasks handling the Cloudflare token.
- **Acceptance criteria**:
  - Both names resolve to the current EC2 A and AAAA addresses.
  - The panel is orange-clouded and the WG hostname is gray-clouded.
- **Guardrails**:
  - Do not attempt to proxy UDP/3389 through standard Cloudflare.

### [ ] Task 4: Migrate Outline to port 8443

- **Files**: `ansible/setup.yml`, `ansible/start.yml`, `README.md`
- **Description**:
  - Use the existing Shadowbox configuration's `portForNewAccessKeys` with the new `outline_keys_port` value.
  - Replace Shadowbox `network_mode: host` with Docker bridge networking.
  - Explicitly publish `8443:8443/tcp`, `8443:8443/udp`, and `50443:50443/tcp` from Shadowbox; do not publish port 443 from Shadowbox.
  - Check that TCP/8443 and UDP/8443 are free before starting Shadowbox.
  - Regenerate or verify the stored access-key URL reports port 8443.
- **Acceptance criteria**:
  - Shadowbox owns TCP/8443 and UDP/8443.
  - Shadowbox runs without host networking and has only the three required published ports.
  - Existing Outline API health checks continue to pass.
- **Guardrails**:
  - Existing Outline access keys that point at port 443 are out of scope; do not migrate or preserve them.
  - Do not leave Shadowbox bound to TCP/443.

### [ ] Task 5: Deploy 3x-ui idempotently

- **Files**: `ansible/setup.yml`
- **Description**:
  - Reuse the existing Docker installation.
  - Place this deployment play immediately after the existing `Deploy Outline server` play and before `Verify server health`; reuse the Docker setup already performed by Outline rather than reinstalling Docker or related packages.
  - Create root-owned `0700` directories beneath the configured 3x-ui state path for:
    - `/etc/x-ui` database/configuration;
    - `/root/cert` certificates;
    - `/root/.acme.sh` ACME state.
  - Run the pinned official 3x-ui container with `community.docker.docker_container`.
  - Publish `443:443/tcp` and `3389:3389/udp`.
  - Set `XUI_PORT=443`, `XUI_ENABLE_FAIL2BAN=true`, and a non-default initial web base path.
  - Grant only `NET_ADMIN` and `NET_RAW`, required by 3x-ui's bundled fail2ban and IPv6 handling.
  - Set `restart_policy: unless-stopped` and the existing local log driver.
- **Acceptance criteria**:
  - Re-running the playbook does not recreate an unchanged container.
  - Database, certificates, ACME state, inbounds, and clients survive container recreation.
  - 3x-ui is the sole TCP/443 listener.
  - The one final health-check phase runs only after both Outline and 3x-ui setup complete.
- **Guardrails**:
  - No `network_mode: host`, `privileged`, Docker socket mount, or database exposure.

### [ ] Task 6: Configure panel TLS and Cloudflare

- **Files**: `ansible/setup.yml`; add an Ansible template only if inline task content becomes unreadable
- **Description**:
  - Bootstrap a strong panel administrator credential and store it outside git with `0600` permissions.
  - Use a Cloudflare token scoped to `Zone:DNS:Edit` for `sss-vpn-proxy.xyz` to drive 3x-ui's documented Cloudflare DNS validation.
  - Let 3x-ui obtain, configure, and renew its own certificate for `3xui.sss-vpn-proxy.xyz` through Cloudflare DNS validation; do not create or install a Cloudflare Origin Certificate.
  - Set the Cloudflare zone encryption mode to **Full** after the panel serves TLS.
  - Make all certificate actions convergent by inspecting the currently configured certificate/domain first.
- **Acceptance criteria**:
  - `https://3xui.sss-vpn-proxy.xyz` is reachable through Cloudflare with valid TLS.
  - Cloudflare SSL/TLS encryption mode is Full.
  - The panel is reachable through the configured Cloudflare DNS record.
- **Guardrails**:
  - Never log panel credentials, Cloudflare credentials, session cookies, or private keys.

### [ ] Task 7: Create AmneziaWG inbound and client through API

- **Files**: `ansible/setup.yml`, `.gitignore`, `files/amneziawg/` (local, gitignored runtime artifacts)
- **Description**:
  - Create `files/amneziawg/` locally before writing artifacts; set directory mode `0700`.
  - Authenticate to the local 3x-ui panel using an API token or supported bootstrap session.
  - Fetch the running pinned release's OpenAPI document at `/panel/api/openapi.json` (using the configured panel base path) and validate the exact inbound/client request schema before mutation.
  - Idempotently find or create a single `amneziawg` inbound on `UDP/3389`, make sure all defaults are randomly generated by 3xui and have full obfuscation enabled.
  - Configure the client endpoint as `wg.sss-vpn-proxy.xyz:3389`, never as a fixed address.
  - Assign non-conflicting IPv4 and IPv6 tunnel ranges and client addresses, subject to the API schema's AmneziaWG fields.
  - Idempotently find or create one named bootstrap client.
  - Download the generated AmneziaWG client configuration from the VPS/panel API to `files/amneziawg/client.conf` with mode `0600` for local client import.
  - Save all related local runtime artifacts only in `files/amneziawg/`: API token, generated panel/bootstrap password, client private/public configuration, QR/export output, and any recovery metadata. Use mode `0600` per file.
  - Add `files/amneziawg/` to `.gitignore`; use `no_log: true` for every task that creates, transfers, reads, or displays these values.
- **Acceptance criteria**:
  - The exact API endpoint and payload come from the live OpenAPI schema, not guessed requests.
  - A second run creates neither a duplicate inbound nor client.
  - Client configuration uses the WG hostname, allowing dual-stack resolver selection.
  - Every AmneziaWG secret/configuration artifact resides under `files/amneziawg/`, has restrictive local permissions, and is excluded from git.
- **Guardrails**:
  - Fail before mutation if this 3x-ui release's OpenAPI schema lacks the required AmneziaWG operations.
  - Keep private keys, API tokens, passwords, QR output, and client configs out of task output and git.

### [ ] Task 8: Add staged verification and documentation

- **Files**: `ansible/setup.yml`, `ansible/start.yml`, `README.md`
- **Description**:
  - Apply DNS/security-group updates before changing running listeners.
  - Move Shadowbox to 8443 and confirm TCP/443 is free before 3x-ui claims it.
  - Add or confirm checks for container state, public panel TLS, Outline API health.
  - Document final port ownership, Cloudflare proxy state, and the manual final AmneziaWG handshake check.
- **Acceptance criteria**:
  - Setup and start playbooks converge after an EC2 stop/start and public IP rotation.
  - Health checks cover both services without assuming UDP success from a TCP probe.
  - Documentation lists the final ports accurately.
- **Guardrails**:
  - Do not claim UDP reachability until a real AmneziaWG client handshake is tested over both IPv4 and IPv6 where connectivity exists.

## Dependencies

1. A Cloudflare API token with `Zone:DNS:Edit` scoped to `sss-vpn-proxy.xyz`.
2. Cloudflare manages the zone's authoritative DNS.
3. AWS credentials can update the existing security group.
4. TCP/443, TCP/8443, UDP/8443, and UDP/3389 have no conflicting host listeners.

## QA Scenarios

1. **First deployment**: DNS records exist, Outline serves TCP+UDP/8443, panel loads through Cloudflare on 443, and AmneziaWG connects on UDP/3389.
2. **Repeat deployment**: No duplicate records, containers, inbounds, or clients.
3. **EC2 IP rotation**: After stop/start, both A and AAAA records update and clients reconnect by hostname.
4. **Certificate persistence**: Panel TLS survives a 3x-ui container recreation and renewal state remains available.
5. **IPv4 path**: A client resolves the WG A record and completes an AmneziaWG handshake.
6. **IPv6 path**: A client resolves the WG AAAA record and completes an AmneziaWG handshake where the client network supports IPv6.
7. **Port ownership**: 3x-ui owns TCP/443 and UDP/3389; Shadowbox owns TCP+UDP/8443.
