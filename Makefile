.PHONY: deploy storage lvm certs install config syncplans repos lifecycle infra provisioning hostgroups check list help bootstrap-common

COMMON_ENV  ?= lab
COMMON_REPO ?= https://gitlab.lab.example.com/ansible/inventory-common.git

# Pulls shared, non-secret environment constants (domain, Vault address,
# GitLab URL, IPA realm) from the central inventory-common repo — see
# https://gitlab.lab.example.com/ansible/inventory-common for the full
# rationale. Symlinked into group_vars/all so it merges automatically;
# deployment-specific env.yml still loads after and can override any key.
bootstrap-common:
	test -d inventory-common \
	  && (cd inventory-common && git pull) \
	  || git clone $(COMMON_REPO) inventory-common
	ln -sf ../../../inventory-common/environments/$(COMMON_ENV).yml inventory/group_vars/all/00-common.yml

deploy:
	ansible-playbook site.yml

storage:
	ansible-playbook site.yml --tags storage

lvm:
	ansible-playbook site.yml --tags lvm

certs:
	ansible-playbook site.yml --tags certs

install:
	ansible-playbook site.yml --tags foreman_install

config:
	ansible-playbook site.yml --tags foreman_config

syncplans:
	ansible-playbook site.yml --tags syncplans

repos:
	ansible-playbook site.yml --tags repos

lifecycle:
	ansible-playbook site.yml --tags lifecycle

infra:
	ansible-playbook site.yml --tags infra

provisioning:
	ansible-playbook site.yml --tags provisioning

hostgroups:
	ansible-playbook site.yml --tags hostgroups

check:
	ansible-playbook site.yml --syntax-check
	ansible-lint site.yml

list:
	ansible-playbook site.yml --list-tasks

help:
	@echo "Targets: bootstrap-common deploy storage lvm certs install config"
	@echo "         syncplans repos lifecycle infra provisioning hostgroups"
	@echo "         check list"
