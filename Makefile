LAB_ENV := ../../DevOps_new/lab-env/env.yml

.PHONY: deploy storage lvm baseline ipa certs install config check list help

deploy:
	ansible-playbook site.yml -e @$(LAB_ENV)

storage:
	ansible-playbook site.yml -e @$(LAB_ENV) --tags storage

lvm:
	ansible-playbook site.yml -e @$(LAB_ENV) --tags lvm

baseline:
	ansible-playbook site.yml -e @$(LAB_ENV) --tags baseline

ipa:
	ansible-playbook site.yml -e @$(LAB_ENV) --tags ipa_client

certs:
	ansible-playbook site.yml -e @$(LAB_ENV) --tags certs

install:
	ansible-playbook site.yml -e @$(LAB_ENV) --tags foreman_install

config:
	ansible-playbook site.yml -e @$(LAB_ENV) --tags foreman_config

syncplans:
	ansible-playbook site.yml -e @$(LAB_ENV) --tags syncplans

repos:
	ansible-playbook site.yml -e @$(LAB_ENV) --tags repos

lifecycle:
	ansible-playbook site.yml -e @$(LAB_ENV) --tags lifecycle

infra:
	ansible-playbook site.yml -e @$(LAB_ENV) --tags infra

provisioning:
	ansible-playbook site.yml -e @$(LAB_ENV) --tags provisioning

hostgroups:
	ansible-playbook site.yml -e @$(LAB_ENV) --tags hostgroups

check:
	ansible-playbook site.yml --syntax-check -e @$(LAB_ENV)
	ansible-lint site.yml

list:
	ansible-playbook site.yml -e @$(LAB_ENV) --list-tasks

help:
	@echo "Targets: deploy storage lvm baseline ipa certs install config"
	@echo "         syncplans repos lifecycle infra provisioning hostgroups"
	@echo "         check list"
