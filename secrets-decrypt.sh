#!/usr/bin/env bash

set -ex

gpg --decrypt -o secrets.tar.xz secrets.tar.xz.asc
tar xJf secrets.tar.xz
rm -f secrets.tar.xz