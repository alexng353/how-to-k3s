# How to Kubernetes

1. Install all of this shit:
```bash
sudo apt update -y
sudo apt upgrade -y

# using whatever package manager we end up using
sudo apt install -y \
  btop \
  neofetch \
  bat \
  zsh \
  net-tools

curl -fsSL https://tailscale.com/install.sh | sh
curl -sfL https://get.k3s.io | sh -
```

2. Run customizations:

```bash
# choose vim.basic
sudo update-alternatives --config editor

```

3. Rename the NIC + Set a static IP:

If you want a static IP, either
a. use dhcp4 with static lease, or
b. set a static ip in netplan config

```bash
ip -br link | awk '{print $1,$3}'
# select the mac address of the NIC you want to rename
```

Edit the `/etc/netplan/something.yaml` configuration file:
```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    kubevip0:
      match:
        macaddress: "10:ff:e0:a1:55:02"
      set-name: kubevip0
      dhcp4: true # either use dhcp4 with static lease, or set a static ip
      # addresses:
      #   - 192.168.72.101/24
```

```bash
sudo netplan try # make sure you didn't fuck the machine
```

4. Installing k3s on the first node: 
On the first node, run:
```bash
curl -sfL https://get.k3s.io | sh -
TOKEN=$(sudo cat /var/lib/rancher/k3s/server/node-token)
echo "$TOKEN"
```

On subsequent nodes, run:
```bash
export TOKEN="<token from first node>"
export IP="<ip address of first node>"
curl -sfL https://get.k3s.io | K3S_URL="https://$IP:6443" K3S_TOKEN="$TOKEN" INSTALL_K3S_EXEC="server" sh -
```

5. Sanity check

On the first node:
```bash
sudo kubectl get nodes
```

6. Installing kube-vip

First, copy the `kube-vip.yaml` file

Next, paste it into this file:
```bash
sudo vi /var/lib/rancher/k3s/server/manifests/kube-vip.yaml
```

Don't forget to modify the IP address in the address field (line 78). You should
be using the interface name of the interface you just renamed.

7. Adding tls certs

On each of the nodes, run:

```bash
# Create/merge k3s config
sudo mkdir -p /etc/rancher/k3s
sudo tee /etc/rancher/k3s/config.yaml >/dev/null <<'EOF'
write-kubeconfig-mode: "0644"
tls-san:
  - 192.168.72.99     # <-- your kube-vip VIP
  - 192.168.72.101    # IP of the first node
  - 192.168.72.102    # IP of the second node
  - 192.168.72.103    # IP of the third node
  - 127.0.0.1         # localhost
  - 10.43.0.1         # k3s-server
EOF

sudo systemctl restart k3s
```

8. Validate tls certs

On your mac, or other non-k3s machine, run:

```bash
openssl s_client -connect 192.168.72.99:6443 -servername 192.168.72.99 </dev/null 2>/dev/null \
 | openssl x509 -noout -text | grep -A1 "Subject Alternative Name"
```

9. Sanity check

On the first node:
```bash
sudo kubectl get nodes
```

10. Installing + setting up kubectl on a separate device

First, install kubectl on your mac:
https://kubernetes.io/docs/tasks/tools/install-kubectl-macos/

Next, copy the kubeconfig file from the first node:
```bash
# on node 1
sudo cat /etc/rancher/k3s/k3s.yaml
```

Paste it into the kubeconfig file on your mac:
```bash
# on mac
mkdir -p ~/.kube
echo "<PASTE>" >> ~/.kube/config
```

Check that it works:
```bash
# on mac
kubectl get nodes
```

11. Moving forward, we can use the kubectl on the mac to interact with the cluster
