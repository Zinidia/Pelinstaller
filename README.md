# Pelinstaller

[![License: GPL v3](https://img.shields.io/github/license/Zinidia/Pelinstaller)](LICENSE.md)

<table><tr></tr><tr><td>

### ⚠️ Pelican is in beta so this script may not work if breaking changes are made, this script will also be recoded to use Docker Compose in the coming days :construction:

Welcome to the Pelinstaller repository! This installer is a hard fork of [ForestRacks's Pterodactyl Installer](https://github.com/ForestRacks/PteroInstaller) and is specifically designed for people to easily install and set up the Pelican on Debian-based or RHEL-based machines. If you encounter any issues during the installation process, our troubleshooting section has some helpful tips.

Learn more about [Pelican's Project](https://pelican.dev/) here. This script is a third-party utility and not associated with the official Pelican Project.

<br></td></tr></table>

## Using the installation scripts

To use the installation scripts, simply run this command as root. The script will ask you whether you would like to install just the panel, just Wings or both.

```bash
bash <(curl -Ss https://raw.githubusercontent.com/pelican-installer/pelican-installer/Production/install.sh || wget -O - https://raw.githubusercontent.com/pelican-installer/pelican-installer/Production/install.sh) auto
```

_Note: On some systems, it's required to be already logged in as root before executing the one-line command (where `sudo` is in front of the command does not work)._

Here is a [YouTube Video](https://www.youtube.com/watch?v=E8UJhyUFoHM) that illustrates the installation process.

## Features

- Automatic installation of the Pelican Panel (dependencies, database, cronjob, nginx).
- Automatic installation of the Pelican Wings (Docker, systemd).
- Panel: (optional) automatic configuration of Let's Encrypt.
- Panel: (optional) automatic configuration of firewall.
- Uninstallation support for both panel and wings.

## Help and support

For help and support regarding the script itself and **not the official Pelican project**, create a [Github Issue](https://github.com/pelican-installer/pelican-installer/issues).

## Supported installations

List of supported installation setups for panel and Wings (installations supported by this installation script).

### Supported panel and wings operating systems

| Operating System | Version | Supported          | PHP Version |
| ---------------- | ------- | ------------------ | ----------- |
| Ubuntu           | 16.04   | :red_circle:       |             |
|                  | 18.04   | :red_circle: \*    |             |
|                  | 20.04   | :white_check_mark: | 8.3         |
|                  | 22.04   | :white_check_mark: | 8.3         |
|                  | 24.04   | :white_check_mark: | 8.3         |
| Debian           | 8       | :red_circle: \*    |             |
|                  | 9       | :red_circle: \*    |             |
|                  | 10      | :white_check_mark: | 8.3         |
|                  | 11      | :white_check_mark: | 8.3         |
|                  | 12      | :white_check_mark: | 8.3         |
| CentOS           | 6       | :red_circle:       |             |
|                  | 7       | :red_circle: \*    |             |
|                  | 8       | :red_circle: \*    |             |
| Rocky Linux      | 8       | :white_check_mark: | 8.3         |
|                  | 9       | :white_check_mark: | 8.3         |
| AlmaLinux        | 8       | :white_check_mark: | 8.3         |
|                  | 9       | :white_check_mark: | 8.3         |

_\* Indicates an operating system and release that previously was supported by this script._

## Firewall setup

The installation scripts can install and configure a firewall for you. The script will ask whether you want this or not. It is highly recommended to opt-in for the automatic firewall setup.

## Production & Ops

### Testing the script locally

To test the script, we use [Vagrant](https://www.vagrantup.com). With Vagrant, you can quickly get a fresh machine up and running to test the script.

If you want to test the script on all supported installations in one go, just run the following.

```bash
vagrant up
```

If you only want to test a specific distribution, you can run the following.

```bash
vagrant up <name>
```

Replace name with one of the following (supported installations).

- `ubuntu_noble`
- `ubuntu_jammy`
- `ubuntu_focal`
- `debian_bullseye`
- `debian_buster`
- `debian_bookworm`
- `almalinux_8`
- `almalinux_9`
- `rockylinux_8`
- `rockylinux_9`

Then you can use `vagrant ssh <name of machine>` to SSH into the box. The project directory will be mounted in `/vagrant` so you can quickly modify the script locally and then test the changes by running the script from `/vagrant/installers/panel.sh` and `/vagrant/installers/wings.sh` respectively.

### Creating a release

In `install.sh` github source and script release variables should change every release. Firstly, update the `CHANGELOG.md` so that the release date and release tag are both displayed. No changes should be made to the changelog points themselves. Secondly, update `GITHUB_SOURCE` and `SCRIPT_RELEASE` in `install.sh`. Finally, you can now push a commit with the message `Release vX.Y.Z`. Create a release on GitHub. See [this commit](https://github.com/pelican-installer/pelican-installer/commit/90aaae10785f1032fdf90b216a4a8d8ca64e6d44) for reference.


## Sponsors ✨

I would like to extend my sincere thanks to the following sponsors for helping fund Pelican Installer's development.
[Interested in becoming a sponsor?](mailto:me@matthew.expert)

| Company                                                   | About                                                                                                                                                                                                                                           |
|-----------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| [**ForestRacks**](https://forestracks.com/vps)  | Looking for a place to host your Pelican Panel? Try out a ForestRacks VPS, ForestRacks is a US-based 5-Star hosting provider offering services globally since 2019. |

## Contributors ✨

We would like to thank the following contributors for their work in maintaining and creating this installer:
1) [Matthew Jacob](https://github.com/Zinidia)
2) [Vilhelm Prytz](https://github.com/vilhelmprytz)
3) [Linux123123](https://github.com/Linux123123)
4) [ImGreen](https://github.com/GreenDiscord)
5) [Neon](https://github.com/DeveloperNeon)
6) [sam1370](https://github.com/sam1370)
7) [Linux123123](https://github.com/Linux123123)
8) [sinjs](https://github.com/sinjs)

Copyright (C) 2018 - 2024, Vilhelm Prytz
Copyright (C) 2021 - 2024, Matthew Jacob
