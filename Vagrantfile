# -*- mode: ruby -*-
# vi: set ft=ruby :

# Configuration section --------------------------------------------------------

# Adjust it if you want to use different user, e.g. "ubuntu"
HOST_USERNAME = ENV["USER"]
# HOST_USERNAME = "ubuntu"

# Get the primary host IP. You can adjust it with a static value, 
# e.g. "192.168.1.10"
#HOST_IP = `ip route get 8.8.8.8 | head -1 | cut -z -d' ' -f7`
HOST_IP = OAM_NETWORK_PREFIX + "1"

OAM_NETWORK_PREFIX = "192.168.10."  # Operation and Maintenance (OAM) network
FIP_NETWORK_PREFIX = "192.168.11."  # FloatingIP network

MAAS_IP = OAM_NETWORK_PREFIX + "2"

# Define number of MAAS zones
MAAS_ZONES_COUNT = 3

# Operations and Management (OAM) network MAAS DHCP range
OAM_DYNAMIC_RANGE_START = OAM_NETWORK_PREFIX + "200"
OAM_DYNAMIC_RANGE_END   = OAM_NETWORK_PREFIX + "254"

# OAM network reserved range (for gateway and MAAS)
OAM_RESERVED_RANGE_START = OAM_NETWORK_PREFIX + "1"
OAM_RESERVED_RANGE_END   = OAM_NETWORK_PREFIX + "9"

# Total number of Cloud Nodes
CLOUD_NODES_COUNT = 6

# Total number of Juju Nodes
MGMT_NODES_COUNT = 1

# CPU and RAM configuration for Cloud Nodes
# Adjust the values that would fit into your host's capacity. Note that if you 
# want to deploy e.g. OpenStack on MAAS, and then spin up VMs on OpenStack, you 
# need to significantly bump up RAM and CPUs for Cloud Nodes.
CLOUD_NODE_CPUS   = 2  # vCPUs per Cloud Node
CLOUD_NODE_MEMORY = 2048  # 4GB plus ~200MB headroom 

# CPU and RAM configuration for MGMT Nodes
MGMT_NODE_CPUS   = 1  # vCPUs for MGMT Node
MGMT_NODE_MEMORY = 2048  # 2GB 

# Local image mirror (See https://maas.io/docs/local-image-mirror)
LOCAL_IMAGE_MIRROR_URL = ""
# LOCAL_IMAGE_MIRROR_URL = "http://192.168.1.100/maas/images/ephemeral-v3/daily/"

# End of Configuration section -------------------------------------------------

Vagrant.configure("2") do |config|

  # MAAS Server
  config.ssh.insert_key = false

  config.vm.define "maas", primary: true do |maas|
    maas.vm.box = "generic/ubuntu2004"
    maas.vm.hostname = "maas"

    maas.vm.provider :libvirt do |domain|
      domain.default_prefix = ""
      domain.cpus = "2"
      domain.memory = "3144"

    maas.vm.network :private_network, ip: MAAS_IP,
      :libvirt__netmask => "255.255.255.0",
      :libvirt__forward_mode => 'nat',
      :libvirt__network_name => 'OAM',
      :libvirt__dhcp_enabled => false,
      :dhcp_enabled => false,
      :autostart => true

    # Forward MAAS GUI port for easier access
    # MAAS GUI is accessible at http://localhost:5240/MAAS/
    maas.vm.network "forwarded_port", guest: 5240, host: 5240

    # Put the SSH key on MAAS node, so that it can control host's virsh to
    # manage power of Cloud Nodes.
    maas.vm.provision :file, 
      :source => './id_rsa', :destination => '/tmp/vagrant/id_rsa'

    # Provision juju client configuration templates
    maas.vm.provision :file, 
      :source => './juju/clouds.yaml',
      :destination => '~vagrant/.local/share/juju/clouds.yaml'
      
    maas.vm.provision :file, 
      :source => './juju/credentials.yaml',
      :destination => '~vagrant/.local/share/juju/credentials.yaml'

    # Provision example Ceph juju bundle
    #maas.vm.provision :file, 
    #  :source => './ceph/bundle.yaml',
    #  :destination => '~vagrant/ceph/bundle.yaml'

    # Install required packages
    maas.vm.provision :shell, 
      :path => './scripts/010-install-packages.sh'

    # Configure SSH keys
    maas.vm.provision :shell,
      :path => './scripts/015-configure-ssh-keys.sh'

    # Configure MAAS
    maas.vm.provision "shell" do |s|
      s.path = './scripts/020-configure-maas.sh'
      s.args = [
        MAAS_IP, 
        OAM_DYNAMIC_RANGE_START, OAM_DYNAMIC_RANGE_END,
        OAM_RESERVED_RANGE_START, OAM_RESERVED_RANGE_END, 
        HOST_USERNAME, HOST_IP, OAM_NETWORK_PREFIX,
        CLOUD_NODES_COUNT, LOCAL_IMAGE_MIRROR_URL,
        MAAS_ZONES_COUNT
      ]
    end

    # Set up Juju
    maas.vm.provision "shell" do |s|
      s.path = './scripts/030-setup-juju.sh'
      s.args = [MAAS_IP]
    end

    maas.vm.post_up_message = 
      "Congratulations! MAAS server has been successfully installed and\n" \
      "provisioned. Commissioning of the Cloud Nodes is most likely in\n" \
      "progress now.\n\n" \
      "Access MAAS GUI by visiting " \
      "http://${MAAS_IP}:5240/MAAS\n" \
      "Username: root\nPassword: root"

  end

  #PXE nodes
    (1..CLOUD_NODES_COUNT).each do |i|
      config.vm.define "node#{"%02d" % i}" do |node|

        node.vm.network :private_network, ip: OAM_NETWORK_PREFIX + "#{i+10}",
          :libvirt__forward_mode => 'nat',
          :libvirt__network_name => 'OAM',
          :libvirt__dhcp_enabled => false,
          :dhcp_enabled => false,
          :autostart => true,
          :mac => "0e00000000#{"%02d" % i}"

        node.vm.network :private_network, ip: FIP_NETWORK_PREFIX + "#{i+10}",
          :libvirt__netmask => "255.255.255.0",
          :libvirt__forward_mode => 'nat',
          :libvirt__network_name => 'FloatingIP',
          :libvirt__dhcp_enabled => false,
          :autostart => true

        node.vm.provider :libvirt do |domain|
          domain.default_prefix = ""
          domain.cpus = CLOUD_NODE_CPUS
          domain.memory = CLOUD_NODE_MEMORY
          domain.storage :file, :size => '16G', :bus => 'scsi'  # Operating System
          domain.storage :file, :size => '16G', :bus => 'scsi'  # Data disk (e.g. for Ceph OSD)
          boot_network = {'network' => 'OAM'}
          domain.boot boot_network
          domain.autostart = false
          domain.mgmt_attach = false
        end

      end
    end

      #juju node
    (1..MGMT_NODES_COUNT).each do |i|
      config.vm.define "jujunode#{"%02d" % i}" do |jujunode|

        jujunode.vm.network :private_network, ip: OAM_NETWORK_PREFIX + "#{i+01}",
          :libvirt__forward_mode => 'nat',
          :libvirt__network_name => 'OAM',
          :libvirt__dhcp_enabled => false,
          :dhcp_enabled => false,
          :autostart => true,
          :mac => "0e00000001#{"%02d" % i}"

        jujunode.vm.provider :libvirt do |domain|
          domain.default_prefix = ""
          domain.cpus = MGMT_NODE_CPUS
          domain.memory = MGMT_NODE_MEMORY
          domain.storage :file, :size => '40G', :bus => 'scsi'  # Operating System
          boot_network = {'network' => 'OAM'}
          domain.boot boot_network
          domain.autostart = false
          domain.mgmt_attach = false
        end

      end
    end

end
