sudo apt update -y
sudo apt upgrade -y

sudo apt install -y \
  btop \
  neofetch \
  bat \
  zsh \
  net-tools

echo "choose vim.basic or something"
sudo update-alternatives --config editor

curl -fsSL https://tailscale.com/install.sh | sh
curl -sfL https://get.k3s.io | sh -

printf '%s\n' 'ubuntu ALL=(ALL:ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/ubuntu > /dev/null \
  && sudo chmod 0440 /etc/sudoers.d/ubuntu \
  && sudo visudo -c -f /etc/sudoers.d/ubuntu

sudo chsh -s /bin/zsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" -y
sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="jispwoso"/' ~/.zshrc

