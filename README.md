# Shiva Server Toolkit

**v1.1.0-dev Automation Preview**

An extensible command-line toolkit for Linux server health, networking, VPN,
Docker, updates, diagnostics, logs, and backups.

Future development is tracked in [ROADMAP.md](ROADMAP.md).

## Release notes v1.0.0

- **Profiles:** automatic hostname detection, built-in profiles for
  `shiva-server`, `shiva-vpn`, and `ananda`, plus local profile overrides.
- **Health summary:** enabled checks only, passed/warning/error counters, and
  an overall server-health percentage.
- **SMART:** configurable physical disk, LVM-aware automatic detection,
  passwordless sudo support, exact PASSED/FAILED parsing, and Doctor details
  for unknown responses.
- **Network:** interface state, routes, listening ports, gateway, internet,
  and DNS checks.
- **VPN:** profile-controlled OpenVPN client, OCSERV, and Amnezia checks.
- **Doctor:** verifies required tools and exposes retained SMART diagnostic
  output.
- **Installer:** installs commands, shared libraries, configuration, and
  built-in profiles while preserving local configuration.
- **Tests:** syntax, profile selection, SMART states, VPN filtering, Health
  output, and staged installation coverage.

## Commands

```text
shiva             Interactive menu
shiva-health      Full health summary
shiva-network     Interfaces, routes, and listening ports
shiva-vpn         OpenVPN, OCSERV, and Amnezia status
shiva-docker      Docker service and containers
shiva-update      Available system updates
shiva-doctor      Toolkit and host diagnostics
shiva-repair      Guided dry-run or applied repairs
shiva-watchdog    Automation checks for service supervision
shiva-history     Local operational history
shiva-logs        Recent warning/error logs
shiva-backup      Backup freshness check
```

The same modules can also be called as subcommands, for example
`shiva health` and `shiva network`.

## Automation preview

The `v1.1` development branch introduces the first automation commands:

```bash
shiva repair status
shiva repair network
shiva repair openvpn
shiva repair dns
shiva watchdog --once
shiva watchdog --status
shiva history
shiva history --module watchdog
```

`shiva repair` runs in dry-run mode by default and prints planned actions.
Use `--apply` only when the target profile is configured and the command is
running with the required permissions.

The watchdog is installed with a systemd unit:

```bash
sudo systemctl enable --now shiva-watchdog
```

## Install

```bash
cd shiva-toolkit
sudo ./install.sh
```

## Debian/Ubuntu package

Build a local DEB package:

```bash
cd shiva-toolkit
make deb
```

The package will be written to:

```text
dist/shiva-toolkit_1.1.0~dev-1_all.deb
```

Install it on Debian or Ubuntu:

```bash
sudo apt install ./dist/shiva-toolkit_1.1.0~dev-1_all.deb
```

The DEB package installs:

```text
/usr/bin/shiva*
/usr/lib/shiva
/etc/shiva/shiva.conf
/etc/shiva/profiles
```

`/etc/shiva/shiva.conf` is a Debian conffile, so local edits are preserved
during package upgrades. Remove the package with:

```bash
sudo apt remove shiva-toolkit
```

## Server profiles

Shiva detects the static hostname with `hostnamectl --static` and loads:

1. the matching built-in profile;
2. `/etc/shiva/profiles/<hostname>.conf`, when present;
3. optional final overrides from `/etc/shiva/shiva.conf`.

The included profiles are:

| Hostname | Purpose | Enabled service checks |
| --- | --- | --- |
| `shiva-server` | Home server | OpenVPN client; Docker disabled by default |
| `shiva-vpn` | VPN server | OpenVPN, OCSERV, Amnezia |
| `ananda` | AI server | Docker |

All three profiles explicitly control temperature, SMART, interfaces, Docker,
OpenVPN, OCSERV, and Amnezia:

```bash
CHECK_TEMPERATURE=true
CHECK_SMART=true
CHECK_INTERFACES=true
CHECK_DOCKER=true
CHECK_OPENVPN=true
CHECK_OCSERV=false
CHECK_AMNEZIA=false
```

Disabled checks are completely omitted: they are not executed and do not
produce placeholder, warning, or `DISABLED` rows. The interactive menu and
`shiva --help` also hide Docker and VPN modules when the current profile has
disabled them.

`REQUIRED_INTERFACES` can contain a space-separated list of interfaces that
must be up. When left empty, the interface check requires at least one active
non-loopback interface. `REQUIRED_INTERFACE` is accepted as a singular alias.
When a required interface is also the configured OpenVPN or Amnezia interface,
Shiva uses the same interface-existence check for both statuses so Health
cannot report the VPN as running while reporting its interface as missing.

Create a host-specific override without modifying the toolkit:

```bash
sudo install -m 0644 /dev/null /etc/shiva/profiles/"$(hostnamectl --static)".conf
sudoedit /etc/shiva/profiles/"$(hostnamectl --static)".conf
```

Existing profile and global configuration files are preserved during
reinstallations.

SSD health follows the root filesystem through LVM/device-mapper to its
physical disk and runs `smartctl` through non-interactive `sudo`. To permit
this check without granting broader passwordless sudo access, add a narrowly
scoped sudoers rule with `visudo`:

```text
your-user ALL=(root) NOPASSWD: /usr/sbin/smartctl -H /dev/sda
```

Set `SMART_DISK="/dev/sda"` in a profile when the physical device is known.
Shiva treats the exact SMART result line as authoritative: `PASSED` is accepted
only when `smartctl` exits successfully, while `FAILED` is reported from the
result text regardless of smartctl's diagnostic bitmask. Unrecognized output
is summarized as `SMART UNKNOWN` and its original error text is shown by
`shiva-doctor`.

The Health footer reports passed, warning, and error counts plus a percentage.
Passed checks contribute 100%, warnings 50%, and errors 0%; disabled checks are
not included.

For a staged, non-root installation:

```bash
DESTDIR=/tmp/shiva-stage ./install.sh
```

## Development

Run directly from the repository:

```bash
./bin/shiva
make test
```

New modules should be separate `bin/shiva-<name>` executables and use the
shared functions in `lib/shiva/common.sh`. Add the module to the main menu only
when interactive access is useful; direct commands remain independently
scriptable.

`shiva-update` only lists updates by default. Installing them is an explicit
root action:

```bash
sudo shiva-update --apply
```
