ENV ?= staging
INVENTORY = inventories/$(ENV)/hosts.yml

VENV   := .venv
PYTHON := python3
ANSIBLE_PLAYBOOK := $(VENV)/bin/ansible-playbook
ANSIBLE_GALAXY    := $(VENV)/bin/ansible-galaxy
YAMLLINT          := $(VENV)/bin/yamllint
ANSIBLE_LINT      := $(VENV)/bin/ansible-lint

.PHONY: setup install lint ping bootstrap site devtools clean

# Everything below depends on `setup`, so a fresh clone needs nothing but
# python3 installed system-wide: no sudo, no system package manager, no
# global pip install. Ansible itself lives in .venv/, Galaxy collections
# live in collections/ - both local to this repo and gitignored.
setup: $(VENV)/bin/activate

$(VENV)/bin/activate: requirements.txt requirements-dev.txt requirements.yml
	$(PYTHON) -m venv $(VENV)
	$(VENV)/bin/pip install --upgrade pip
	$(VENV)/bin/pip install -r requirements-dev.txt
	$(ANSIBLE_GALAXY) collection install -r requirements.yml
	touch $(VENV)/bin/activate

install: setup

lint: setup
	$(YAMLLINT) .
	$(ANSIBLE_LINT)

ping: setup
	$(ANSIBLE_PLAYBOOK) -i $(INVENTORY) playbooks/ping.yml

bootstrap: setup
	$(ANSIBLE_PLAYBOOK) -i $(INVENTORY) playbooks/bootstrap.yml

site: setup
	$(ANSIBLE_PLAYBOOK) -i $(INVENTORY) playbooks/site.yml

devtools: setup
	$(ANSIBLE_PLAYBOOK) -i $(INVENTORY) playbooks/devtools.yml

clean:
	rm -rf $(VENV) collections
