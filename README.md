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
| 1 | `make network` | Configure additional NICs at the OS level (optional, skipped if `foreman_network_interfaces` is empty) |
| 2 | `make lvm` | Carve data disk into LVM volumes for Pulp, containers, pgsql |
| 3 | `make certs` | Obtain TLS cert via ACME (Cloudflare DNS-01) |
| 4 | `make install` | Run `foreman-installer-katello` (~20 min) |
| 5 | `make config` | Configure Foreman via API (content, infra, provisioning, host groups) |

ProxMox-level provisioning (data disk, additional NICs) is **not** part of
this playbook — run `deployments/proxmox-vm-manage` against this host first
(see that deployment's README) before Phase 2, which expects
`foreman_data_disk_device` to already exist as a block device.

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


## Variable reference

Variables come from three places: `inventory/group_vars/foreman/vars.yml` (deployment tuning and the content model), `inventory/group_vars/all/env.yml` (copy of `env.yml.example`, gitignored), and `inventory-common` (`domain`, `kerberos_realm`, `ipa_primary`, `gitlab_url`, `vault_addr`, `vault_kv_*`, `ansible_user`, `rsyslog_remote_*`). "Required" means there is no usable default, or the shipped value is lab-specific and must be replaced. Role defaults for anything not listed are in the [`foreman_install`](../../collections/infrasvc/roles/foreman_install/README.md) and [`foreman_config`](../../collections/infrasvc/roles/foreman_config/README.md) role READMEs.

### Host and storage

| Variable | Shipped value | Required | Description |
|---|---|---|---|
| `foreman` | `foreman.example.com` (`env.yml.example`) | Yes | Foreman FQDN; must match the `foreman` group host in `inventory-common/hosts.yml` |
| `foreman_hostname` | `{{ foreman }}` | No | Server FQDN used throughout |
| `foreman_url` | `https://{{ foreman_hostname }}` | No | Base URL |
| `foreman_data_disk_device` | `/dev/sdb` | Yes | Data disk that phase 2 partitions with LVM; added beforehand through `deployments/proxmox-vm-manage` (`virtio1` is `/dev/vdb`, `scsi1` is `/dev/sdb`) |
| `lvm_provision_volumes` | `lv_pulp` 300G on `/var/lib/pulp`, `lv_containers` 40G on `/var/lib/containers`, `lv_pgsql` 30G on `/var/lib/pgsql`, all XFS in `vg_foreman` | No | LVs carved from the data disk; see **Storage layout** |
| `foreman_network_interfaces` | `[]` | No | Extra NICs configured at the OS level through `mgcdrd.infrabase.network_interfaces` (bonds, VLANs, static IPs); `net0` is untouched. Empty skips the phase. See **Additional NICs** |

### Installer and identity

| Variable | Shipped value | Required | Description |
|---|---|---|---|
| `foreman_version` | `3.19` | No | Foreman release |
| `foreman_katello_version` | `4.21` | No | Katello release |
| `foreman_puppet_release` | `openvox8` | No | Puppet/OpenVox repo release |
| `foreman_org` | lab organization | Yes | Organization all content is created under; replace with yours |
| `foreman_location` | lab location | Yes | Location all content is created under; replace with yours |
| `foreman_username` | `admin` | No | Foreman admin user for API calls |
| `foreman_installer_cli_enable`, `foreman_installer_plugin_enable`, `foreman_installer_proxy_plugin_enable`, `foreman_installer_further_enable` | lists (see **Plugins enabled**) | No | hammer modules, Foreman plugins, Smart Proxy plugins, and extra packages passed to `foreman-installer` |
| `foreman_installer_tuning` | `development` | No | Installer tuning profile |
| `foreman_installer_skip_checks` | `true` | No | Skip the installer's preflight checks |
| `foreman_ldap_auth_sources` | unset | No | LDAP authentication sources (IPA fallback), each with an `account_password`; enables the `ldap_auth` tasks |
| `foreman_puppet_autosign_entries` | `[*.{{ domain }}]` | No | Puppet autosign patterns |

### Smart proxy: DHCP, DNS, TFTP, realm

| Variable | Shipped value | Required | Description |
|---|---|---|---|
| `foreman_dhcp_enable` | `true` | No | Manage DHCP (ISC) |
| `foreman_dhcp_provider` | `isc` | No | DHCP provider |
| `foreman_dhcp_interface` | `ens18` | Yes | NIC DHCP listens on; set to your NIC name |
| `foreman_dhcp_gateway` | `192.0.2.1` | Yes | Gateway handed out (documentation-range placeholder) |
| `foreman_dhcp_range_start`, `foreman_dhcp_range_end` | `192.0.2.2`, `192.0.2.10` | Yes | DHCP range (placeholders) |
| `foreman_dhcp_nameservers` | list | Yes | DNS servers handed out |
| `foreman_dns_enable` | `true` | No | Manage DNS |
| `foreman_dns_provider` | `powerdns` | No | `powerdns` or `nsupdate` |
| `foreman_pdns_api_url` | `http://dns.{{ domain }}:8081` | Yes | PowerDNS REST API endpoint |
| `foreman_tftp_enable` | `true` | No | Manage TFTP |
| `foreman_tftp_listen_on` | `https` | No | Protocols TFTP serves |
| `foreman_realm_enable` | `true` | No | Enable FreeIPA realm integration |
| `foreman_realm_pam_server` | `foreman` | No | PAM service for realm authentication |
| `foreman_realm_ipa_authentication` | `"true"` | No | IPA authentication (installer string boolean) |
| `foreman_realm_ipa_authentication_api` | `"false"` | No | IPA authentication for the API (installer string boolean) |
| `foreman_realm_proxy` | `"true"` | No | Realm smart-proxy feature (installer string boolean) |
| `foreman_realm_provider` | `freeipa` | No | Realm provider |
| `foreman_realm_principal` | `svc-foreman-agent@{{ kerberos_realm }}` | No | Account the realm proxy authenticates as; needs a host-management role and a working password |
| `foreman_realm_freeipa_remove_dns` | `"false"` | No | Remove DNS records when a realm host is deleted |
| `foreman_ipa_controller` | `{{ ipa_primary }}` | No | IPA server the realm proxy talks to |
| `foreman_realm_vault_rotate` | `true` | No | Reset the principal's password after each keytab fetch and write it back to Vault, since `ipa-getkeytab` rotates the key |
| `foreman_realm_vault_addr` | `{{ vault_addr }}` | No | Vault address for that password |
| `foreman_realm_vault_kv_mount` | `{{ vault_kv_infra_mount }}` | No | KV mount |
| `foreman_realm_vault_path` | `{{ vault_kv_env }}/foreman` | No | KV path |
| `foreman_realm_vault_password_key` | `realm_agent_password` | No | Key holding the password |

### Certificates and proxy content

| Variable | Shipped value | Required | Description |
|---|---|---|---|
| `foreman_acme_ca` | `letsencrypt` | No | `letsencrypt` or `google`; Google needs an EAB keypair in Vault first. See **Certificate renewal** |
| `foreman_custom_certs` | `true` | No | Use the `acme_sh` cert instead of the self-signed one |
| `foreman_cert_path`, `foreman_cert_key_path`, `foreman_cert_ca_path` | `/etc/ssl/acme/{{ foreman_hostname }}/{cert,key,ca}.pem` | No | Certificate, key, and self-contained CA chain |
| `foreman_certs_city`, `foreman_certs_country`, `foreman_certs_org`, `foreman_certs_org_unit`, `foreman_certs_state` | lab values | Yes | Subject fields for the internal certificates; replace with yours |
| `foreman_proxy_content_enable_docker` | `false` | No | Container Pulp content type |
| `foreman_proxy_content_enable_ostree` | `true` | No | OSTree Pulp content type |
| `foreman_awx_url`, `foreman_awx_job_template_id` | commented out | No | AWX callback integration; uncomment once job templates exist (with `vault_awx_host_config_key`) |

### Template sync (GitLab)

| Variable | Shipped value | Required | Description |
|---|---|---|---|
| `foreman_template_gitlab_host` | `{{ gitlab_url }}` without the scheme | No | GitLab host |
| `foreman_template_repo` | `ssh://git@<gitlab host>/hardening/foreman-templates.git` | Yes | Templates repository; replace with yours |
| `foreman_template_import_associate` | `always` | No | Associate imported templates with OS and other objects |
| `foreman_template_import_branch` | `main` | No | Branch to import |
| `foreman_template_import_dirname` | `/` | No | Directory within the repo |
| `foreman_template_import_filter` | `EL.*\|el.*\|freeipa.*\|kickstart_repos.*` | No | Regex of template names to import |
| `foreman_template_import_force` | `true` | No | Overwrite locked templates |
| `foreman_template_settings` | `template_sync_*` settings: associate `Always`, branch `main`, commit message, dirname `/`, filter, force `yes`, repo | No | Foreman settings for the template-sync plugin (`name`, `value`) |

### Content model

Each is a list of entries applied through `foreman_config`; every entry takes `state: present` (or `absent`) where applicable. Shipped values describe the lab's Rocky 9 and Debian 12/13 content and are meant to be edited.

| Variable | Shipped value | Required | Description |
|---|---|---|---|
| `foreman_sync_plans` | weekly plans for Rocky 9, Debian 12, Debian 13 | No | Katello sync plans (`name`, `org`, `interval`, `enabled`, `sync_date`) |
| `foreman_repo_products` | Rocky 9, Rocky 9 aarch64, Debian 12, Debian 13 | No | Products (`name`, `org`, `sync_plan`) |
| `foreman_gpg_keys` | `RPM-GPG-KEY-Rocky-9` | No | GPG content credentials (`name`, `file`), taken from an enrolled Rocky 9 host's `/etc/pki/rpm-gpg/` |
| `foreman_repos_rpm` | Rocky 9 AppStream, BaseOS, Devel, EPEL, Extras, Foreman Client, plus kickstart trees | No | RPM repositories (`name`, `product`, `url`, `mirror_on_sync`, `download_policy`, `gpg_key`) |
| `foreman_repos_deb` | Bookworm and Trixie: main, security, updates | No | DEB repositories |
| `foreman_architectures` | `x86_64`, `aarch64`, `arm64` | No | Architectures |
| `foreman_lifecycle_envs` | `Development`, `Stage`, `Production` | No | Lifecycle environments after `Library` |
| `foreman_content_views` | `Rocky 9` and `Debian 12`, auto-publish, promoted through every environment | No | Content views (`name`, `org`, `auto_publish`, `solve_dependencies`, `first_publish`, `lifecycle_envs`, `repos`) |
| `foreman_activation_keys` | `rocky9prd` (Production, view `Rocky 9`) | No | Activation keys (`name`, `org`, `lifecycle_env`, `content_view`, `unlimited_hosts`, `auto_attach`, `content_overrides`) |
| `foreman_domains` | `{{ domain }}` with `dns_proxy: {{ foreman_hostname }}` | No | Domains |
| `foreman_realms` | `{{ kerberos_realm }}`, FreeIPA, proxy `{{ foreman_hostname }}` | No | Realms |
| `foreman_subnets` | one `Lab` subnet in `192.0.2.0/25` with DHCP boot mode | Yes | Subnets (`name`, `network`, `mask`, `gateway`, `dns_primary`, `dns_secondary`, `boot_mode`, proxies); replace with your networks |
| `foreman_compute_resources` | Proxmox nodes `PVE2`, `PVE3`, `PVE4`, `PVE6` with `user: root@pam` and passwords from Vault | Yes | Compute resources (`name`, `provider`, `url`, `user`, `password`, `ssl_verify_peer`) |
| `foreman_compute_profiles` | `PVE2 Default`, `PVE3 Default`, `PVE4 Default`, `PVE6 Default` | No | Compute profiles with `vm_attrs` (CPU, memory, disk, NIC) |
| `foreman_operatingsystems_deb`, `foreman_operatingsystems_rh` | two Debian releases (Bookworm 12 and 13) and Rocky 9 | No | Operating systems with partition tables, install media, and provisioning templates |
| `foreman_partition_table_os_families` | `EL SW Mirror`, `EL Single Disk`, `EL Single Disk UEFI` (Redhat), `Preseed default` (Debian) | No | Partition-table to OS-family mapping |
| `foreman_installation_media` | `Rocky Linux` (Pulp content URL) and `Debian mirror` | No | Installation media |
| `foreman_global_parameters` | `allow-root-ssh: true` | No | Global parameters (`name`, `type`, `value`) |
| `foreman_hostgroups` | `Rocky 9 Base` | No | Host groups (`name`, `description`, `org`, `locations`, `lifecycle_env`, `content_view`, `content_source`, `puppet_proxy`, ...) |
| `foreman_scap_contents` | `[]` | No | Custom SCAP datastreams; the stock `Red Hat rl9 default content` is auto-seeded |
| `foreman_scap_policies` | `CIS Rocky 9 - Level 2`, weekly on Sunday, deployed by Ansible to `Rocky 9 Base` | No | OpenSCAP policies (`scap_content_title`, `scap_content_profile`, `deploy_by`, `period`, `weekday`, `hostgroups`) |
| `foreman_usergroups` | `allow_full_sudo`, external auth source, mapped to `admins`, `isadmin: true` | No | User groups mapped to external groups |

### Vault lookups (`inventory/group_vars/foreman/vault.yml.example`)

Copy to `vault.yml` (gitignored). Every value resolves from Vault KV at `<vault_kv_env>/…` on `vault_kv_infra_mount`; the lab paths are listed under **Vault paths**.

| Variable | Source | Required | Description |
|---|---|---|---|
| `vault_foreman_admin_username`, `vault_foreman_admin_password` | `<env>/foreman` | Yes | Foreman admin credentials |
| `vault_foreman_db_password` | `<env>/foreman` | Yes | Foreman database password |
| `vault_foreman_host_root_pass` | `<env>/foreman` | Yes | Root password set on provisioned hosts |
| `vault_foreman_realm_agent_password` | `<env>/foreman` | If `foreman_realm_enable` | Password of the `foreman_realm_principal` IPA account |
| `vault_foreman_template_sync_ssh_private_key`, `vault_foreman_template_sync_ssh_public_key` | `<env>/foreman` | If template sync is used | ed25519 keypair for the `foreman` OS user's GitLab access; the public half is a deploy key on the templates project |
| `vault_foreman_ldap_bind_password` | `<env>/foreman`, field `ldap_bind_password` | If `foreman_ldap_auth_sources` is set | Bind account password for the LDAP auth source (IPA fallback) |
| `vault_ipa_admin_user`, `vault_ipa_admin_password` | `<env>/ipa/domain_admin` | If `foreman_realm_enable` | IPA domain admin, used to prepare the realm principal |
| `vault_pdns_api_key` | `<env>/pdns` | If `foreman_dns_provider: powerdns` | PowerDNS API key |
| `vault_pve_password`, `vault_pve2_password`, `vault_pve3_password`, `vault_pve4_password`, `vault_pve6_password` | `<env>/proxmox/root` | One per compute resource | Proxmox root passwords |
| `vault_acme_email` | `<env>/acme` | Yes | ACME account email |
| `vault_acme_google_eab_kid`, `vault_acme_google_eab_hmac_key` | `<env>/acme/google/<foreman_hostname>` | If `foreman_acme_ca: google` | Google Public CA EAB credentials |

---

## Before first run

1. Run `deployments/proxmox-vm-manage` against this host to add the data
   disk (and any extra NICs) — see that deployment's README
2. Set `foreman_dhcp_interface` in `inventory/group_vars/foreman/vars.yml` to the correct NIC
3. Set `foreman_pdns_api_url` in `vars.yml` to the PowerDNS REST API endpoint
4. Populate all Vault paths (see below)
5. Leave `foreman_acme_ca: letsencrypt` (default) or switch to `google` once
   the Google Public CA EAB keypair is populated at `infra/lab/acme/google`
6. Uncomment `foreman_awx_url` in `vars.yml` and `vault_awx_host_config_key` in `vault.yml`
   once AWX job templates are created


## Vault paths

| What | Path | Keys |
|------|------|------|
| Foreman admin + DB | `infra/lab/foreman` | `admin_username`, `admin_password`, `db_password`, `host_root_pass`, `realm_agent_password`, `template_sync_ssh_private_key`, `template_sync_ssh_public_key`, `ldap_bind_password` (only when `foreman_ldap_auth_sources` is set) |
| IPA domain admin | `infra/lab/ipa/domain_admin` | `username`, `password` |
| PowerDNS API | `infra/lab/pdns` | `api_key` |
| ProxMox nodes | `infra/lab/proxmox/root` | one `<node>_password` key per compute node referenced in `vars.yml` (e.g. `pve2_password`) |
| ACME / Cloudflare | `infra/lab/acme` | `email`, `cf_key`, `cf_email` (legacy Cloudflare Global API Key mode) |
| ACME / Google Public CA EAB | `infra/lab/acme/google` | `kid`, `hmac_key` (only read when `foreman_acme_ca: google`, see below) |
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

The data disk is added via `deployments/proxmox-vm-manage`, run against this
host before this deployment (see that deployment's README and its
`inventory/host_vars/` for the foreman host's disk spec). Phase 2 here just
partitions whatever device `foreman_data_disk_device` (`vars.yml`) points at
with LVM:

| LV | Mount | Size |
|----|-------|------|
| `lv_pulp` | `/var/lib/pulp` | 300G |
| `lv_containers` | `/var/lib/containers` | 40G |
| `lv_pgsql` | `/var/lib/pgsql` | 30G |


## Additional NICs

Additional VM network interfaces (`net1`+) are added via
`deployments/proxmox-vm-manage` (`mgcdrd.proxmox.proxmox_nic` under the
hood) — `net0` stays owned by the VM's clone-time config and isn't touched
by either deployment. Once a NIC exists at the PVE level, configure it at
the OS level here via `foreman_network_interfaces` in `vars.yml`:

```yaml
foreman_network_interfaces:
  - name: net1
    type: physical
    device: eth1
    ip4: ["10.100.0.5/24"]
    gw4: 10.100.0.1
```

See `mgcdrd.infrabase.network_interfaces`'s README for the full per-type key
reference.


## Certificate renewal

The web cert is an RSA 2048 cert (`acme_sh` role, `complete_chain: true`)
issued by the CA set in `foreman_acme_ca` (`vars.yml`):

- **`letsencrypt`** (default) — `ca.pem` carries the full chain rooted with
  ISRG Root X1.
- **`google`** — Google Public CA, `ca.pem` rooted with GTS Root R1. Requires
  an EAB keypair in Vault first (`gcloud publicca external-account-keys
  create --location=<region>`, stored at `infra/lab/acme/google` as `kid` /
  `hmac_key`) — Google's ACME endpoint rejects registration without it.

Either way `katello-certs-check` gets a self-contained chain. On each acme.sh
auto-renewal the registered hook re-roots the copied chain
(`complete-le-chain.sh`, pinned to whichever CA is active) and pushes it
through `foreman-installer --certs-update-server` via
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
