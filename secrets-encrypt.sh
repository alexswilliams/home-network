#!/usr/bin/env bash

set -ex

tar cJf secrets.tar.xz playbooks/files/monitoring/config/homepower/credentials.yaml
gpg --yes --symmetric -a -o secrets.tar.xz.asc secrets.tar.xz
rm -f secrets.tar.xz
