# ansible-bootstrap-kit

Reusable Ansible scaffold for the baseline stuff every org needs on every host:
users, packages, security hardening, time sync, and a common inventory layout.
Fork/clone this as the starting point for a new environment instead of
rebuilding the structure each time.

## Layout

```
.
├── ansible.cfg                  # project-local Ansible config (points at staging by default)
├── requirements.yml              # Galaxy collections this kit depends on
├── Makefile                      # install / lint / ping / bootstrap / site shortcuts
├── inventories/
│   ├── staging/
│   │   ├── hosts.yml              # staging inventory
│   │   ├── group_vars/all/        # vars applied to every staging host
│   │   └── host_vars/             # per-host overrides
│   └── production/
│       ├── hosts.yml
│       ├── group_vars/all/
│       └── host_vars/
├── playbooks/
│   ├── ping.yml                   # connectivity + fact-gathering sanity check
│   ├── bootstrap.yml              # first-run setup: common + users + security
│   └── site.yml                   # full convergence: all roles
├── roles/
│   ├── common/                    # hostname, timezone, base packages, MOTD
│   ├── users/                     # admin users, SSH keys, sudo access
│   ├── packages/                  # OS package cache/upgrade/install/remove
│   ├── security/                  # SSH hardening, fail2ban, firewall
│   └── ntp/                       # chrony time sync
├── files/, templates/             # project-wide static files / Jinja templates
├── library/, filter_plugins/      # custom modules / filters, if you add any
└── docs/                          # extra notes
```

Each environment is a separate inventory directory under `inventories/`, so
`group_vars`/`host_vars` never leak between staging and production. Add new
environments by copying `inventories/staging` and adjusting hosts/vars.

## Usage

```bash
# one-time: install required collections (ansible.posix, community.general)
make install

# sanity-check connectivity to an inventory
make ping ENV=staging

# first-time setup of brand-new hosts (users, baseline, hardening)
make bootstrap ENV=staging

# full convergence run of every role
make site ENV=production
```

`ENV` defaults to `staging` and selects `inventories/$(ENV)/hosts.yml`.

Equivalent raw commands:

```bash
ansible-playbook -i inventories/staging/hosts.yml playbooks/site.yml
ansible-playbook -i inventories/production/hosts.yml playbooks/bootstrap.yml --limit webservers
```

## Roles

| Role       | Purpose                                                            |
|------------|---------------------------------------------------------------------|
| `common`   | Hostname, timezone, baseline package set, MOTD banner               |
| `users`    | Admin user accounts, SSH authorized keys, sudo grants               |
| `packages` | Package cache refresh, optional full upgrade, extra installs/removals |
| `security` | SSH hardening (`PermitRootLogin`, password auth), fail2ban, firewall |
| `ntp`      | chrony installation and time server configuration                   |

All roles expose their tunables via `roles/<role>/defaults/main.yml` — override
per-environment in `inventories/<env>/group_vars/all/main.yml`, or per-host in
`inventories/<env>/host_vars/<hostname>.yml`.

## Secrets

Don't commit secrets. Use `ansible-vault` for anything sensitive
(`vault.yml` files are already excluded via `.gitignore`):

```bash
ansible-vault create inventories/production/group_vars/all/vault.yml
ansible-playbook -i inventories/production/hosts.yml playbooks/site.yml --ask-vault-pass
```

## Linting

```bash
make lint   # yamllint + ansible-lint
```
