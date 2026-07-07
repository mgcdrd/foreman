.PHONY: deploy storage lvm certs install config syncplans repos lifecycle infra provisioning hostgroups check list help

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
	@echo "Targets: deploy storage lvm certs install config"
	@echo "         syncplans repos lifecycle infra provisioning hostgroups"
	@echo "         check list"
