# AutoKey for Wayland (and X11, too)

This fork of the [AutoKey](https://github.com/autokey/autokey) project enables 
the unreleased code that the "develop" branch of the official 
[AutoKey](https://github.com/autokey/autokey) project contains to support the 
Gnome/Wayland desktop.  This fork contains fixes, plus additional changes and 
enhancements, to make AutoKey function properly in both the X11 and 
Gnome/Wayland environments.  

**Important:** This version of AutoKey currently only works with Gnome desktops 
under Wayland.  Under X11, it continues to work with any desktop environment. 
I hope to extend Wayland support to KDE shortly, and to other desktop environments 
in the future.

## Project Documentation

The [project documentation](https://autokey-wayland.readthedocs.io/en/latest/) 
web site includes information on:

* [What Works & What Does Not](https://autokey-wayland.readthedocs.io/en/latest/whatworks.html)
* [Installation Instructions](https://autokey-wayland.readthedocs.io/en/latest/installation.html)

Ubuntu/Debian and Fedora installation packages are available.  The AutoKey for 
Wayland code may also be cloned from GitHub, configured, and run manually on any
system.

## Support

Read the 
[Troubleshooting](https://autokey-wayland.readthedocs.io/en/latest/troubleshoot.html) 
section of the documentation website.

The [official AutoKey wiki](http://github.com/autokey/autokey/wiki) contains a 
lot of useful information about how to use AutoKey, including many example 
scripts and the like.  Make use of it.

You may post questions or bug reports to this project's 
[Issues](https://github.com/dlk3/autokey-wayland/issues) tracker, and I will do 
my best to address them.  Problem reports should always include a console log that
captures the debug output from AutoKey when the problem occurs.  See the 
[issue reporting](https://autokey-wayland.readthedocs.io/en/latest/troubleshoot/issues.html)
section of the documentation for guidance.

## Project Branches

* [main](https://github.com/dlk3/autokey-wayland/tree/main) - the current release.
* [develop](https://github.com/dlk3/autokey-wayland/tree/develop) - developing the next release.

See, also, [Releases](https://github.com/dlk3/autokey-wayland/releases).

## Installation

This repository includes a user-local installer for systems without a distro
package, or when you want a self-contained install under `~/.local`:

```bash
git clone https://github.com/lx19990999/autokey-wayland
cd autokey-wayland
./install.sh
```

On **KDE / Wayland**, install the Qt frontend only:

```bash
./install.sh --ui qt
```

After installation, start AutoKey from the application menu or run:

```bash
autokey        # prefers Qt on KDE
autokey-qt
autokey-gtk
```

Other options:

```bash
./install.sh --help
./uninstall.sh
```

The installer creates `~/.local/bin` launchers, desktop entries, icons, a Python
venv under `~/.local/share/autokey/venv`, and (with sudo) udev/uinput setup for
keyboard injection on Wayland. See [INSTALL](INSTALL) for a short summary.

### Verified environment

The installer and `./install.sh --ui qt` flow were developed and tested on:

| Item | Value |
|------|-------|
| OS | Rocky Linux 10.2 (RHEL/EL10, `dnf`) |
| Desktop | KDE Plasma 6.6.4 (`plasma-workspace` 6.6.4) |
| Session | Wayland (KWin 6.6.4, `libwayland-client` 1.24.0) |

On this stack, AutoKey uses the **uinput** interface and **KWin** (via DBus) for
window information. GNOME Shell extension steps are skipped automatically on KDE.

Distro packages (Fedora COPR / Debian) remain documented at
[autokey-wayland.readthedocs.io — Installation](https://autokey-wayland.readthedocs.io/en/latest/installation.html).

