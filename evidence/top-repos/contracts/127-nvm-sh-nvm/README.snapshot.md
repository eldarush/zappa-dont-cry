<a href="https://github.com/nvm-sh/logos">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/nvm-sh/logos/HEAD/nvm-logo-white.svg" />
    <img src="https://raw.githubusercontent.com/nvm-sh/logos/HEAD/nvm-logo-color.svg" height="50" alt="nvm project logo" />
  </picture>
</a>


# Node Version Manager [![Tests](https://github.com/nvm-sh/nvm/actions/workflows/tests-fast.yml/badge.svg?branch=master)][3] [![nvm version](https://img.shields.io/badge/version-v0.40.5-yellow.svg)][4] [![CII Best Practices](https://bestpractices.dev/projects/684/badge)](https://bestpractices.dev/projects/684)

<!-- To update this table of contents, ensure you have run `npm install` then `npm run doctoc` -->
<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
## Table of Contents

- [Intro](#intro)
- [About](#about)
- [Installing and Updating](#installing-and-updating)
  - [Install & Update Script](#install--update-script)
    - [Additional Notes](#additional-notes)
    - [Installing in Docker](#installing-in-docker)
      - [Installing in Docker for CICD-Jobs](#installing-in-docker-for-cicd-jobs)
    - [Troubleshooting on Linux](#troubleshooting-on-linux)
    - [Troubleshooting on macOS](#troubleshooting-on-macos)
    - [Ansible](#ansible)
  - [Verify Installation](#verify-installation)
  - [Important Notes](#important-notes)
  - [Git Install](#git-install)
  - [Manual Install](#manual-install)
  - [Manual Upgrade](#manual-upgrade)
- [Usage](#usage)
  - [Long-term Support](#long-term-support)
  - [Migrating Global Packages While Installing](#migrating-global-packages-while-installing)
  - [Offline Install](#offline-install)
  - [Default Global Packages From File While Installing](#default-global-packages-from-file-while-installing)
  - [io.js](#iojs)
  - [System Version of Node](#system-version-of-node)
  - [Listing Versions](#listing-versions)
  - [Setting Custom Colors](#setting-custom-colors)
    - [Persisting custom colors](#persisting-custom-colors)
    - [Suppressing colorized output](#suppressing-colorized-output)
  - [Restoring PATH](#restoring-path)
  - [Set default node version](#set-default-node-version)
  - [Use a mirror of node binaries](#use-a-mirror-of-node-binaries)
    - [Pass Authorization header to mirror](#pass-authorization-header-to-mirror)
  - [.nvmrc](#nvmrc)
  - [Deeper Shell Integration](#deeper-shell-integration)
    - [Calling `nvm use` automatically in a directory with a `.nvmrc` file](#calling-nvm-use-automatically-in-a-directory-with-a-nvmrc-file)
      - [bash](#bash)
      - [zsh](#zsh)
      - [fish](#fish)
- [Running Tests](#running-tests)
- [Environment variables](#environment-variables)
- [Bash Completion](#bash-completion)
  - [Usage](#usage-1)
- [Compatibility Issues](#compatibility-issues)
- [Installing nvm on Alpine Linux](#installing-nvm-on-alpine-linux)
  - [Alpine Linux 3.13+](#alpine-linux-313)
  - [Alpine Linux 3.5 - 3.12](#alpine-linux-35---312)
- [Uninstalling / Removal](#uninstalling--removal)
  - [Manual Uninstall](#manual-uninstall)
- [Docker For Development Environment](#docker-for-development-environment)
- [Problems](#problems)
- [macOS Troubleshooting](#macos-troubleshooting)
- [WSL Troubleshooting](#wsl-troubleshooting)
- [Maintainers](#maintainers)
- [Project Support](#project-support)
- [Enterprise Support](#enterprise-support)
- [License](#license)
- [Copyright notice](#copyright-notice)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## Intro

`nvm` allows you to quickly install and use different versions of node via the command line.

**Example:**
```sh
$ nvm install 24
Now using node v24.14.0 (npm v11.9.0)
$ node -v
v24.14.0
$ nvm use 22
Now using node v22.22.1 (npm v10.9.4)
$ node -v
v22.22.1
$ nvm use 20
Now using node v20.20.1 (npm v10.8.2)
$ node -v
v20.20.1
```

Simple as that!


## About
nvm is a version manager for [node.js](https://nodejs.org/en/), designed to be installed per-user, and invoked per-shell. `nvm` works on any POSIX-compliant shell (sh, dash, ksh, zsh, bash), in particular on these platforms: unix, macOS, and [Windows WSL](https://github.com/nvm-sh/nvm#important-notes).

<a id="installation-and-update"></a>
<a id="install-script"></a>
## Installing and Updating

### Install & Update Script

To **install** or **update** nvm, you should run the [install script][2]. To do that, you may either download and run the script manually, or use the following cURL or Wget command:
```sh
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.5/install.sh | bash
```
```sh
wget -qO- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.5/install.sh | bash
```

Running either of the above commands downloads a script and runs it. The script clones the nvm repository to `~/.nvm`, and attempts to add the source lines from the snippet below to the correct profile file (`~/.bashrc`, `~/.bash_profile`, `~/.zshrc`, or `~/.profile`). If you find the install script is updating the wrong profile file, set the `$PROFILE` env var to the profile file’s path, and then rerun the installation script.

<a id="profile_snippet"></a>
```sh
export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" # This loads nvm
```

#### Additional Notes

- If the environment variable `$XDG_CONFIG_HOME` is present, it will place the `nvm` files there.</sub>

- You can add `--no-use` to the end of the above script to postpone using `nvm` until you manually [`use`](#usage) it:

```sh
export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" --no-use # This loads nvm, without auto-using the default version
```

- You can customize the install source, directory, profile, and version using the `NVM_SOURCE`, `NVM_DIR`, `PROFILE`, and `NODE_VERSION` variables.
Eg: `curl ... | NVM_DIR="path/to/nvm"`. Ensure that the `NVM_DIR` does not contain a trailing slash.

- The installer can use `git`, `curl`, or `wget` to download `nvm`, whichever is available.

- You can instruct the installer to not edit your shell config (for example if you already get completions via a [zsh nvm plugin](https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/nvm)) by setting `PROFILE=/dev/null` before running the `install.sh` script. Here's an example one-line command to do that: `PROFILE=/dev/null bash -c 'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.5/install.sh | bash'`

#### Installing in Docker

When invoking bash as a non-interactive shell, like in a Docker container, none of the regular profile files are sourced. In order to use `nvm`, `node`, and `npm` like normal, you can instead specify the special `BASH_ENV` variable, which bash sources when invoked non-interactively.

```Dockerfile
# Use bash for the shell
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Create a script file sourced by both interactive and non-interactive bash shells
ENV BASH_ENV "${HOME}/.bash_env"
RUN touch "${BASH_ENV}"
RUN echo '. "${BASH_ENV}"' >> ~/.bashrc

# Download and install nvm
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.5/install.sh | PROFILE="${BASH_ENV}" bash
RUN echo node > .nvmrc
RUN nvm install
```

##### Installing in Docker for CICD-Jobs

More robust, works in CI/CD-Jobs. Can be run in interactive and non-interactive containers.
See https://github.com/nvm-sh/nvm/issues/3531.

```Dockerfile
FROM ubuntu:latest
ARG NODE_VERSION=20

# install curl
RUN apt update && apt install curl -y

# install nvm
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.5/install.sh | bash

# set env
ENV NVM_DIR=/root/.nvm

# install node
RUN bash -c "source $NVM_DIR/nvm.sh && nvm install $NODE_VERSION"

# set ENTRYPOINT for reloading nvm-environment
ENTRYPOINT ["bash", "-c", "source $NVM_DIR/nvm.sh && exec \"$@\"", "--"]

# set cmd to bash
CMD ["/bin/bash"]

```

This example defaults to installation of nodejs version 20.x.y. Optionally you can easily override the version with docker build args like:
```
docker build -t nvmimage --build-arg NODE_VERSION=19 .
```

After creation of the image you can start container interactively and run commands, for example:
```
docker run --rm -it nvmimage

root@0a6b5a237c14:/# nvm -v
0.40.5

root@0a6b5a237c14:/# node -v
v19.9.0

root@0a6b5a237c14:/# npm -v
9.6.3
```

Noninteractive example:
```
user@host:/tmp/test $ docker run --rm -it nvmimage node -v
v19.9.0
user@host:/tmp/test $ docker run --rm -it nvmimage npm -v
9.6.3
```

#### Troubleshooting on Linux

On Linux, after running the install script, if you get `nvm: command not found` or see no feedback from your terminal after you type `command -v nvm`, simply close your current terminal, open a new terminal, and try verifying again.
Alternatively, you can run the following commands for the different shells on the command line:

*bash*: `source ~/.bashrc`

*zsh*: `source ~/.zshrc`

*ksh*: `. ~/.profile`

These should pick up the `nvm` command.

#### Troubleshooting on macOS

Since OS X 10.9, `/usr/bin/git` has been preset by Xcode command line tools, which means we can't properly detect if Git is installed or not. You need to manually install the Xcode command line tools before running the install script, otherwise, it'll fail. (see [#1782](https://github.com/nvm-sh/nvm/issues/1782))

If you get `nvm: command not found` after running the install script, one of the following might be the reason:

  - Since macOS 10.15, the default shell is `zsh` and nvm will look for `.zshrc` to update, none is installed by default. Create one with `touch ~/.zshrc` and run the install script again.

  - If you use bash, the previous default shell, your system may not have `.bash_profile` or `.bashrc` files where the command is set up. Create one of them with `touch ~/.bash_profile` or `touch ~/.bashrc` and run the install script again. Then, run `. ~/.bash_profile` or `. ~/.bashrc` to pick up the `nvm` command.

  - You have previously used `bash`, but you have `zsh` installed. You need to manually add [these lines](#manual-install) to `~/.zshrc` and run `. ~/.zshrc`.

  - You might need to restart your terminal instance or run `. ~/.nvm/nvm.sh`. Restarting your terminal/opening a new tab/window, or running the source command will load the command and the new configuration.

  - If the above didn't help, you might need to restart your terminal instance. Try opening a new tab/window in your terminal and retry.

If the above doesn't fix the problem, you may try the following:

  - If you use bash, it may be that your `.bash_profile` (or `~/.profile`) does not source your `~/.bashrc` properly. You could fix this by adding `source ~/<your_profile_file>` to it or following the next step below.

  - Try adding [the snippet from the install section](#profile_snippet), that finds the correct nvm directory and loads nvm, to your usual profile (`~/.bash_profile`, `~/.zshrc`, `~/.profile`, or `~/.bashrc`).

  - For more information about this issue and possible workarounds, please [refer here](https://github.com/nvm-sh/nvm/issues/576)

**Note** For Macs with the Apple Silicon chip, node started offering **arm64** arch Darwin packages since v16.0.0 and experimental **arm64** support when compiling from source since v14.17.0. If you are facing issues installing node using `nvm`, you may want to update to one of those versions or later.

#### Ansible

You can use a task:

```yaml
- name: Install nvm
  ansible.builtin.shell: >
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.5/install.sh | bash
  args:
    creates: "{{ ansible_env.HOME }}/.nvm/nvm.sh"
```

### Verify Installation

To verify that nvm has been installed, do:

```sh
command -v nvm
```

which should output `nvm` if the installation was successful. Please note that `which nvm` will not work, since `nvm` is a sourced shell function, not an executable binary.

**Note:** On Linux, after running the install script, if you get `nvm: command not found` or see no feedback from your terminal after you type `command -v nvm`, simply close your current terminal, open a new terminal, and try verifying again.

### Important Notes

If you're running a system without prepackaged binary available, which means you're going to install node or io.js from its source code, you need to make sure your system has a C++ compiler. For OS X, Xcode will work, for Debian/Ubuntu based GNU/Linux, the `build-essential` and `libssl-dev` packages work.

**Note:** `nvm` also supports Windows in some cases. It should work through WSL (Windows Subsystem for Linux) depending on the version of WSL. It should also work with [Git Bash](https://gitforwindows.org/) (MSYS) or [Cygwin](https://cygwin.com). Otherwise, for Windows, a few alternatives exist, which are neither supported nor developed by us:

  - [nvm-windows](https://github.com/coreybutler/nvm-windows)
  - [nodist](https://github.com/marcelklehr/nodist)
  - [nvs](https://github.com/jasongin/nvs)

**Note:** `nvm` does not support [Fish] either (see [#303](https://github.com/nvm-sh/nvm/issues/303)). Alternatives exist, which are neither supported nor developed by us:

  - [bass](https://github.com/edc/bass) allows you to use utilities written for Bash in fish shell
  - [fast-nvm-fish](https://github.com/brigand/fast-nvm-fish) only works with version numbers (not aliases) but doesn't significantly slow your shell startup
  - [plugin-nvm](https://github.com/derekstavis/plugin-nvm) plugin for [Oh My Fish](https://github.com/oh-my-fish/oh-my-fish), which makes nvm and its completions available in fish shell
  - [nvm.fish](https://github.com/jorgebucaran/nvm.fish) - The Node.js version manager you'll adore, crafted just for Fish
  - [fish-nvm](https://github.com/FabioAntunes/fish-nvm) - Wrapper around nvm for fish, delays sourcing nvm until it's actually used.

**Note:** We still have some problems with FreeBSD, because there is no official pre-built binary for FreeBSD, and building from source may need [patches](https://www.freshports.org/www/node/files/patch-deps_v8_src_base_platform_platform-posix.cc); see the issue ticket:

  - [[#900] [Bug] node on FreeBSD may need to be patched](https://github.com/nvm-sh/nvm/issues/900)
  - [nodejs/node#3716](https://github.com/nodejs/node/issues/3716)

**Note:** On OS X, if you do not have Xcode installed and you do not wish to download the ~4.3GB file, you can install the `Command Line Tools`. You can check out this blog post on how to just that:

  - [How to Install Command Line Tools in OS X Mavericks & Yosemite (Without Xcode)](https://osxdaily.com/2014/02/12/install-command-line-tools-mac-os-x/)

**Note:** On OS X, if you have/had a "system" node installed and want to install modules globally, keep in mind that:

  - When using `nvm` you do not need `sudo` to globally install a module with `npm -g`, so instead of doing `sudo npm install -g grunt`, do instead `npm install -g grunt`
  - If you have an `~/.npmrc` file, make sure it does not contain any `prefix` settings (which is not compatible with `nvm`)
  - You can (but should not?) keep your previous "system" node install, but `nvm` will only be available to your user account (the one used to install nvm). This might cause version mismatches, as other users will be using `/usr/local/lib/node_modules/*` VS your user account using `~/.nvm/versions/node/vX.X.X/lib/node_modules/*`

Homebrew installation is not supported. If you have issues with homebrew-installed `nvm`, please `brew uninstall` it, and install it using the instructions below, before filing an issue.

**Note:** If you're using `zsh` you can easily install `nvm` as a zsh plugin. Install [`zsh-nvm`](https://github.com/lukechilds/zsh-nvm) and run `nvm upgrade` to upgrade ([you can set](https://github.com/lukechilds/zsh-nvm#auto-use) `NVM_AUTO_USE=true` to have it automatically detect and use `.nvmrc` files).

**Note:** Git versions before v1.7 may face a problem of cloning `nvm` source from GitHub via https protocol, and there is also different behavior of git before v1.6, and git prior to [v1.17.10](https://github.com/git/git/commit/5a7d5b683f869d3e3884a89775241afa515da9e7) can not clone tags, so the minimum required git version is v1.7.10. If you are interested in the problem we mentioned here, please refer to GitHub's [HTTPS cloning errors](https://help.github.com/articles/https-cloning-errors/) article.

### Git Install

If you have `git` installed (requires git v1.7.10+):

1. clone this repo in the root of your user profile
    - `cd ~/` from anywhere then `git clone https://github.com/nvm-sh/nvm.git .nvm`
1. `cd ~/.nvm` and check out the latest version with `git checkout v0.40.5`
1. activate `nvm` by sourcing it from your shell: `. ./nvm.sh`

Now add these lines to your `~/.bashrc`, `~/.profile`, or `~/.zshrc` file to have it automatically sourced upon login:
(you may have to add to more than one of the above files)

```sh
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
```

### Manual Install

For a fully manual install, execute the following lines to first clone the `nvm` repository into `$HOME/.nvm`, and then load `nvm`:

```sh
export NVM_DIR="$HOME/.nvm" && (
  git clone https://github.com/nvm-sh/nvm.git "$NVM_DIR"
  cd "$NVM_DIR"
  git checkout `git describe --abbrev=0 --tags --match "v[0-9]*" $(git rev-list --tags --max-count=1)`
) && \. "$NVM_DIR/nvm.sh"
```

Now add these lines to your `~/.bashrc`, `~/.profile`, or `~/.zshrc` file to have it automatically sourced upon login:
(you may have to add to more than one of the above files)

```sh
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
```

### Manual Upgrade

For manual upgrade with `git` (requires git v1.7.10+):

1. change to the `$NVM_DIR`
1. pull down the latest changes
1. check out the latest version
1. activate the new version

```sh
(
  cd "$NVM_DIR"
  git fetch --tags origin
  git checkout `git describe --abbrev=0 --tags --match "v[0-9]*" $(git rev-list --tags --max-count=1)`
) && \. "$NVM_DIR/nvm.sh"
```

## Usage

To download, compile, and install the latest release of node, do this:

```sh
nvm install node # "node" is an alias for the latest version
```

To install a specific version of node:

```sh
nvm install 14.7.0 # or 16.3.0, 12.22.1, etc
```

To set an alias:

```sh
nvm alias my_alias v14.4.0
```
Make sure that your alias does not contain any spaces or slashes.

The first version installed becomes the default. New shells will start with the default version of node (e.g., `nvm alias default`).

You can list available versions using `ls-remote`:

```sh
nvm ls-remote
```

And then in any new shell just use the installed version:

```sh
nvm use node
```

Or you can just run it:

```sh
nvm run node --version
```

Or, you can run any arbitrary command in a subshell with the desired version of node:

```sh
nvm exec 4.2 node --version
```

You can also get the path to the executable to where it was installed:

```sh
nvm which 12.22
```

In place of a version pointer like "14.7" or "16.3" or "12.22.1", you can use the following special default aliases wit
