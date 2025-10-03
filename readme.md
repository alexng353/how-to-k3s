# How to Kubernetes

## Setup/Installation (of *each* host machine)

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

## Preparation for Kubernetes

1. Rename your NIC + Set a static IP:

If you want a static IP, either
- use dhcp4 with static lease, or
- set a static ip in netplan config

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
        macaddress: "<MAC ADDRESS>"
      set-name: kubevip0
      dhcp4: true # either use dhcp4 with static lease, or set a static ip
      # addresses:
      #   - 192.168.72.101/24
```

> We use the same name for the interface so that we don't have to worry about
> changing the config file for each node.

```bash
sudo netplan try # make sure you didn't fuck the machine
```

## Installing Kubernetes

> Please remember to follow the instructions because they are unique for each
> machine.

1. Installing k3s on the first node: 
```bash
curl -sfL https://get.k3s.io | sh -
TOKEN=$(sudo cat /var/lib/rancher/k3s/server/node-token)
echo "$TOKEN"
```

2. On *subsequent* nodes, run:
```bash
export TOKEN="<token from first node>"
export IP="<ip address of first node>"
curl -sfL https://get.k3s.io | K3S_URL="https://$IP:6443" K3S_TOKEN="$TOKEN" INSTALL_K3S_EXEC="server" sh -
```

3. Sanity check

On the first node:
```bash
sudo kubectl get nodes
```

## Installing kube-vip as a static pod

> Run on **EVERY** node

Creates a highly available IP address for the cluster.

1. Copy the `kube-vip.yaml` file into the manifests directory:

```bash
cat kube-vip.yaml | clipcopy

# Yeah
ssh ubuntu@my-node
sudo mkdir -p /etc/rancher/k3s/server/manifests
sudo vi /var/lib/rancher/k3s/server/manifests/kube-vip.yaml
```

**DO THIS ON EVERY FUCKING MACHINE**

Don't forget to modify the IP address in the address field (Grep for "-name:
address"). You should be using the interface name of the interface you just
renamed.

2. Adding tls certs

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

# Don't forget this one
sudo systemctl restart k3s
```

3. Sanity: validate tls certs

On your mac, or other non-k3s machine, run:

```bash
openssl s_client -connect 192.168.72.99:6443 -servername 192.168.72.99 </dev/null 2>/dev/null \
 | openssl x509 -noout -text | grep -A1 "Subject Alternative Name"
```

4. Sanity check

On the first node:
```bash
sudo kubectl get nodes
```

## Setting up kubectl on a management device
1. Installing + setting up kubectl on a separate device

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

Moving forwards, we can use the kubectl on the mac to interact with the cluster

## Installing rook-ceph

> Run from your mac, now that it's all set up


> You can try to get ChatGPT to help you with this, but following the
> instructions below will yield similar (or better) results.

You **MUST** have at least one device per machine that is not used for the
operating system.

1. Check the devices on each node:

```bash
$ lsblk
NAME        MAJ:MIN RM   SIZE RO TYPE MOUNTPOINTS
nvme1n1     259:0    0 931.5G  0 disk
├─nvme1n1p1 259:1    0     1G  0 part /boot/efi
└─nvme1n1p2 259:2    0 930.5G  0 part /
nvme0n1     259:3    0   1.8T  0 disk
```

If you are using nvme for your boot drive, and SATA devices for the rest of the
drives, you can match your devices using a regex:

```yaml
storage:
  useAllNodes: true
  useAllDevices: false
  deviceFilter: "^sd[a-z]" # the regex in question
```

If you are using nvme devices for all of your drives, you can check out the
standard configuration in the `ceph-cluster.yaml` file. It looks something like
this:

```yaml
storage:
  useAllNodes: true
  useAllDevices: false
  nodes:
    - name: hudson
      devices:
        - name: "/dev/disk/by-id/nvme-CT2000P310SSD8_252050102238"
    - name: jesse
      devices:
        - name: "/dev/disk/by-id/nvme-CT2000P310SSD8_25205010198F"
    - name: martin
      devices:
        - name: "/dev/disk/by-id/nvme-CT2000P310SSD8_252050101853"
  config:
    osdsPerDevice: "1"
```

In order to find the device name, you should use `ls -la /dev/disk/by-id/` and
`lsblk` together. You should be able to discern the correct device by checking
against the `lsblk` output. Take great care that the device in question does not
already have a filesystem (or any partitions) on it. If it does, you will need
to sanitize them (see below).

```bash
$ ls -la /dev/disk/by-id/
total 0
drwxr-xr-x 2 root root 280 Oct  2 04:09 .
drwxr-xr-x 7 root root 140 Oct  2 04:09 ..
lrwxrwxrwx 1 root root  13 Oct  2 04:09 nvme-CT1000P310SSD8_25205011379B -> ../../nvme1n1
lrwxrwxrwx 1 root root  13 Oct  2 04:09 nvme-CT1000P310SSD8_25205011379B_1 -> ../../nvme1n1
lrwxrwxrwx 1 root root  15 Oct  2 04:09 nvme-CT1000P310SSD8_25205011379B_1-part1 -> ../../nvme1n1p1
lrwxrwxrwx 1 root root  15 Oct  2 04:09 nvme-CT1000P310SSD8_25205011379B_1-part2 -> ../../nvme1n1p2
lrwxrwxrwx 1 root root  15 Oct  2 04:09 nvme-CT1000P310SSD8_25205011379B-part1 -> ../../nvme1n1p1
lrwxrwxrwx 1 root root  15 Oct  2 04:09 nvme-CT1000P310SSD8_25205011379B-part2 -> ../../nvme1n1p2
lrwxrwxrwx 1 root root  13 Oct  2 04:09 nvme-CT2000P310SSD8_252050101853 -> ../../nvme0n1
lrwxrwxrwx 1 root root  13 Oct  2 04:09 nvme-CT2000P310SSD8_252050101853_1 -> ../../nvme0n1
lrwxrwxrwx 1 root root  13 Oct  2 04:09 nvme-eui.000000000000000100a0752550101853 -> ../../nvme0n1
lrwxrwxrwx 1 root root  13 Oct  2 04:09 nvme-eui.00a075015011379b -> ../../nvme1n1
lrwxrwxrwx 1 root root  15 Oct  2 04:09 nvme-eui.00a075015011379b-part1 -> ../../nvme1n1p1
lrwxrwxrwx 1 root root  15 Oct  2 04:09 nvme-eui.00a075015011379b-part2 -> ../../nvme1n1p2
$ lsblk
NAME        MAJ:MIN RM   SIZE RO TYPE MOUNTPOINTS
nvme1n1     259:0    0 931.5G  0 disk
├─nvme1n1p1 259:1    0     1G  0 part /boot/efi
└─nvme1n1p2 259:2    0 930.5G  0 part /
nvme0n1     259:3    0   1.8T  0 disk
```

**Sanitizing the devices**

```bash
# DANGEROUS: wipes the disk you point at. Replace sdX/nvmeXnY with the correct device.
sudo sgdisk --zap-all /dev/sdX
sudo dd if=/dev/zero of=/dev/sdX bs=1M count=100 oflag=direct,dsync
sudo partprobe /dev/sdX
```

2. Modify the `ceph-cluster.yaml` file to match your devices, according to the
   above information.

3. Apply the changes:

```bash
kubectl apply -f ceph-cluster.yaml
```

