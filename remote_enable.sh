sudo systemctl --user stop gnome-remote-desktop || true
sudo systemctl --user disable gnome-remote-desktop || true
sudo apt purge -y gnome-remote-desktop xrdp xfce4 xfce4-goodies || true
sudo apt autoremove -y



sudo apt update
sudo apt install -y xrdp xfce4 xfce4-goodies

# Force xrdp sessions to load Xfce
echo "startxfce4" > ~/.xsession
sudo systemctl enable --now xrdp



sudo ufw allow 3389/tcp
