# Define required providers
terraform {
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "1.54.1"
    }
  }
}

# Configure the OpenStack Provider
provider "openstack" {
  auth_url = "https://api.pub1.infomaniak.cloud/identity"
  region = "dc3-a"
  user_name = var.user_name
  password = var.password
  user_domain_name = "Default"
  project_domain_id = "default"
  tenant_id = var.tenant_id
  tenant_name = var.tenant_name
}

# Upload public key
resource "openstack_compute_keypair_v2" "yubikey" {
  name = var.keypair_name
  public_key = var.ssh_key
}

resource "openstack_images_image_v2" "talos" {
  name             = "Talos"
  image_source_url = "https://github.com/siderolabs/talos/releases/download/v1.6.4/metal-amd64.iso"
  container_format = "bare"
  disk_format      = "iso"
}

# Create router
resource "openstack_networking_router_v2" "front_router" {
  name = "front-router"
  admin_state_up      = true
  external_network_id = var.floating_ip_pool_id
}

resource "openstack_networking_router_interface_v2" "front_router" {
  depends_on = ["openstack_networking_subnet_v2.private_subnet", "openstack_networking_router_v2.front_router"]
  router_id = openstack_networking_router_v2.front_router.id
  subnet_id = openstack_networking_subnet_v2.private_subnet.id
}


# Add subnet
resource "openstack_networking_network_v2" "private_network" {
  name           = "private_network"
  admin_state_up = "true"
}

resource "openstack_networking_subnet_v2" "private_subnet" {
  name       = "private_subnet"
  network_id = openstack_networking_network_v2.private_network.id
  cidr       = "10.10.0.0/24"
  dns_nameservers = ["9.9.9.9","1.1.1.1"]
  ip_version = 4
  enable_dhcp = true
  allocation_pool {
    start = "10.10.0.101"
    end   = "10.10.0.200"
  }
}


resource "openstack_networking_secgroup_v2" "ssh_external" {
  name        = "SSH-EXTERNAL"
  description = "Security group for SSH external access."
}

resource "openstack_networking_secgroup_rule_v2" "ssh_external" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.ssh_external.id
}

resource "openstack_networking_secgroup_v2" "ssh_internal" {
  name        = "SSH-INTERNAL"
  description = "Security group for SSH internal access."
}

resource "openstack_networking_secgroup_rule_v2" "ssh_internal" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "10.10.0.0/24"
  security_group_id = openstack_networking_secgroup_v2.ssh_internal.id
}

resource "openstack_networking_secgroup_rule_v2" "kube_api" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6443
  port_range_max    = 6443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.ssh_internal.id
}

resource "openstack_networking_secgroup_rule_v2" "talos_api" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 50000
  port_range_max    = 50000
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.ssh_internal.id
}

resource "openstack_networking_secgroup_rule_v2" "icmp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.ssh_internal.id
}

### CONTROLPLANE INSTANCES ###
resource "openstack_compute_instance_v2" "Controlplanes" {
  depends_on = ["openstack_networking_subnet_v2.private_subnet","openstack_images_image_v2.talos"]
  count = var.controlplane_num
  name = "controlplane-${count.index + 1}"
  image_id = openstack_images_image_v2.talos.id
  flavor_id = var.controlplane_flavor
  key_pair = var.keypair_name
  security_groups = [openstack_networking_secgroup_v2.ssh_internal.name]
  network {
    name = "private_network"
    fixed_ip_v4 = "10.10.0.1${count.index + 1}"
  }
  #user_data = file("bootstrap.sh")
}

resource "openstack_blockstorage_volume_v3" "Controlplanes" {
  depends_on = ["openstack_compute_instance_v2.Controlplanes"]
  count = var.controlplane_num
  name = "controlplane_storage-${count.index + 1}"
  size = var.controlplane_volume_size
}

resource "openstack_compute_volume_attach_v2" "Controlplanes" {
  depends_on = ["openstack_blockstorage_volume_v3.Controlplanes"]
  count       = var.controlplane_num
  instance_id = openstack_compute_instance_v2.Controlplanes[count.index].id
  volume_id   = openstack_blockstorage_volume_v3.Controlplanes[count.index].id
}


### WORKER INSTANCES ###
resource "openstack_compute_instance_v2" "Workers" {
  depends_on = ["openstack_networking_subnet_v2.private_subnet","openstack_images_image_v2.talos"]
  count = var.worker_num
  name = "worker-${count.index + 1}"
  image_id = openstack_images_image_v2.talos.id
  flavor_id = var.worker_flavor
  key_pair = var.keypair_name
  security_groups = [openstack_networking_secgroup_v2.ssh_internal.name]
  network {
    name = "private_network"
    fixed_ip_v4 = "10.10.0.5${count.index + 1}"
  }
  #user_data = file("bootstrap.sh")
}

resource "openstack_blockstorage_volume_v3" "Workers" {
  depends_on = ["openstack_compute_instance_v2.Workers"]
  count = var.worker_num
  name = "worker_storage-${count.index + 1}"
  size = var.worker_volume_size
}

resource "openstack_compute_volume_attach_v2" "Workers" {
  depends_on = ["openstack_blockstorage_volume_v3.Workers"]
  count       = var.worker_num
  instance_id = openstack_compute_instance_v2.Workers[count.index].id
  volume_id   = openstack_blockstorage_volume_v3.Workers[count.index].id
}


### MANAGMENT INSTANCE ###

resource "openstack_compute_instance_v2" "Managment" {
  depends_on = [
    "openstack_networking_subnet_v2.private_subnet",
    "openstack_compute_instance_v2.Workers",
    "openstack_compute_instance_v2.Controlplanes"
  ]
  count = var.managment_num
  name = "managment-${count.index + 1}"
  image_id = var.managment_image
  flavor_id = var.managment_flavor
  key_pair = var.keypair_name
  security_groups = [openstack_networking_secgroup_v2.ssh_external.name, openstack_networking_secgroup_v2.ssh_internal.name]
  network {
    name = "private_network"
    fixed_ip_v4 = "10.10.0.20${count.index + 1}"    
  }
  user_data =  <<-EOT
#!/bin/bash
echo -e '\n# \e[1;34mInstall made by \e[1;31m@PAPAMICA__ \e[1;34mwith documentation of \e[1;31m@TheBidouilleur \e[0m\n\e[0m
\e[32m# Documentation (in french) : https://une-tasse-de.cafe/blog/talos/\e[0m\n\e[0m
\e[32m# Infomaniak Public Cloud documentation : https://docs.infomaniak.cloud/\e[0m\n\e[0m  
\nControlplanes:
${join("\n", [for instance in openstack_compute_instance_v2.Controlplanes : "${instance.name} = ${instance.network.0.fixed_ip_v4}"])}

\nWorkers:
${join("\n", [for instance in openstack_compute_instance_v2.Workers : "${instance.name} = ${instance.network.0.fixed_ip_v4}"])}\n
\nInstall logs : /var/log/cloud-init-output.log
' > /etc/motd

cd /home/debian

curl -sL https://talos.dev/install | sh

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && rm kubectl


sudo wget -qO- https://github.com/derailed/k9s/releases/download/v0.32.3/k9s_Linux_amd64.tar.gz | sudo tar xvz -C /usr/local/bin/

sudo -u debian talosctl gen secrets
sudo -u debian talosctl gen config mycluster https://10.10.0.11:6443 --with-secrets ./secrets.yaml --install-disk /dev/vda

echo -e "\nWaiting 120 seconds for initial boot"
sleep 120

${join("\n", [for instance in openstack_compute_instance_v2.Controlplanes : "sudo -u debian talosctl apply-config --insecure -n ${instance.network.0.fixed_ip_v4} -e ${instance.network.0.fixed_ip_v4} --file controlplane.yaml"])}
${join("\n", [for instance in openstack_compute_instance_v2.Workers : "sudo -u debian talosctl apply-config --insecure -n ${instance.network.0.fixed_ip_v4} -e ${instance.network.0.fixed_ip_v4} --file worker.yaml"])}

sudo -u debian talosctl --talosconfig=./talosconfig config endpoint ${join(" ", openstack_compute_instance_v2.Controlplanes[*].network.0.fixed_ip_v4)}
sudo -u debian talosctl --talosconfig=./talosconfig config node ${join(" ", openstack_compute_instance_v2.Controlplanes[*].network.0.fixed_ip_v4, openstack_compute_instance_v2.Workers[*].network.0.fixed_ip_v4)}
sudo -u debian talosctl config merge ./talosconfig
sleep 120
sudo -u debian talosctl bootstrap -e 10.10.0.11 --talosconfig ./talosconfig --nodes 10.10.0.11
sudo -u debian talosctl kubeconfig -e 10.10.0.11 --talosconfig ./talosconfig --nodes 10.10.0.11

# Function to check Kubernetes cluster status
check_cluster_status() {
    kubectl get nodes --no-headers=true | awk '$2 != "Ready" {exit 1}' >/dev/null 2>&1
}

# Wait for the cluster to be ready
while check_cluster_status; do
    echo -e "\nThe cluster is not yet ready, waiting...\n"
    sleep 10
done
echo -e "\n#######################################################\n\n         VICTORY ! YOUR K8S CLUSTER IS READY !\n\nYou can use this command to check : kubectl get nodes\n\n#######################################################"
  EOT
}

resource "openstack_networking_floatingip_v2" "fip" {
  pool = var.floating_ip_pool
}

resource "openstack_compute_floatingip_associate_v2" "fip_managment" {
  depends_on = ["openstack_networking_floatingip_v2.fip"]
  floating_ip = openstack_networking_floatingip_v2.fip.address
  instance_id = openstack_compute_instance_v2.Managment[0].id
}


output "Managment_ip" {
    value = openstack_compute_floatingip_associate_v2.fip_managment.floating_ip
    }

output "All_instance_ips" {
  value = {
    for instance_type, instances in {
      Managment = openstack_compute_instance_v2.Managment,
      Controlplanes = openstack_compute_instance_v2.Controlplanes,
      Workers = openstack_compute_instance_v2.Workers
    } : instance_type => [for instance in instances : instance.network.0.fixed_ip_v4]
  }
}
