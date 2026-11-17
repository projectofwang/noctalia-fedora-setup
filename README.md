# Noctalia trên Fedora minimal

Cài trọn hệ sinh thái Noctalia v5 lên Fedora 44/45 (kể cả bản minimal), chọn
Umbriel làm compositor và toàn bộ gói theo kênh nightly.

## Clone và chạy

```bash
git clone https://github.com/projectofwang/noctalia-fedora-setup.git
cd noctalia-fedora-setup
chmod +x noctalia-fedora.sh

./noctalia-fedora.sh --dry-run   # xem trước, không thay đổi gì
./noctalia-fedora.sh             # cài thật, hỏi từng bước
```

Muốn cài không hỏi lại và đổi luôn display manager sang greeter:

```bash
./noctalia-fedora.sh --yes --switch-dm
```

Script cần chạy bằng user thường (nó tự gọi `sudo`), máy phải có `git`,
`sudo`, `awk` và `dnf`.

## Hệ sinh thái gồm những gì

| Thành phần | Vai trò | Gói |
|---|---|---|
| Noctalia | Shell: bar, launcher, control center, notification, lock screen, wallpaper, OSD | `noctalia-nightly` |
| Umbriel | Compositor Wayland (wlroots), thay cho Niri/Hyprland/Sway | `umbriel-nightly` |
| xdg-desktop-portal-umbriel | Portal cho screen sharing, screenshot, global shortcuts, input capture | `xdg-desktop-portal-umbriel-nightly` |
| Luciole | File manager native Wayland, đồng thời là file picker qua portal | `luciole-nightly` |
| Noctalia Greeter | Màn hình đăng nhập greetd đồng bộ giao diện | `noctalia-greeter` + `greetd` |

Bốn gói đầu **chỉ có trên Terra** (repo cộng đồng của Fyra Labs). Bản stable
`noctalia` nằm trong repo chính thức Fedora 44+, còn `noctalia-greeter` stable
có trên Terra.

**Yêu cầu tối thiểu Fedora 44.** Terra không có `umbriel-nightly` hay
`luciole-nightly` cho Fedora 43, và wlroots trên F43 (0.19) cũ hơn mức Umbriel
cần (0.20).

## Cách 1 — chạy script

```bash
./noctalia-fedora.sh            # hỏi từng bước
./noctalia-fedora.sh --dry-run  # xem trước, không đổi gì
```

Các tùy chọn:

| Tùy chọn | Ý nghĩa |
|---|---|
| `-n`, `--dry-run` | Chỉ in lệnh sẽ chạy |
| `-y`, `--yes` | Không hỏi lại |
| `--no-greeter` | Bỏ greeter, giữ display manager hiện tại |
| `--switch-dm` | Disable DM cũ và bật greetd (giữ 1 TTY để cứu hộ) |
| `-f`, `--force-config` | Ghi đè `~/.config/umbriel/config.toml` đang có |

Script sẽ: bật Terra → gỡ gói xung đột (`noctalia`, `luciole`, bản `-git`) →
cài 55 gói nền + 3 gói greeter → tạo config Umbriel với
`autostart = ["noctalia"]` → cấu hình greeter, state dir và `greetd` → kiểm tra
`/etc/pam.d` → (tùy chọn) đổi DM.

Script **không** tự đổi display manager trừ khi bạn truyền `--switch-dm`, và
từ chối đổi nếu thiếu `noctalia-greeter-session` hoặc entry session Umbriel.

## Cách 2 — cài tay từng bước

### 1. Bật Terra

```bash
sudo dnf install --nogpgcheck \
  --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' \
  terra-release
sudo dnf makecache
```

### 2. Cài hệ sinh thái

```bash
sudo dnf install \
  noctalia-nightly umbriel-nightly \
  xdg-desktop-portal-umbriel-nightly luciole-nightly

# Compositor cần Xwayland cho app X11
sudo dnf install xorg-x11-server-Xwayland
```

Nếu máy đã có `noctalia`, `luciole` hoặc các bản `-git`, gỡ trước vì chúng
`Conflicts` với gói nightly:

```bash
sudo dnf remove noctalia noctalia-git luciole luciole-git
```

### 3. Cài phần nền cho session

```bash
sudo dnf install \
  pipewire pipewire-pulseaudio pipewire-utils wireplumber \
  polkit dbus-daemon dbus-tools gnome-keyring libsecret \
  upower power-profiles-daemon ddcutil brightnessctl playerctl \
  mesa-dri-drivers mesa-libEGL mesa-libGLES mesa-libgbm \
  mesa-vulkan-drivers libglvnd-egl libglvnd-gles \
  fontconfig dejavu-sans-fonts google-noto-sans-fonts \
  google-noto-color-emoji-fonts rsms-inter-fonts hicolor-icon-theme \
  sound-theme-freedesktop libheif \
  xdg-desktop-portal xdg-desktop-portal-gtk \
  NetworkManager NetworkManager-wifi kitty
```

Phần này gồm: audio + OSD (PipeWire/WirePlumber), keyring (lưu secret), pin
và độ sáng, font (thiếu font thì UI Noctalia hiện ô vuông), portal nền, mạng
và terminal mặc định mà keybind Umbriel gọi (`Mod+Return` → kitty).

Tùy chọn cho Luciole (thumbnail video/PDF, giải nén, mở terminal):

```bash
sudo dnf install shared-mime-info gsettings-desktop-schemas dconf \
  adwaita-icon-theme gvfs gvfs-smb glib-networking glycin-loaders \
  ffmpeg-free ffmpegthumbnailer poppler-utils 7zip xdg-terminal-exec
```

### 4. Cấu hình Umbriel + Noctalia

```bash
mkdir -p ~/.config/umbriel
cp /usr/share/umbriel/config.toml ~/.config/umbriel/config.toml
```

Mở file và bật autostart (config mẫu đang comment sẵn dòng này):

```toml
[general]
autostart = ["noctalia"]
```

Config mẫu đã có sẵn `[appearance.blur]` với `radius = 3`, layer rule blur
cho bar/panel/notification và window rule float cho cửa sổ Settings — đúng
khuyến nghị tích hợp của Noctalia, nên không cần sửa thêm.

Kiểm tra config (Umbriel từ chối key lạ):

```bash
umbriel config validate
```

### 5. Greeter (tùy chọn)

```bash
sudo dnf install greetd noctalia-greeter wlroots
```

Tạo state dir, cấu hình greetd và cấp quyền DRM cho user `greetd`:

```bash
sudo install -d -m 0750 -o greetd -g greetd /var/lib/noctalia-greeter
printf '[session]\ndefault = "Umbriel"\n' | sudo tee /var/lib/noctalia-greeter/greeter.toml
sudo chown greetd:greetd /var/lib/noctalia-greeter/greeter.toml

sudo usermod -aG video,input greetd

sudo tee /etc/greetd/config.toml >/dev/null <<'EOF'
[terminal]
vt = 1

[default_session]
command = "/usr/bin/noctalia-greeter-session"
user = "greetd"
EOF
```

Đổi display manager (giữ 1 TTY đang mở để cứu hộ):

```bash
systemctl status display-manager.service     # xem DM hiện tại
sudo systemctl disable --now gdm.service     # thay bằng DM của bạn
sudo systemctl enable --now greetd
```

Nếu hỏng, quay lại từ TTY:

```bash
sudo systemctl disable --now greetd
sudo systemctl enable --now gdm.service
```

## Chạy lần đầu

Từ display manager chọn session **Umbriel**, hoặc từ TTY:

```bash
start-umbriel
```

`start-umbriel` chạy compositor qua systemd user service, đọc login profile
của shell (bash/zsh/fish) để lấy `PATH`, rồi khởi động Noctalia theo
`autostart`.

## Kiểm tra sau khi vào session

```bash
noctalia msg panel-toggle launcher   # bar/launcher phản hồi?
umbriel layers                       # thấy noctalia-bar-*, noctalia-panel
umbriel config validate
```

Log:

```bash
tail -f ~/.cache/noctalia/noctalia.log
tail -f ~/.cache/umbriel/umbriel.log
```

## Những lỗi hay gặp

| Triệu chứng | Nguyên nhân và cách xử lý |
|---|---|
| Không thấy session Umbriel | Thiếu `/usr/share/wayland-sessions/umbriel.desktop`; cài lại `umbriel-nightly` |
| `Permission denied` khi mở DRM | Phiên đăng nhập không có logind seat; kiểm tra PAM của greetd có đi tới `pam_systemd` |
| Bar không hiện, chỉ có hình nền | Noctalia chưa autostart; kiểm tra `autostart` trong config Umbriel và log Noctalia |
| Ô vuông thay chữ | Thiếu font; cài `dejavu-sans-fonts`, `google-noto-sans-fonts`, `google-noto-color-emoji-fonts` |
| Không có âm thanh, OSD không hiện | `pipewire`, `wireplumber` chưa chạy: `systemctl --user status wireplumber` |
| Screen share không có nguồn | Thiếu portal backend; kiểm tra `systemctl --user status xdg-desktop-portal-umbriel` |
| Greeter hiện màn hình đen | Thiếu quyền DRM cho user `greetd`; kiểm tra group `video`, `input` và log `journalctl -u greetd` |
| Mất luôn màn hình đăng nhập | Từ TTY: `sudo systemctl disable --now greetd && sudo systemctl enable --now <dm>.service` |

## Ghi chú

- Kênh nightly không có API ổn định: keybind và key cấu hình của Umbriel có
  thể đổi giữa các bản, và Noctalia v5 cũng đang tiến hoá nhanh.
- Terra là repo bên thứ ba, không thuộc Fedora. Script dùng `--nogpgcheck`
  đúng như hướng dẫn chính thức của Terra khi thêm repo lần đầu.
- Greeter chạy dưới user `greetd` (không phải `greeter` như tài liệu upstream);
  Fedora đặt tên user là `greetd` trong `greetd.sysusers`.
- Không thêm user thường vào group `input`/`video` để chạy Umbriel: compositor
  lấy quyền thiết bị qua logind, còn group `input` cho phép đọc mọi phím gõ.

## Nguồn

- [Noctalia installation docs](https://docs.noctalia.dev/noctalia/getting-started/installation/)
- [Noctalia repository](https://github.com/noctalia-dev/noctalia)
- [Umbriel repository](https://github.com/noctalia-dev/umbriel)
- [Umbriel packaging notes](https://github.com/noctalia-dev/umbriel/blob/main/PACKAGING.md)
- [Luciole installation](https://github.com/noctalia-dev/luciole/blob/main/docs/user/installation.md)
- [Noctalia Greeter installation](https://github.com/noctalia-dev/noctalia-greeter/blob/main/docs/user/installation.md)
- [Terra package sources](https://github.com/terrapkg/packages)
- [Noctalia + Umbriel integration](https://docs.noctalia.dev/noctalia/compositor-settings/umbriel)
