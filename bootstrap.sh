#!/bin/bash
echo -e "\n# \e[1;34mInstall made by \e[1;31m@PAPAMICA__ \e[1;34mwith documentation of \e[1;31m@TheBidouilleur \e[0m\n\e[0m
\e[32m# Documentation (in french) : https://une-tasse-de.cafe/blog/talos/\e[0m\n\e[0m
\e[32m# Infomaniak Public Cloud's documentation : https://docs.infomaniak.cloud/\e[0m\n\e[0m
\e[36m# Follow the commands below to install the cluster:\e[0m\n\e[0m
# Generate secrets
\e[33mtalosctl gen secrets\n\e[0m
# Generate configuration for the cluster
\e[33mtalosctl gen config mycluster https://10.10.0.11:6443 --with-secrets ./secrets.yaml --install-disk /dev/vda\n\e[0m
# Apply control plane configuration to nodes
\e[33mtalosctl apply-config --insecure -n 10.10.0.11 -e 10.10.0.11 --file controlplane.yaml
\e[33mtalosctl apply-config --insecure -n 10.10.0.12 -e 10.10.0.12 --file controlplane.yaml
\e[33mtalosctl apply-config --insecure -n 10.10.0.13 -e 10.10.0.13 --file controlplane.yaml\n\e[0m
# Apply worker configuration to nodes
\e[33mtalosctl apply-config --insecure -n 10.10.0.51 -e 10.10.0.51 --file worker.yaml
\e[33mtalosctl apply-config --insecure -n 10.10.0.52 -e 10.10.0.52 --file worker.yaml\n\e[0m
# Configure endpoints and nodes
\e[33mtalosctl --talosconfig=./talosconfig config endpoint 10.10.0.11 10.10.0.12 10.10.0.13
\e[33mtalosctl --talosconfig=./talosconfig config node 10.10.0.11 10.10.0.12 10.10.0.13 10.10.0.51 10.10.0.52
\e[33mtalosctl config merge ./talosconfig\n\e[0m
# Check system messages
\e[33mtalosctl dmesg\n\e[0m
# Bootstrap the cluster
\e[33mtalosctl bootstrap -e 10.10.0.11 --talosconfig ./talosconfig --nodes 10.10.0.11\n\e[0m
# Retrieve kubeconfig for the cluster
\e[33mtalosctl kubeconfig -e 10.10.0.11 --talosconfig ./talosconfig --nodes 10.10.0.11\n\e[0m
# Verify nodes are ready
\e[33mkubectl get nodes\n\e[0m" > /etc/motd

su debian
cd /home/debian

curl -sL https://talos.dev/install | sh

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && rm kubectl


sudo wget -qO- https://github.com/derailed/k9s/releases/download/v0.32.3/k9s_Linux_amd64.tar.gz | sudo tar xvz -C /usr/local/bin/



