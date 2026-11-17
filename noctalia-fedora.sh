#!/usr/bin/env bash
# Noctalia full ecosystem installer for Fedora (Umbriel compositor, nightly channel).
set -Eeuo pipefail

readonly PROG=${0##*/}
readonly GREETER_STATE_DIR=/var/lib/noctalia-greeter
readonly GREETD_CONFIG=/etc/greetd/config.toml
readonly GREETD_USER=greetd

DRY_RUN=0
ASSUME_YES=0
WITH_GREETER=1
SWITCH_DM=0
DM_SWITCHED=0
FORCE_CONFIG=0
TARGET_USER=""
SUDO=()

usage() {
  cat <<EOF
Usage: $PROG [options]

Installs the Noctalia ecosystem on Fedora 44/45, including minimal installs:
Noctalia shell, Umbriel compositor, xdg-desktop-portal-umbriel, Luciole file
manager, and optionally the Noctalia greeter (greetd).

Packages come from the Fedora repositories plus the Terra repository, which
provides the nightly builds of the Noctalia family.

Options:
  -n, --dry-run        Print what would happen without changing anything
  -y, --yes            Never prompt
      --no-greeter     Skip noctalia-greeter, greetd and greeter setup
      --switch-dm      After installing, disable the current display manager
                       and enable greetd (keep a TTY open to recover)
  -f, --force-config   Overwrite an existing ~/.config/umbriel/config.toml
  -h, --help           Show this help

Run as your normal user, not as root: the script calls sudo itself.
EOF
}

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

run() {
  if ((DRY_RUN)); then
    printf '    [dry-run] %s\n' "$*"
    return 0
  fi
  "$@"
}

confirm() {
  ((ASSUME_YES)) && return 0
  local reply
  read -r -p "$1 [y/N] " reply
  [[ $reply == [yY] ]]
}

parse_args() {
  while (($#)); do
    case $1 in
      -n|--dry-run)       DRY_RUN=1 ;;
      -y|--yes)           ASSUME_YES=1 ;;
      --no-greeter)       WITH_GREETER=0 ;;
      --switch-dm)        SWITCH_DM=1 ;;
      -f|--force-config)  FORCE_CONFIG=1 ;;
      -h|--help)          usage; exit 0 ;;
      *) usage; die "unknown option: $1" ;;
    esac
    shift
  done

  if ((WITH_GREETER == 0 && SWITCH_DM == 1)); then
    warn "--switch-dm ignored because --no-greeter was given"
    SWITCH_DM=0
  fi
}

preflight() {
  [[ -r /etc/os-release ]] || die "cannot read /etc/os-release"
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ ${ID:-} == fedora ]] || die "this script targets Fedora only (found: ${ID:-unknown})"
  if ((VERSION_ID < 44)); then
    die "Fedora 44 or newer required (found ${VERSION_ID:-unknown}): Terra has no umbriel-nightly or luciole-nightly for older releases, and wlroots 0.20 is missing"
  fi

  case $(uname -m) in
    x86_64|aarch64) ;;
    *) die "unsupported architecture: $(uname -m) (Terra ships x86_64 and aarch64 only)" ;;
  esac

  ((EUID == 0)) && die "do not run this as root; run it as your user and let it call sudo"
  command -v sudo >/dev/null || die "sudo is required (sudo dnf install sudo)"
  command -v dnf >/dev/null || die "dnf is required"
  command -v awk >/dev/null || die "awk is required (sudo dnf install gawk)"
  SUDO=(sudo)

  TARGET_USER=${SUDO_USER:-$(id -un)}
  [[ $TARGET_USER != root ]] || die "run this as your normal user"
  id "$TARGET_USER" >/dev/null 2>&1 || die "user ${TARGET_USER} does not exist"

  info "Fedora ${VERSION_ID} on $(uname -m), target user: ${TARGET_USER}"
}

enable_terra() {
  if [[ -f /etc/yum.repos.d/terra.repo ]]; then
    info "Terra repository already configured"
    return 0
  fi
  log "Enabling the Terra repository"
  run "${SUDO[@]}" dnf install -y --nogpgcheck \
    --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' \
    terra-release
}

remove_conflicting() {
  local -a installed=()
  local pkg
  for pkg in noctalia noctalia-git luciole luciole-git; do
    if rpm -q "$pkg" >/dev/null 2>&1; then
      installed+=("$pkg")
    fi
  done
  ((${#installed[@]})) || return 0

  warn "these packages conflict with the nightly builds: ${installed[*]}"
  if ! confirm "Remove them now?"; then
    die "aborting: remove the conflicting packages first"
  fi
  run "${SUDO[@]}" dnf remove -y "${installed[@]}"
}

install_pkgs() {
  local -a pkgs=("$@")
  ((${#pkgs[@]})) || return 0

  log "Installing ${#pkgs[@]} packages"
  if run "${SUDO[@]}" dnf install -y "${pkgs[@]}"; then
    return 0
  fi

  warn "the combined transaction failed; retrying package by package"
  local -a failed=()
  local pkg
  for pkg in "${pkgs[@]}"; do
    run "${SUDO[@]}" dnf install -y "$pkg" >/dev/null 2>&1 || failed+=("$pkg")
  done
  ((${#failed[@]} == 0)) || warn "could not install: ${failed[*]}"
}

build_lists() {
  COMMON_PKGS=(
    # Noctalia family (Terra nightly)
    noctalia-nightly
    umbriel-nightly
    xdg-desktop-portal-umbriel-nightly
    luciole-nightly
    # Session and graphics stack
    xorg-x11-server-Xwayland
    mesa-dri-drivers mesa-libEGL mesa-libGLES mesa-libgbm
    mesa-vulkan-drivers libglvnd-egl libglvnd-gles
    # Audio, power, input
    pipewire pipewire-pulseaudio pipewire-utils wireplumber
    upower power-profiles-daemon ddcutil
    brightnessctl playerctl
    # Authentication, secrets, portals
    polkit dbus-daemon dbus-tools gnome-keyring libsecret
    xdg-desktop-portal xdg-desktop-portal-gtk
    # Desk integration used by Luciole and the shell
    shared-mime-info gsettings-desktop-schemas dconf adwaita-icon-theme
    gvfs gvfs-smb glib-networking glycin-loaders
    ffmpeg-free ffmpegthumbnailer poppler-utils 7zip
    xdg-terminal-exec xdg-user-dirs xdg-utils accountsservice
    # Fonts and icons
    fontconfig dejavu-sans-fonts google-noto-sans-fonts
    google-noto-color-emoji-fonts rsms-inter-fonts hicolor-icon-theme
    # Sound theme and image codecs
    sound-theme-freedesktop libheif
    # Terminal and networking
    kitty NetworkManager NetworkManager-wifi
  )
  GREETER_PKGS=(greetd noctalia-greeter wlroots)
}

install_everything() {
  install_pkgs "${COMMON_PKGS[@]}"
  if ((WITH_GREETER)); then
    install_pkgs "${GREETER_PKGS[@]}"
  fi
}

verify_install() {
  ((DRY_RUN)) && return 0

  log "Verifying installed commands"
  local -a bins=(noctalia umbriel start-umbriel luciole Xwayland)
  if ((WITH_GREETER)); then
    bins+=(noctalia-greeter noctalia-greeter-session)
  fi

  local -a missing=()
  local b
  for b in "${bins[@]}"; do
    command -v "$b" >/dev/null 2>&1 || missing+=("$b")
  done

  if ((${#missing[@]})); then
    warn "not found on PATH: ${missing[*]}"
    warn "the session will not start until these are installed"
  else
    info "all expected commands are present"
  fi
}

write_umbriel_config() {
  local cfg_dir="${HOME}/.config/umbriel"
  local cfg="${cfg_dir}/config.toml"
  local packaged=/usr/share/umbriel/config.toml

  if [[ -f $cfg ]] && ((FORCE_CONFIG == 0)); then
    info "keeping existing ${cfg} (use --force-config to regenerate it)"
    return 0
  fi

  log "Writing ${cfg}"
  if ((DRY_RUN)); then
    info "[dry-run] copy ${packaged} and add Noctalia defaults"
    return 0
  fi

  [[ -r $packaged ]] || die "packaged Umbriel config missing: ${packaged}"
  mkdir -p "$cfg_dir"
  cp "$packaged" "$cfg"

  # The packaged config already carries the appearance, blur and layer rules
  # Noctalia recommends, so only the shell autostart entry needs enabling.
  local entry='autostart = ["noctalia"]'
  local tmp
  tmp=$(mktemp)
  if grep -qE '^autostart[[:space:]]*=' "$cfg"; then
    awk -v e="$entry" '/^autostart[[:space:]]*=/ && !done { print e; done=1; next } { print }' "$cfg" >"$tmp"
  elif grep -qE '^#[[:space:]]*autostart[[:space:]]*=' "$cfg"; then
    awk -v e="$entry" '/^#[[:space:]]*autostart[[:space:]]*=/ && !done { print e; done=1; next } { print }' "$cfg" >"$tmp"
  elif grep -qE '^\[general\][[:space:]]*$' "$cfg"; then
    awk -v e="$entry" '/^\[general\][[:space:]]*$/ && !done { print; print e; done=1; next } { print }' "$cfg" >"$tmp"
  else
    { cat "$cfg"; printf '\n[general]\n%s\n' "$entry"; } >"$tmp"
  fi
  mv "$tmp" "$cfg"

  if command -v umbriel >/dev/null 2>&1; then
    log "Validating the Umbriel configuration"
    umbriel config validate || warn "Umbriel reported diagnostics; review ${cfg}"
  fi
}

setup_greeter() {
  ((WITH_GREETER)) || return 0

  if ! id -u "$GREETD_USER" >/dev/null 2>&1 && ((DRY_RUN == 0)); then
    die "user ${GREETD_USER} is missing; is the greetd package installed?"
  fi

  log "Granting the greeter access to DRM and input devices"
  run "${SUDO[@]}" usermod -aG video,input "$GREETD_USER"

  log "Preparing the greeter state directory"
  run "${SUDO[@]}" install -d -m 0750 -o "$GREETD_USER" -g "$GREETD_USER" "$GREETER_STATE_DIR"

  local greeter_toml="${GREETER_STATE_DIR}/greeter.toml"
  if ((DRY_RUN)); then
    info "[dry-run] ensure ${greeter_toml} selects the Umbriel session"
  elif [[ -f $greeter_toml ]]; then
    info "keeping existing ${greeter_toml}"
  else
    log "Writing ${greeter_toml}"
    printf '[session]\ndefault = "Umbriel"\n' |
      "${SUDO[@]}" tee "$greeter_toml" >/dev/null
    "${SUDO[@]}" chown "${GREETD_USER}:${GREETD_USER}" "$greeter_toml"
    "${SUDO[@]}" chmod 0640 "$greeter_toml"
  fi

  # greetd must reach pam_systemd so the graphical login registers a logind
  # session and a systemd user manager. On Fedora the stack lives in
  # /usr/lib/pam.d/greetd and pulls it in through "session include system-auth",
  # so only a shadowing /etc/pam.d/greetd that drops that include is a problem.
  local pam_etc=/etc/pam.d/greetd
  local pam_vendor=/usr/lib/pam.d/greetd
  local pam_active=$pam_etc
  [[ -f $pam_active ]] || pam_active=$pam_vendor

  if ((DRY_RUN)); then
    info "[dry-run] check that ${pam_active} reaches pam_systemd"
  elif [[ ! -f $pam_active ]]; then
    warn "no greetd PAM stack found; verify the login starts a systemd user session"
  elif grep -qE 'pam_systemd|include[[:space:]]+(system-auth|postlogin)' "$pam_active"; then
    info "${pam_active} already reaches pam_systemd"
  else
    warn "${pam_active} does not reach pam_systemd; the session may lose its"
    warn "systemd user manager, portals and audio. Review it before rebooting."
  fi

  log "Pointing greetd at noctalia-greeter-session"
  if [[ -f $GREETD_CONFIG ]] && grep -q 'noctalia-greeter-session' "$GREETD_CONFIG"; then
    info "greetd is already configured"
  elif ((DRY_RUN)); then
    info "[dry-run] write ${GREETD_CONFIG} (command = /usr/bin/noctalia-greeter-session, user = ${GREETD_USER})"
  else
    if [[ -f $GREETD_CONFIG ]]; then
      "${SUDO[@]}" cp -a "$GREETD_CONFIG" "${GREETD_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"
    fi
    "${SUDO[@]}" mkdir -p "$(dirname "$GREETD_CONFIG")"
    "${SUDO[@]}" tee "$GREETD_CONFIG" >/dev/null <<EOF
[terminal]
vt = 1

[default_session]
command = "/usr/bin/noctalia-greeter-session"
user = "${GREETD_USER}"
EOF
  fi

  if ((SWITCH_DM)); then
    if switch_display_manager; then
      DM_SWITCHED=1
    else
      SWITCH_DM=0
    fi
  else
    info "greetd is installed but not enabled"
    info "activate later with: sudo systemctl disable --now <current-dm>.service && sudo systemctl enable --now greetd"
  fi
}

switch_display_manager() {
  # Refuse to remove the working login screen unless the replacement is
  # actually present, otherwise the machine boots to a black VT.
  if ((DRY_RUN)); then
    :
  elif ! command -v noctalia-greeter-session >/dev/null 2>&1; then
    warn "noctalia-greeter-session is not installed; leaving the display manager alone"
    return 1
  elif [[ ! -f /usr/share/wayland-sessions/umbriel.desktop ]]; then
    warn "the Umbriel session entry is missing; leaving the display manager alone"
    return 1
  fi

  log "Switching the display manager to greetd"
  local current=""
  current=$(systemctl show -p Id --value display-manager.service 2>/dev/null || true)

  if [[ -n $current && $current != greetd.service ]]; then
    if confirm "Disable ${current}? Keep a TTY open in case greetd fails to start."; then
      run "${SUDO[@]}" systemctl disable --now "$current"
    else
      warn "did not disable ${current}; greetd will not take over at boot"
      return 1
    fi
  fi
  run "${SUDO[@]}" systemctl enable --now greetd
}

summary() {
  local greeter_line=""
  local session_hint="in your display manager"
  local greeter_cmd="  noctalia-greeter sessions       list sessions offered at login"
  local rollback_dm=""

  if ((WITH_GREETER)); then
    greeter_line=", noctalia-greeter + greetd"
    if ((DM_SWITCHED)); then
      session_hint="on the Noctalia greeter (reboot to see it)"
      rollback_dm=$'\n  sudo systemctl disable --now greetd\n  sudo systemctl enable --now <previous-dm>.service'
    fi
  else
    greeter_cmd=""
  fi

  log "Finished"
  cat <<EOF
Installed: noctalia-nightly (shell), umbriel-nightly (compositor),
           xdg-desktop-portal-umbriel-nightly, luciole-nightly${greeter_line}

Next steps
  1. Log out and start the "Umbriel" session ${session_hint}
  2. Or, from a TTY: start-umbriel
  3. Shell settings:     ~/.config/noctalia/
     Compositor config:  ~/.config/umbriel/config.toml
  4. Logs: ~/.cache/noctalia/noctalia.log and ~/.cache/umbriel/umbriel.log

Handy commands
  umbriel config validate         check the compositor configuration
  umbriel layers                  list active layer-shell surfaces
  noctalia msg panel-toggle launcher
${greeter_cmd}

Rollback
  sudo dnf remove umbriel-nightly noctalia-nightly luciole-nightly xdg-desktop-portal-umbriel-nightly${rollback_dm}
EOF
}

main() {
  parse_args "$@"
  preflight
  build_lists
  enable_terra
  remove_conflicting
  install_everything
  verify_install
  write_umbriel_config
  setup_greeter
  summary
}

main "$@"
