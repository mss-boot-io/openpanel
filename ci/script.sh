#!/bin/bash

set -e

command -v wget >/dev/null || {
  echo "wget not found, please install it and try again."
  exit 1
}

if [ ! -f "1pctl" ]; then
  wget https://github.com/1Panel-dev/installer/raw/v2/1pctl
fi

if [ ! -f "install.sh" ]; then
  wget https://github.com/1Panel-dev/installer/raw/v2/install.sh
fi

if [ ! -d "initscript" ]; then
  wget https://github.com/1Panel-dev/installer/raw/v2/initscript/1panel-core.service
  wget https://github.com/1Panel-dev/installer/raw/v2/initscript/1panel-agent.service
  mkdir -p initscript && cd initscript
  for file in 1panel-core.init 1panel-agent.init 1panel-core.openrc 1panel-agent.openrc 1panel-core.procd 1panel-agent.procd 1panel-core.service 1panel-agent.service; do
    wget -q https://github.com/1Panel-dev/installer/raw/v2/initscript/$file
  done
  cd ..
fi

if [ ! -d "lang" ]; then
  mkdir -p lang && cd lang
  for lang in en fa pt-BR ru zh; do
    wget -q https://github.com/1Panel-dev/installer/raw/v2/lang/$lang.sh
  done
  cd ..
fi

if [ ! -f "GeoIP.mmdb" ]; then
  wget https://resource.fit2cloud.com/1panel/package/v2/geo/GeoIP.mmdb
fi

chmod 755 1pctl install.sh
