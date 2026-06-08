<div align="center">
  <img src="https://raw.githubusercontent.com/junegunn/i/master/fzf-color.png" alt="fzf - a command-line fuzzy finder">
  <a href="https://github.com/junegunn/fzf/actions"><img src="https://github.com/junegunn/fzf/actions/workflows/linux.yml/badge.svg?branch=master" alt="Build Status"></a>
  <a href="http://github.com/junegunn/fzf/releases"><img src="https://img.shields.io/github/v/tag/junegunn/fzf" alt="Version"></a>
  <a href="https://github.com/junegunn/fzf?tab=MIT-1-ov-file#readme"><img src="https://img.shields.io/github/license/junegunn/fzf" alt="License"></a>
  <a href="https://github.com/junegunn/fzf/graphs/contributors"><img src="https://img.shields.io/github/contributors/junegunn/fzf" alt="Contributors"></a>
  <a href="https://github.com/sponsors/junegunn"><img src="https://img.shields.io/github/sponsors/junegunn" alt="Sponsors"></a>
  <a href="https://github.com/junegunn/fzf/stargazers"><img src="https://img.shields.io/github/stars/junegunn/fzf?style=flat" alt="Stars"></a>
</div>

---

<kbd align="center">
  <br/>
  <a href="https://commitgoods.com/collections/fzf"><img src="https://junegunn.github.io/fzf/images/fzf-mugs.jpg" width="80%" alt="fzf merch"></a>
  <br/>
  <br/>
  Show your love for fzf -- T-shirts, mugs, and stickers now available!
  <br/>
  <br/>
  <a href="https://commitgoods.com/collections/fzf">commitgoods.com/collections/fzf</a>
  <br/>
  <br/>
</kbd>

---

fzf is a general-purpose command-line fuzzy finder and an interactive terminal toolkit.

<img src="https://raw.githubusercontent.com/junegunn/i/master/fzf-preview.png" width=640>

Whether you're selecting files, browsing command history, previewing data,
navigating complex datasets with fuzzy matching, or creating custom menus and
workflows, fzf provides the building blocks to turn shell scripts into rich
terminal applications.

Highlights
----------

- **Portable** // Distributed as a single binary for easy installation
- **Fast** // Optimized to process millions of items in milliseconds
- **Programmable** // Event-driven architecture for building custom terminal interfaces and workflows
- **Batteries-included** // Comes with integrations for Bash, Zsh, Fish, Nushell, Vim, and Neovim

Table of Contents
-----------------

<!-- vim-markdown-toc GFM -->

* [Installation](#installation)
    * [Using Homebrew](#using-homebrew)
    * [Using Mise](#using-mise)
    * [Linux packages](#linux-packages)
    * [Windows packages](#windows-packages)
    * [Using git](#using-git)
    * [Binary releases](#binary-releases)
    * [Setting up shell integration](#setting-up-shell-integration)
    * [Vim/Neovim plugin](#vimneovim-plugin)
* [Upgrading fzf](#upgrading-fzf)
* [Building fzf](#building-fzf)
* [Usage](#usage)
    * [Using the finder](#using-the-finder)
    * [Display modes](#display-modes)
        * [`--height` mode](#--height-mode)
        * [`--popup` mode](#--popup-mode)
    * [Search syntax](#search-syntax)
    * [Environment variables](#environment-variables)
    * [Customizing the look](#customizing-the-look)
    * [Options](#options)
    * [Demo](#demo)
* [Examples](#examples)
* [Key bindings for command-line](#key-bindings-for-command-line)
* [Fuzzy completion](#fuzzy-completion)
    * [Files and directories](#files-and-directories)
    * [Process IDs](#process-ids)
    * [Host names](#host-names)
    * [Environment variables / Aliases](#environment-variables--aliases)
    * [Customizing fuzzy completion for bash and zsh](#customizing-fuzzy-completion-for-bash-and-zsh)
        * [Customizing fzf options for completion](#customizing-fzf-options-for-completion)
        * [Customizing completion source for paths and directories](#customizing-completion-source-for-paths-and-directories)
        * [Supported commands (bash)](#supported-commands-bash)
        * [Custom fuzzy completion](#custom-fuzzy-completion)
    * [Fuzzy completion for fish](#fuzzy-completion-for-fish)
    * [Fuzzy completion for Nushell](#fuzzy-completion-for-nushell)
* [Vim plugin](#vim-plugin)
* [Advanced topics](#advanced-topics)
    * [Customizing for different types of input](#customizing-for-different-types-of-input)
    * [Performance](#performance)
    * [Executing external programs](#executing-external-programs)
    * [Turning into a different process](#turning-into-a-different-process)
    * [Reloading the candidate list](#reloading-the-candidate-list)
        * [1. Update the list of processes by pressing CTRL-R](#1-update-the-list-of-processes-by-pressing-ctrl-r)
        * [2. Switch between sources by pressing CTRL-D or CTRL-F](#2-switch-between-sources-by-pressing-ctrl-d-or-ctrl-f)
        * [3. Interactive ripgrep integration](#3-interactive-ripgrep-integration)
    * [Preview window](#preview-window)
    * [Previewing an image](#previewing-an-image)
* [Tips](#tips)
    * [Respecting `.gitignore`](#respecting-gitignore)
    * [Fish shell](#fish-shell)
    * [fzf Theme Playground](#fzf-theme-playground)
* [Related projects](#related-projects)
* [License](#license)
* [Goods](#goods)
* [Sponsors :heart:](#sponsors-heart)

<!-- vim-markdown-toc -->

Installation
------------

### Using Homebrew

You can use [Homebrew](https://brew.sh/) (on macOS or Linux) to install fzf.

```sh
brew install fzf
```

> [!IMPORTANT]
> To set up shell integration (key bindings and fuzzy completion),
> see [the instructions below](#setting-up-shell-integration).

fzf is also available [via MacPorts][portfile]: `sudo port install fzf`

[portfile]: https://github.com/macports/macports-ports/blob/master/sysutils/fzf/Portfile

### Using Mise

You can use [mise](https://github.com/jdx/mise) to install fzf.

```sh
mise use -g fzf@latest
```

### Linux packages

| Package Manager | Linux Distribution      | Command                            |
| --------------- | ----------------------- | ---------------------------------- |
| APK             | Alpine Linux            | `sudo apk add fzf`                 |
| APT             | Debian 9+/Ubuntu 19.10+ | `sudo apt install fzf`             |
| Conda           |                         | `conda install -c conda-forge fzf` |
| DNF             | Fedora                  | `sudo dnf install fzf`             |
| Nix             | NixOS, etc.             | `nix-env -iA nixpkgs.fzf`          |
| Pacman          | Arch Linux              | `sudo pacman -S fzf`               |
| pkg             | FreeBSD                 | `pkg install fzf`                  |
| pkgin           | NetBSD                  | `pkgin install fzf`                |
| pkg_add         | OpenBSD                 | `pkg_add fzf`                      |
| Portage         | Gentoo                  | `emerge --ask app-shells/fzf`      |
| Spack           |                         | `spack install fzf`                |
| XBPS            | Void Linux              | `sudo xbps-install -S fzf`         |
| Zypper          | openSUSE                | `sudo zypper install fzf`          |

> [!IMPORTANT]
> To set up shell integration (key bindings and fuzzy completion),
> see [the instructions below](#setting-up-shell-integration).

[![Packaging status](https://repology.org/badge/vertical-allrepos/fzf.svg?columns=3)](https://repology.org/project/fzf/versions)

### Windows packages

On Windows, fzf is available via [Chocolatey][choco], [Scoop][scoop],
[Winget][winget], and [MSYS2][msys2]:

| Package manager | Command                               |
| --------------- | ------------------------------------- |
| Chocolatey      | `choco install fzf`                   |
| Scoop           | `scoop install fzf`                   |
| Winget          | `winget install fzf`                  |
| MSYS2 (pacman)  | `pacman -S $MINGW_PACKAGE_PREFIX-fzf` |

[choco]: https://chocolatey.org/packages/fzf
[scoop]: https://github.com/ScoopInstaller/Main/blob/master/bucket/fzf.json
[winget]: https://github.com/microsoft/winget-pkgs/tree/master/manifests/j/junegunn/fzf
[msys2]: https://packages.msys2.org/base/mingw-w64-fzf

### Using git

Alternatively, you can "git clone" this repository to any directory and run
[install](https://github.com/junegunn/fzf/blob/master/install) script.

```sh
git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
~/.fzf/install
```

The install script will add lines to your shell configuration file to modify
`$PATH` and set up shell integration.

### Binary releases

You can download the official fzf binaries from the releases page.

* https://github.com/junegunn/fzf/releases

### Setting up shell integration

Add the following line to your shell configuration file.

* bash
  ```sh
  # Set up fzf key bindings and fuzzy completion
  eval "$(fzf --bash)"
  ```
* zsh
  ```sh
  # Set up fzf key bindings and fuzzy completion
  source <(fzf --zsh)
  ```
* fish
  ```fish
  # Set up fzf key bindings
  fzf --fish | source
  ```
* Nushell -- Nushell does not support piping into `source`, so the install
  script generates a file in the autoload directory. If you didn't use the
  install script, you can manually set it up:
  ```nu
  # Generate the integration script
  mkdir ($nu.default-config-dir | path join "autoload")
  fzf --nushell | save -f ($nu.default-config-dir | path join "autoload" "_fzf_integration.nu")
  ```

> [!NOTE]
> `--bash`, `--zsh`, `--fish`, and `--nushell` options are only available in
> recent versions of fzf. If you have an older version of fzf, or want finer control, you can
> source individual script files in the [/shell](/shell) directory. The
> location of the files may vary depending on the package manager you use.
> Please refer to the package documentation for more information.
> (e.g. `apt show fzf`)

> [!TIP]
> You can disable CTRL-T, CTRL-R, or ALT-C bindings by setting the
> corresponding `*_COMMAND` variable to an empty string when sourcing the
> script. For example, to disable CTRL-R and ALT-C:
>
> * bash: `FZF_CTRL_R_COMMAND= FZF_ALT_C_COMMAND= eval "$(fzf --bash)"`
> * zsh: `FZF_CTRL_R_COMMAND= FZF_ALT_C_COMMAND= source <(fzf --zsh)`
> * fish: `fzf --fish | FZF_CTRL_R_COMMAND= FZF_ALT_C_COMMAND= source`
> * nushell: add to your `env.nu`:
>   `$env.FZF_CTRL_R_COMMAND = ""; $env.FZF_ALT_C_COMMAND = ""`
>
> Setting the variables after sourcing the script will have no effect.

### Vim/Neovim plugin

If you use [vim-plug](https://github.com/junegunn/vim-plug), add this to
your Vim configuration file:

```vim
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim'
```

* `junegunn/fzf` provides the basic library functions
    * `fzf#install()` makes sure that you have the latest binary
* `junegunn/fzf.vim` is [a separate project](https://github.com/junegunn/fzf.vim)
  that provides a variety of useful commands

To learn more about the Vim integration, see [README-VIM.md](README-VIM.md).

> [!TIP]
> If you use Neovim and prefer Lua-based plugins, check out
> [fzf-lua](https://github.com/ibhagwan/fzf-lua).

Upgrading fzf
-------------

fzf is being actively developed, and you might want to upgrade it once in a
while. Please follow the instruction below depending on the installation
method used.

- git: `cd ~/.fzf && git pull && ./install`
- brew: `brew update; brew upgrade fzf`
- macports: `sudo port upgrade fzf`
- chocolatey: `choco upgrade fzf`
- vim-plug: `:PlugUpdate fzf`

Building fzf
------------

See [BUILD.md](BUILD.md).

Usage
-----

fzf will launch interactive finder, read the list from STDIN, and write the
selected item to STDOUT.

```sh
find * -type f | fzf > selected
```

Without STDIN pipe, fzf will traverse the file system under the current
directory to get the list of files.

```sh
vim $(fzf)
```

> [!NOTE]
> You can override the default behavior
> * Either by setting `$FZF_DEFAULT_COMMAND` to a command that generates the desired list
> * Or by setting `--walker`, `--walker-root`, and `--walker-skip` options in `$FZF_DEFAULT_OPTS`

> [!WARNING]
> A more robust solution would be to use `xargs` but we've presented
> the above as it's easier to grasp
> ```sh
> fzf --print0 | xargs -0 -o vim
> ```

> [!TIP]
> fzf also has the ability to turn itself into a different process.
>
> ```sh
> fzf --bind 'enter:become(vim {})'
> ```
>
> *See [Turning into a different process](#turning-into-a-different-process)
> for more information.*

### Using the finder

- `CTRL-K` / `CTRL-J` (or `CTRL-P` / `CTRL-N`) to move cursor up and down
- `Enter` key to select the item, `CTRL-C` / `CTRL-G` / `ESC` to exit
- On multi-select mode (`-m`), `TAB` and `Shift-TAB` to mark multiple items
- Emacs style key bindings
- Mouse: scroll, click, double-click; shift-click and shift-scroll on
  multi-select mode

### Display modes

fzf by default runs in fullscreen mode, but there are other display modes.

#### `--height` mode

With `--height HEIGHT[%]`, fzf will start below the cursor with the given height.

```sh
fzf --height 40%
```

`reverse` layout and `--border` goes well with this option.

```sh
fzf --height 40% --layout reverse --border
```

By prepending `~` to the height, you're setting the maximum height.

```sh
# Will take as few lines as possible to display the list
seq 3 | fzf --height ~100%
seq 3000 | fzf --height ~100%
```

Height value can be a negative number.

```sh
# Screen height - 3
fzf --height -3
```

#### `--popup` mode

With `--popup` option, fzf will start in a popup window
(requires tmux 3.3+ or Zellij 0.44+).

```sh
# --popup [center|top|bottom|left|right][,SIZE[%]][,SIZE[%][,border-native]]

fzf --popup center         # Center, 50% width and height
fzf --popup 80%            # Center, 80% width and height
fzf --popup 100%,50%       # Center, 100% width and 50% height
fzf --popup left,40%       # Left, 40% width
fzf --popup left,40%,90%   # Left, 40% width, 90% height
fzf --popup top,40%        # Top, 40% height
fzf --popup bottom,80%,40% # Bottom, 80% width, 40% height
```

`--popup` is silently ignored when you're not on tmux or Zellij.

> [!NOTE]
> If you're stuck with an old version of tmux that doesn't support popup,
> or if you want to open fzf in a regular tmux pane, check out
> [fzf-tmux](bin/fzf-tmux) script.

> [!TIP]
> You can add these options to `$FZF_DEFAULT_OPTS` so that they're applied by
> default. For example,
>
> ```sh
> # Open in a popup if on tmux or Zellij, otherwise use --height mode
> export FZF_DEFAULT_OPTS='--height 40% --popup bottom,40% --layout reverse --border top'
> ```

### Search syntax

Unless otherwise specified, fzf starts in "extended-search mode" where you can
type in multiple search terms delimited by spaces. e.g. `^music .mp3$ sbtrkt
!fire`

| Token     | Match type                              | Description                                  |
| --------- | --------------------------------------  | ------------------------------------------   |
| `sbtrkt`  | fuzzy-match                             | Items that match `sbtrkt`                    |
| `'wild`   | exact-match (quoted)                    | Items that include `wild`                    |
| `'wild'`  | exact-boundary-match (quoted both ends) | Items that include `wild` at word boundaries |
| `^music`  | prefix-exact-match                      | Items that start with `music`                |
| `.mp3$`   | suffix-exact-match                      | Items that end with `.mp3`                   |
| `!fire`   | inverse-exact-match                     | Items that do not include `fire`             |
| `!^music` | inverse-prefix-exact-match              | Items that do not start with `music`         |
| `!.mp3$`  | inverse-suffix-exact-match              | Items that do not end with `.mp3`            |

If you don't prefer fuzzy matching and do not wish to "quote" every word,
start fzf with `-e` or `--exact` option. Note that when  `--exact` is set,
`'`-prefix "unquotes" the term.

A single bar character term acts as an OR operator. For example, the following
query matches entries that start with `core` and end with either `go`, `rb`,
or `py`.

```
^core go$ | rb$ | py$
```

### Environment variables

- `FZF_DEFAULT_COMMAND`
    - Default command to use when input is tty
    - e.g. `export FZF_DEFAULT_COMMAND='fd --type f'`
- `FZF_DEFAULT_OPTS`
    - Default options
    - e.g. `export FZF_DEFAULT_OPTS="--layout=reverse --inline-info"`
- `FZF_DEFAULT_OPTS_FILE`
    - If you prefer to manage default options in a file, set this variable to
      point to the location of the file
    - e.g. `export FZF_DEFAULT_OPTS_FILE=~/.fzfrc`

> [!WARNING]
> `FZF_DEFAULT_COMMAND` is not used by shell integration due to the
> slight difference in requirements.
>
> * `CTRL-T` runs `$FZF_CTRL_T_COMMAND` to get a list of files and directories
> * `ALT-C` runs `$FZF_ALT_C_COMMAND` to get a list of directories
> * `vim ~/**<tab>` runs `fzf_compgen_path()` with the prefix (`~/`) as the first argument
> * `cd foo**<tab>` runs `fzf_compgen_dir()` with the prefix (`foo`) as the first argument
>
> The available options are described later in this document.

### Customizing the look

The user interface of fzf is fully customizable with a large number of
configuration options. For a quick setup, you can start with one of the style
presets -- `default`, `full`, or `minimal` -- using the `--style` option.

```sh
fzf --style full \
    --preview 'fzf-preview.sh {}' --bind 'focus:transform-header:file --brief {}'
```

| Preset    | Screenshot                                                                             |
| :---      | :---                                                                                   |
| `default` | <img src="https://raw.githubusercontent.com/junegunn/i/master/fzf-style-default.png"/> |
| `full`    | <img src="https://raw.githubusercontent.com/junegunn/i/master/fzf-style-full.png"/>    |
| `minimal` | <img src="https://raw.githubusercontent.com/junegunn/i/master/fzf-style-minimal.png"/> |

Here's an example based on the `full` preset:

<img src="https://raw.githubusercontent.com/junegunn/i/master/fzf-4-borders.png"/>

<details>

```sh
git ls-files | fzf --style full \
    --border --padding 1,2 \
    --border-label ' Demo ' --input-label ' Input ' --header-label ' File Type ' \
    --preview 'fzf-preview.sh {}' \
    --bind 'result:transform-list-label:
        if [[ -z $FZF_QUERY ]]; then
          echo " $FZF_MATCH_COUNT items "
        else
          echo " $FZF_MATCH_COUNT matches for [$FZF_QUERY] "
        fi
        ' \
    --bind 'focus:transform-preview-label:[[ -n {} ]] && printf " Previewing [%s] " {}' \
    --bind 'focus:+transform-header:file --brief {} || echo "No file selected"' \
    --bind 'ctrl-r:change-list-label( Reloading the list )+reload(sleep 2; git ls-files)' \
    --color 'border:#aaaaaa,label:#cccccc' \
    --color 'preview-border:#9999cc,preview-label:#ccccff' \
    --color 'list-border:#669966,list-label:#99cc99' \
    --color 'input-border:#996666,input-label:#ffcccc' \
    --color 'header-border:#6699cc,header-label:#99ccff'
```

</details>

### Options

See the man page (`fzf --man` or `man fzf`) for the full list of options.

### Demo
If you learn by watching videos, check out this screencast by [@samoshkin](https://github.com/samoshkin) to explore `fzf` features.

<a title="fzf - command-line fuzzy finder" href="https://www.youtube.com/watch?v=qgG5Jhi_Els">
  <img src="https://i.imgur.com/vtG8olE.png" width="640">
</a>

Examples
--------

* [Wiki page of examples](https://github.com/junegunn/fzf/wiki/examples)
    * *Disclaimer: The examples on this page are maintained by the communit
