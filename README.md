# ansible-bootstrap-kit

Reusable Ansible scaffold for the baseline stuff every org needs on every host:
users, packages, security hardening, time sync, and a common inventory layout.
Fork/clone this as the starting point for a new environment instead of
rebuilding the structure each time.

This README is written so that someone brand new to Ansible can follow it
top to bottom and actually get a server configured. If you already know
Ansible, skip to [Layout](#layout) and [Usage](#usage).

---

## 0. Concepts, in plain words

- **Control node** — the machine you run `ansible`/`ansible-playbook` from
  (your laptop, a CI runner, a bastion host). Only this machine needs
  Ansible installed.
- **Managed node / target** — a server Ansible configures over SSH. It only
  needs SSH + Python installed — no agent.
- **Inventory** — the list of managed nodes, organized into **groups**
  (e.g. `webservers`, `dbservers`). In this repo that's
  `inventories/<env>/hosts.yml`.
- **Playbook** — a YAML file describing what to do (`playbooks/*.yml`).
- **Role** — a reusable, named bundle of tasks (`roles/*`), e.g. the
  `security` role always does SSH hardening + firewall, regardless of which
  playbook calls it.
- **`group_vars` / `host_vars`** — variables applied automatically to every
  host in a group, or to one specific host.

Everything below assumes Linux/macOS as the control node. Target machines
can be any Linux distro supported by the roles (Debian/Ubuntu or RHEL/Rocky/Alma).

---

## 1. Set up the toolchain (control node only — one command, nothing system-wide)

This kit is fully self-contained: you do **not** need `sudo apt install ansible`
or `sudo dnf install ansible-core` on your machine. The only prerequisite is
`python3` (with the `venv` module, which is part of the standard library on
every mainstream distro). Everything else — Ansible itself, the lint tools,
the Galaxy collections — gets installed *inside this repo*, in a local
`.venv/` and `collections/` directory, and is never touched outside it.

```bash
make setup
```

This one command:
1. Creates a virtualenv at `.venv/` (local to this repo, gitignored).
2. Installs `ansible-core`, `ansible-lint`, and `yamllint` into it from
   `requirements.txt` / `requirements-dev.txt` — pinned versions, so every
   clone of this repo gets the same toolchain.
3. Installs the Galaxy collections this kit depends on (`ansible.posix`,
   `community.general` — used for things like the firewall and timezone
   modules) into `collections/` from `requirements.yml`.

You never need to run `make setup` manually in normal use — every other
`make` target (`ping`, `bootstrap`, `site`, `lint`) depends on it and will
run it automatically the first time, then reuse it. It's safe to re-run any
time (e.g. after someone updates `requirements.txt`).

Confirm it worked:

```bash
.venv/bin/ansible --version
```

If you ever want to wipe it and start over (e.g. to test a clean clone):

```bash
make clean   # removes .venv/ and collections/
```

### Activate the venv (so you can type `ansible-playbook` instead of `.venv/bin/ansible-playbook`)

Every raw command in the rest of this README (`ansible`, `ansible-playbook`,
`ansible-inventory`, `ansible-vault`, ...) assumes the venv is active in your
shell. Do this once per terminal session, after `make setup` has run at least
once:

```bash
source .venv/bin/activate
```

Your prompt will usually change to show `(.venv)`. Run `deactivate` to leave
it. If you'd rather not activate and just run one-off commands, prefix them
with `.venv/bin/` instead, e.g. `.venv/bin/ansible-playbook ...` — that's
exactly what the `make` targets do under the hood, which is why they work
with no activation needed.

---

## 2. Set up your inventory and groups

The inventory is just a list of servers, grouped by role. Open
`inventories/staging/hosts.yml`:

```yaml
all:
  children:
    webservers:
      hosts:
        gmr-stg-01:
        gmr-stg-02:
    dbservers:
      hosts:
        gmr-stg-03:
  vars:
    env: staging
```

- `webservers` and `dbservers` are **groups** — just names you invent to
  target playbooks/variables at a subset of hosts.
- Each line under `hosts:` is one server. `gmr-stg-01`/`02`/`03` here follow
  an org naming convention (`<project>-<env>-<number>`) — `inventories/production/hosts.yml`
  mirrors it as `prd-gmr-01`/`02`/`03`. These names must resolve via DNS or
  `/etc/hosts` on your control node; if yours don't, either add them there or
  swap in real hostnames/IP addresses instead, e.g.:

```yaml
all:
  children:
    webservers:
      hosts:
        10.0.1.10:
        10.0.1.11:
    dbservers:
      hosts:
        10.0.2.10:
  vars:
    env: staging
```

### Adding a new group

Just add another key under `children:`:

```yaml
    loadbalancers:
      hosts:
        gmr-stg-04:
```

Groups matter because:
1. You can target them with `--limit webservers` or `hosts: webservers` in a playbook.
2. You can set group-only variables in `inventories/<env>/group_vars/<groupname>.yml`
   (create that file — right now only `group_vars/all/` exists, which applies
   to *every* host regardless of group).

### Adding a new environment

Copy the whole `inventories/staging` directory:

```bash
cp -r inventories/staging inventories/qa
# then edit inventories/qa/hosts.yml and inventories/qa/group_vars/all/main.yml
```

### List what Ansible sees

Before doing anything else, sanity-check your inventory file is valid and
shows the hosts/groups you expect:

```bash
ansible-inventory -i inventories/staging/hosts.yml --list
ansible-inventory -i inventories/staging/hosts.yml --graph
```

`--graph` gives a quick tree view like:

```
@all:
  |--@webservers:
  |  |--gmr-stg-01
  |  |--gmr-stg-02
  |--@dbservers:
  |  |--gmr-stg-03
```

---

## 3. Set up passwordless SSH authentication

Ansible connects over plain SSH. By default it will prompt for a password on
every single task, which is slow and breaks automation — so the normal setup
is **SSH key-based login**. Do this once per control-node ↔ target pair.

### Step 1 — generate a key pair (control node, skip if you already have one)

```bash
ssh-keygen -t ed25519 -C "ansible-control" -f ~/.ssh/id_ed25519
# press Enter through the passphrase prompt if you want a fully unattended key
```

This creates:
- `~/.ssh/id_ed25519` — your **private** key (never share/commit this).
- `~/.ssh/id_ed25519.pub` — your **public** key (safe to share, this is what
  goes on the servers).

### Step 2 — copy the public key to each target server

You still need a password (or existing key) the *first* time, to install
your new key:

```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub user@gmr-stg-01
```

If `ssh-copy-id` isn't available (e.g. some minimal images), do it manually:

```bash
cat ~/.ssh/id_ed25519.pub | ssh user@gmr-stg-01 \
  "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

### Step 3 — prove it works without a password

```bash
ssh user@gmr-stg-01
```

You should land in a shell with **no password prompt**. If it still asks for
a password, see [Troubleshooting](#troubleshooting) below.

### Step 4 — tell Ansible which user/key to use

If your SSH user differs from your local username, or you use a non-default
key path, set it per-environment in
`inventories/<env>/group_vars/all/main.yml`:

```yaml
ansible_user: user
ansible_ssh_private_key_file: ~/.ssh/id_ed25519
```

(If your username and default key already match, you can skip this.)

### Step 5 — passwordless `sudo` (needed because this kit uses `become: true`)

Every playbook here runs with `become: true` (see `ansible.cfg`), meaning
tasks run as root via `sudo`. If `sudo` on the target asks for a password,
Ansible will fail or hang. Set up passwordless sudo for your SSH user **on
the target**, once:

```bash
ssh user@gmr-stg-01
echo "user ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/90-user
sudo visudo -cf /etc/sudoers.d/90-user   # validates the syntax, must say "OK"
exit
```

> This is exactly what the `users` role's `sudo_nopasswd: true` flag
> automates for *new* admin accounts you create with Ansible — but your
> very first connecting user has to get this manually, since nothing has
> run yet.

If you'd rather not grant full passwordless sudo, you can instead run
Ansible with `--ask-become-pass` and type the sudo password once per run —
slower, but works without the sudoers change:

```bash
ansible-playbook -i inventories/staging/hosts.yml playbooks/ping.yml --ask-become-pass
```

---

## 4. Check connectivity

Now confirm Ansible can actually reach every host in the inventory and run
a module on it.

### Quick ad-hoc ping (no playbook needed)

```bash
ansible all -i inventories/staging/hosts.yml -m ping
```

Expected output per host:

```
gmr-stg-01 | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python3"
    },
    "changed": false,
    "ping": "pong"
}
```

`"ping": "pong"` = that host is reachable, authenticated, and can run
Python modules. Anything else (`UNREACHABLE!`, `FAILED!`) means something in
steps 2–3 above isn't right yet — see [Troubleshooting](#troubleshooting).

### Playbook version (also gathers and prints OS facts)

```bash
make ping ENV=staging
# same as: ansible-playbook -i inventories/staging/hosts.yml playbooks/ping.yml
```

Only move on to step 5 once every host shows success here.

---

## 5. Run the playbooks

There are two playbooks, for two different situations:

| Playbook            | When to use it                                                              | Roles it runs                          |
|----------------------|------------------------------------------------------------------------------|-----------------------------------------|
| `playbooks/bootstrap.yml` | **First time** touching a brand-new server: create admin users, apply baseline config, lock down SSH. | `common`, `users`, `security`          |
| `playbooks/site.yml`      | **Every time after that** — the full, repeatable convergence run (also keeps packages and NTP in sync). | `common`, `users`, `packages`, `security`, `ntp` |

### Always dry-run first

`--check` simulates the run without changing anything; `--diff` shows what
*would* change, line by line. Get in the habit of running this before every
real run, especially against production:

```bash
ansible-playbook -i inventories/staging/hosts.yml playbooks/site.yml --check --diff
```

Read the output. Anything listed as `changed` is a change that *would* be
made for real. If that all looks correct, drop `--check --diff` and run it
for real:

```bash
make bootstrap ENV=staging     # first-time setup
make site ENV=staging          # day-2 convergence
```

Or with raw `ansible-playbook`:

```bash
ansible-playbook -i inventories/staging/hosts.yml playbooks/bootstrap.yml
ansible-playbook -i inventories/production/hosts.yml playbooks/site.yml
```

`ENV` in the `Makefile` targets just picks which `inventories/<ENV>/hosts.yml`
to use — it defaults to `staging` if you don't pass it.

### Useful flags while you're learning

| Flag | What it does |
|------|---------------|
| `--limit webservers` | Only run against hosts in the `webservers` group (or a single host: `--limit gmr-stg-01`) |
| `-v`, `-vvv` | More verbose output — `-vvv` shows the actual module arguments and SSH commands, great for debugging |
| `--check --diff` | Dry run, shows what would change (see above) |
| `--tags` / `--skip-tags` | Run (or skip) only tasks tagged a certain way, if you add tags |
| `--step` | Confirm each task one at a time before it runs |

Example — dry-run just the hardening step against one web server, verbosely:

```bash
ansible-playbook -i inventories/staging/hosts.yml playbooks/site.yml \
  --limit gmr-stg-01 --tags security --check --diff -vv
```

---

## 6. Verify the results

After a real run, spot-check that things actually took effect, using
ad-hoc commands (no playbook needed):

```bash
# confirm hostname was set
ansible all -i inventories/staging/hosts.yml -m command -a "hostname"

# confirm timezone
ansible all -i inventories/staging/hosts.yml -m command -a "timedatectl"

# confirm the admin user exists and is in the sudo group
ansible all -i inventories/staging/hosts.yml -m command -a "id ansible"

# confirm sshd config took effect (should show your hardened values)
ansible all -i inventories/staging/hosts.yml -m command -a "sshd -T" --become

# confirm fail2ban / firewall service is active
ansible all -i inventories/staging/hosts.yml -m command -a "systemctl is-active fail2ban"
ansible all -i inventories/staging/hosts.yml -m command -a "ufw status verbose" --become
```

Also check idempotency — re-running the exact same playbook a second time
should report `changed=0` for everything, since the state Ansible wants
already exists:

```bash
ansible-playbook -i inventories/staging/hosts.yml playbooks/site.yml
```

Look at the `PLAY RECAP` at the bottom: `changed=0, failed=0` means the
system is already in the desired state — that's the goal.

---

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| `Permission denied (publickey,password)` | Your public key isn't in `~/.ssh/authorized_keys` on the target yet. Redo step 3.2, or check `ansible_user`/`ansible_ssh_private_key_file` are set correctly. |
| `Host key verification failed` | First-time connection to a host Ansible/SSH hasn't seen before. Run `ssh user@host` once manually and accept the fingerprint, or set `host_key_checking = False` in `ansible.cfg` for throwaway lab environments (not recommended for production). |
| Hangs or asks for a sudo password | Passwordless sudo isn't set up (step 3.5). Either fix sudoers, or pass `--ask-become-pass`. |
| `/usr/bin/python3: No such file or directory` | Target has no Python 3. Install it (`apt install python3` / `dnf install python3`), or set `ansible_python_interpreter` explicitly in `group_vars`. |
| `UNREACHABLE!` with a timeout | Network/firewall is blocking port 22, or the IP/hostname in `hosts.yml` is wrong. Try `ssh user@host` manually first — if that fails too, it's not an Ansible problem. |
| Module fails only in `--check` mode | Some modules (ones that read live state, like `command`/`shell`) can't be simulated. That's expected — ignore `--check` warnings on those, focus on real-run output. |

---

## Layout

```
.
├── ansible.cfg                  # project-local Ansible config (points at staging by default)
├── requirements.txt              # pinned Python deps (ansible-core) for the local venv
├── requirements-dev.txt          # + lint tools (ansible-lint, yamllint), for `make lint`
├── requirements.yml              # Galaxy collections this kit depends on
├── Makefile                      # setup / lint / ping / bootstrap / site / clean shortcuts
├── .venv/                        # created by `make setup` — local Ansible install, gitignored
├── inventories/
│   ├── staging/
│   │   ├── hosts.yml              # staging inventory (groups + hosts)
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
`group_vars`/`host_vars` never leak between staging and production.

## Usage

```bash
# one-time: create .venv/ + collections/, install Ansible/lint tools/collections into them
make setup

# sanity-check connectivity to an inventory
make ping ENV=staging

# first-time setup of brand-new hosts (users, baseline, hardening)
make bootstrap ENV=staging

# full convergence run of every role
make site ENV=production
```

`ENV` defaults to `staging` and selects `inventories/$(ENV)/hosts.yml`. You
don't need to run `make setup` separately — `ping`/`bootstrap`/`site`/`lint`
all depend on it and will set things up automatically on first use.

Equivalent raw commands (after `source .venv/bin/activate`, see
[step 1](#1-set-up-the-toolchain-control-node-only--one-command-nothing-system-wide)):

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
