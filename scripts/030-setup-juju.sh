#!/usr/bin/env bash

set -xe

# $1: MAAS_IP

# Install juju from snap
echo "Installing Juju..."
snap install juju --classic
snap install charm --classic

# Update juju client configuration files
echo "Updating juju client configuration files..."
MAAS_APIKEY=$(maas apikey --username admin)
sed -i 's/{{ maas_root_apikey }}/'${MAAS_APIKEY}'/g' ~vagrant/.local/share/juju/credentials.yaml
sed -i 's/{{ maas_ip }}/'$1'/g' ~vagrant/.local/share/juju/clouds.yaml

# Bootstrap juju to node with juju tag
echo 'Bootstrap juju to node with juju tag...'
juju bootstrap --constraints tags=juju mymaas maas-controller

# Create openstack juju model
echo 'Create openstack juju model...'
juju add-model --config default-series=focal openstack