ENV ?= staging
INVENTORY = inventories/$(ENV)/hosts.yml

.PHONY: install lint ping bootstrap site

install:
	ansible-galaxy collection install -r requirements.yml

lint:
	yamllint .
	ansible-lint

ping:
	ansible-playbook -i $(INVENTORY) playbooks/ping.yml

bootstrap:
	ansible-playbook -i $(INVENTORY) playbooks/bootstrap.yml

site:
	ansible-playbook -i $(INVENTORY) playbooks/site.yml
