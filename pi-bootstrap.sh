#!/usr/bin/env bash


# Pre-tasks:
# - Installed base OS onto card
# - Have SSH'd to it at least once (sshpass doesn't support missing hostkeys)
# - Initialised the keyring (see pacman-init, but roughly `pacman-key --init && pacman-key --populate archlinuxarm`)
# - Fetched latest package database and upgraded (`pacman -Syu`)
# - Installed python (`pacman -S python`)

ansible-playbook playbooks/pi-bootstrap.yaml
