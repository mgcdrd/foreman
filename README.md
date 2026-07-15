foreman
=======

Deploys Foreman 3.19 + Katello 4.21 on a fresh Rocky Linux 9 VM — from bare OS
to a fully configured provisioning server in a single run.

Uses `foreman-installer-katello` (traditional RPM-based install, not containerized).
The containerized `foremanctl` path was ruled out because it does not support
DHCP, TFTP, DNS, Discovery, OpenSCAP, or Realm in 3.19.


## Prerequisites

- Rocky Linux 9 VM built and reachable via SSH
- Host enrolled in the FreeIPA domain
- IPA service account named in `foreman_realm_principal` (default
  `svc-foreman-agent`) created with a role granting host-management
  privileges — the equivalent of `foreman-prepare-realm`'s `realm-proxy`
  user — **and a password set** (stored in Vault as `realm_agent_password`).
  The install role kinits as this account itself and self-service-fetches
  its own Kerberos keytab; no admin privilege is needed for that step.
- HashiCorp Vault running and populated (see Vault paths below)
- Collections installed: `ansible-galaxy collection install -r collections/requirements.yml`
- `../../inventory-common` cloned as a sibling of `deployments/` (see below)

If the VM was previously registered to another Foreman/Katello as a content
host, the install preflight unregisters it and re-enables the standard Rocky
repos automatically.


## First-time setup

This deployment has no `hosts.yml`/`group_vars/all.yml` of its own — the
`foreman` group, its host, and shared environment constants (`domain`,
`vault_addr`, `ipa_primary`, `kerberos_realm`, `gitlab_url`, `vault_kv_*`,
`ansible_user`, `rsyslog_remote_*`) all come from
[inventory-common](https://gitlab.example.com/ansible/inventory-common),
referenced as a second inventory source in `ansible.cfg`. Clone it as a
sibling of `deployments/`:

```bash
git clone https://gitlab.example.com/ansible/inventory-common.git ../../inventory-common
```

Add the host under the `foreman` group in `../../inventory-common/hosts.yml`
if it isn't there yet — see that repo's README for the tier rule on what
belongs there versus here. For a customer engagement, point at a
`inventory-<client>` repo (cloned from `inventory-template`) instead, and
update `ansible.cfg`'s inventory path accordingly.

Two files are gitignored and must be created from their examples:

```bash
cp inventory/group_vars/all/env.yml.example inventory/group_vars/all/env.yml
cp inventory/group_vars/foreman/vault.yml.example inventory/group_vars/foreman/vault.yml
```

- **`env.yml`** — set the `foreman` hostname to match what you added to
  `inventory-common/hosts.yml`; only override `domain`/`vault_addr`/etc. here
  if this deployment must differ from the shared environment
- **`vault.yml`** — replace `infra/<env>/` in every path with your Vault namespace (e.g. `infra/lab/`)

Then update `vars.yml` with your network values:
- `foreman_dhcp_interface` — NIC name
- `foreman_dhcp_gateway` / `foreman_dhcp_range_*` / `foreman_dhcp_nameservers` — your subnet
- `foreman_subnets` network block
- `foreman_pdns_api_url` — PowerDNS REST API endpoint


## Deployment phases

| Phase | Make target | What it does |
|-------|-------------|--------------|
| 0 | `make storage` | Add 400G data disk via ProxMox API, detect block device |
| 1 | `make lvm` | Carve data disk into LVM volumes for Pulp, containers, pgsql |
| 2 | `make certs` | Obtain TLS cert via ACME (Cloudflare DNS-01) |
| 3 | `make install` | Run `foreman-installer-katello` (~20 min) |
| 4 | `make config` | Configure Foreman via API (content, infra, provisioning, host groups) |

OS hardening and FreeIPA enrollment are **not** part of this playbook — the
host is assumed to be hardened (see `deployments/harden`) and already an IPA
domain member before `make deploy`.

Full run: `make deploy`

Phase 5 sub-targets for partial re-runs:

| Target | What it configures |
|--------|--------------------|
| `make syncplans` | Sync plans |
| `make repos` | Products and repositories |
| `make lifecycle` | Lifecycle environments, content views, activation keys |
| `make infra` | Domains, subnets, architectures, compute resources and profiles |
| `make provisioning` | Operating systems, install media, partition tables, global params |
| `make hostgroups` | Host groups |


## Before first run

1. Set `foreman_dhcp_interface` in `inventory/group_vars/foreman/vars.yml` to the correct NIC
2. Set `foreman_pdns_api_url` in `vars.yml` to the PowerDNS REST API endpoint
3. Populate all Vault paths (see below)
4. Uncomment `foreman_awx_url` in `vars.yml` and `vault_awx_host_config_key` in `vault.yml`
   once AWX job templates are created


## Vault paths

| What | Path | Keys |
|------|------|------|
| Foreman admin + DB | `infra/lab/foreman` | `admin_username`, `admin_password`, `db_password`, `host_root_pass`, `realm_agent_password`, `template_sync_ssh_private_key`, `template_sync_ssh_public_key` |
| IPA domain admin | `infra/lab/ipa/domain_admin` | `username`, `password` |
| PowerDNS API | `infra/lab/pdns` | `api_key` |
| ProxMox nodes | `infra/lab/proxmox/root` | one `<node>_password` key per compute node referenced in `vars.yml` (e.g. `pve2_password`) |
| ACME / Cloudflare | `infra/lab/acme` | `email`, `cf_key`, `cf_email` (legacy Cloudflare Global API Key mode) |
| AWX callback | `infra/lab/awx/host_callback` | `host_config_key` (optional — only needed once AWX job templates exist) |

`realm_agent_password` is the password for the IPA account named in
`foreman_realm_principal` — the role kinits as that account itself to
self-service-fetch its own Kerberos keytab, so this account needs both a
role granting host-management privileges **and** a working password (see
Prerequisites above). `template_sync_ssh_private_key` /
`..._public_key` are a persistent ed25519 keypair for the `foreman` OS
user's GitLab access — generate once with `ssh-keygen -t ed25519 -N '' -f <file>`
and register the public half as a deploy key on the templates project. Both
survive host rebuilds since they're deployed from Vault rather than
generated per-host.


## Storage layout

Phase 0 adds a 400G virtio disk via the ProxMox API (VMID discovered automatically
by hostname). Phase 1.5 partitions it with LVM:

| LV | Mount | Size |
|----|-------|------|
| `lv_pulp` | `/var/lib/pulp` | 300G |
| `lv_containers` | `/var/lib/containers` | 40G |
| `lv_pgsql` | `/var/lib/pgsql` | 30G |

Set `foreman_expand_storage: false` in `vars.yml` to skip Phase 0 if the disk
was pre-provisioned in PVE (Phase 1.5 falls back to `/dev/vdb`).


## Certificate renewal

The web cert is an RSA 2048 Let's Encrypt cert (`acme_sh` role,
`complete_chain: true`): `ca.pem` carries the full chain rooted with ISRG
Root X1 so `katello-certs-check` accepts it. On each acme.sh auto-renewal the
registered hook re-roots the copied chain (`complete-le-chain.sh`) and pushes
it through `foreman-installer --certs-update-server` via
`/usr/local/sbin/foreman-cert-renewal.sh`. No `fullchain.pem` is deployed.

## Content managed

**RPM** — Rocky 9 x86_64 + aarch64: AppStream, BaseOS, Devel, EPEL, Extras, Foreman Client

**DEB** — Debian 12 (Bookworm) and Debian 13 (Trixie): main, security, updates

Lifecycle: `Library → Development → Stage → Production`


## Plugins enabled

Ansible, Bootdisk, Discovery, OpenSCAP, ProxMox compute, Puppet (OpenVox 8),
Remote Execution, Templates, Vault


## Smart proxy features

DHCP (ISC), TFTP, DNS (PowerDNS), Realm (FreeIPA), OpenSCAP, Remote Execution,
Ansible, Discovery
