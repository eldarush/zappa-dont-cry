[![](docs/readme.png)](https://tabby.sh)


<p align="center">
  <a href="https://github.com/Eugeny/tabby/releases/latest"><img alt="GitHub All Releases" src="https://img.shields.io/github/downloads/eugeny/tabby/total.svg?label=DOWNLOADS&logo=github&style=for-the-badge"></a> &nbsp; <a href="https://nightly.link/Eugeny/tabby/workflows/build/master"><img src="https://shields.io/badge/-Nightly%20Builds-orange?logo=hackthebox&logoColor=fff&style=for-the-badge"/></a> &nbsp; <a href="https://discord.gg/Vn7BjmzhtF"><img alt="Discord" src="https://img.shields.io/discord/1280890060195233934?style=for-the-badge&color=blue&logo=discord&logoColor=white&label=Discord"></a> &nbsp <a href="https://translate.tabby.sh/"><img alt="Translate" src="https://shields.io/badge/Translate-UI-white?logo=googletranslate&style=for-the-badge&color=white&logoColor=fff"></a>
</p>

<p align="center">
  <a href="https://ko-fi.com/J3J8KWTF">
    <img src="https://cdn.ko-fi.com/cdn/kofi3.png?v=2" width="150">
  </a>
</p>

---


> 👋 Managing remote environments? Check out [Warpgate, my smart SSH/HTTP/MySQL bastion server](https://github.com/warp-tech/warpgate), it works great with Tabby, you'll love it.

----

### Downloads:

* [Latest release](https://github.com/Eugeny/tabby/releases/latest)
* [Repositories](https://packagecloud.io/eugeny/tabby): [Debian/Ubuntu-based](https://packagecloud.io/eugeny/tabby/install#bash-deb), [RPM-based](https://packagecloud.io/eugeny/tabby/install#bash-rpm)
* [Latest nightly build](https://nightly.link/Eugeny/tabby/workflows/build/master)

<br/>
<p align="center">
This README is also available in: <a  href="./README.es-ES.md">:es: Spanish</a> · <a  href="./README.ru-RU.md">:ru: Русский</a> · <a  href="./README.ko-KR.md">:kr: 한국어</a> · <a  href="./README.zh-CN.md">:cn: 简体中文</a> · <a  href="./README.it-IT.md">:it: Italiano</a> · <a href="./README.de-DE.md">:de: Deutsch</a> · <a href="./README.ja-JP.md">:jp: 日本語</a> · <a href="./README.id-ID.md">:id: Bahasa Indonesia</a> · <a href="./README.pt-BR.md">:brazil: Português</a> · <a href="./README.pl-PL.md">:poland: Polski</a>
</p>

----

[**Tabby**](https://tabby.sh) (formerly **Terminus**) is a highly configurable terminal emulator, SSH and serial client for Windows, macOS and Linux

* Integrated SSH and Telnet client and connection manager
* Integrated serial terminal
* Theming and color schemes
* Fully configurable shortcuts and multi-chord shortcuts
* Split panes
* Remembers your tabs
* PowerShell (and PS Core), WSL, Git-Bash, Cygwin, MSYS2, Cmder and CMD support
* Direct file transfer from/to SSH sessions via Zmodem
* Full Unicode support including double-width characters
* Doesn't choke on fast-flowing outputs
* Proper shell experience on Windows including tab completion (via Clink)
* Integrated encrypted container for SSH secrets and configuration
* SSH, SFTP and Telnet client available as a [web app](https://tabby.sh/app) (also [self-hosted](https://github.com/Eugeny/tabby-web)).

# Contents <!-- omit in toc -->

- [What Tabby is and isn't](#what-tabby-is-and-isnt)
- [Terminal features](#terminal-features)
- [SSH Client](#ssh-client)
- [Serial Terminal](#serial-terminal)
- [Portable](#portable)
- [Plugins](#plugins)
- [Themes](#themes)
- [Contributing](#contributing)

<a name="about"></a>

# What Tabby is and isn't

* **Tabby is** an alternative to Windows' standard terminal (conhost), PowerShell ISE, PuTTY, macOS Terminal.app and iTerm

* **Tabby is not** a new shell or a MinGW or Cygwin replacement. Neither is it lightweight - if RAM usage is of importance, consider [Conemu](https://conemu.github.io) or [Alacritty](https://github.com/jwilm/alacritty)

<a name="terminal"></a>

# Terminal features

![](docs/readme-terminal.png)

* A VT220 terminal + various extensions
* Multiple nested split panes
* Tabs on any side of the window
* Optional dockable window with a global spawn hotkey ("Quake console")
* Progress detection
* Notification on process completion
* Bracketed paste, multiline paste warnings
* Font ligatures
* Custom shell profiles
* Optional RMB paste and copy-on select (PuTTY style)

<a name="ssh"></a>

# SSH Client

![](docs/readme-ssh.png)

* SSH2 client with a connection manager
* X11 and port forwarding
* Automatic jump host management
* Agent forwarding (incl. Pageant and Windows native OpenSSH Agent)
* Login scripts

<a name="serial"></a>

# Serial Terminal

* Saved connections
* Readline input support
* Optional hex byte-by-byte input and hexdump output
* Newline conversion
* Automatic reconnection

<a name="portable"></a>

# Portable

Tabby will run as a portable app on Windows, if you create a `data` folder in the same location where `Tabby.exe` lives.

<a name="plugins"></a>

# Plugins

Plugins and themes can be installed directly from the Settings view inside Tabby.

* [docker](https://github.com/Eugeny/tabby-docker) - connect to Docker containers
* [title-control](https://github.com/kbjr/terminus-title-control) - allows modifying the title of the terminal tabs by providing a prefix, suffix, and/or strings to be removed
* [quick-cmds](https://github.com/minyoad/tabby-quick-cmds) - quickly send commands to one or all terminal tabs
* [save-output](https://github.com/Eugeny/tabby-save-output) - record terminal output into a file
* [sync-config](https://github.com/starxg/terminus-sync-config) - sync the config to Gist or Gitee
* [clippy](https://github.com/Eugeny/tabby-clippy) - an example plugin which annoys you all the time
* [workspace-manager](https://github.com/composer404/tabby-workspace-manager) - allows creating custom workspace profiles based on the given config
* [search-in-browser](https://github.com/composer404/tabby-search-in-browser) - opens default system browser with a text selected from the Tabby's tab
* [sftp-tab](https://github.com/wljince007/tabby-sftp-tab) - open sftp tab for ssh connection like SecureCRT
* [background](https://github.com/moemoechu/tabby-background) - change Tabby background image and more...
* [highlight](https://github.com/moemoechu/tabby-highlight) - Tabby terminal keyword highlight plugin
* [web-auth-handler](https://github.com/Jazzmoon/tabby-web-auth-handler) - In-app web authentication popups (Built primarily for warpgate in-browser auth)
* [mcp-server](https://github.com/thuanpham582002/tabby-mcp-server) - Powerful Model Context Protocol server integration for Tabby that seamlessly connects with AI assistants through MCP clients like Cursor and Windsurf, enhancing your terminal workflow with intelligent AI capabilities.
* [ssh-keymap](https://github.com/mathys-lopinto/tabby-ssh-keymap) - lets your synced Tabby SSH profiles reference private keys by name instead of by absolute file path. A local mapping file (never synced) translates each name to the real path on that machine * [serial-timestamp](https://github.com/WoodenNautilus/tabby-serial-timestamp) - adds timestamps to serial terminal sessions

<a name="themes"></a>

# Themes

* [hype](https://github.com/Eugeny/tabby-theme-hype) - a Hyper inspired theme
* [relaxed](https://github.com/Relaxed-Theme/relaxed-terminal-themes#terminus) - the Relaxed theme for Tabby
* [gruvbox](https://github.com/porkloin/terminus-theme-gruvbox)
* [windows10](https://www.npmjs.com/package/terminus-theme-windows10)
* [altair](https://github.com/yxuko/terminus-altair)
* [catppuccin](https://github.com/catppuccin/tabby) - Soothing pastel theme for Tabby
* [noctis](https://github.com/aaronhuggins/tabby-colors-noctis) - color themes inspired by Noctis VS Code theme

# Sponsors <!-- omit in toc -->

<a href="https://packagecloud.io"><img src="https://assets-production.packagecloud.io/assets/logo_v1-d5895e7b89b2dee19030e85515fd0f91d8f3b37c82d218a6531fc89c2b1b613c.png" width="200"></a>

[**packagecloud**](https://packagecloud.io) has provided free Debian/RPM repository hosting

[![](https://user-images.githubusercontent.com/161476/200423885-7aba2202-fea7-4409-95b9-3a062ce902c7.png)](https://keygen.sh/?via=eugene)

[**keygen**](https://keygen.sh/?via=eugene) has provided free release & auto-update hosting

<a href="https://iqhive.com/"><img src="https://iqhive.com/img/icons/logo.svg" width="200"></a>

[**IQ Hive**](https://iqhive.com) is providing financial support for the project development


<a name="contributing"></a>
# Contributing

Pull requests and plugins are welcome!

See [HACKING.md](https://github.com/Eugeny/tabby/blob/master/HACKING.md) and [API docs](https://docs.tabby.sh/) for information of how the project is laid out, and a very brief plugin development tutorial.

---
<a name="contributors"></a>

Thanks goes to these wonderful people ([emoji key](https://allcontributors.org/docs/en/emoji-key)):

<!-- ALL-CONTRIBUTORS-LIST:START - Do not remove or modify this section -->
<!-- prettier-ignore-start -->
<!-- markdownlint-disable -->
<table>
  <tbody>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="http://www.russellmyers.com"><img src="https://avatars2.githubusercontent.com/u/184085?v=4?s=100" width="100px;" alt="Russell Myers"/><br /><sub><b>Russell Myers</b></sub></a><br /><a href="https://github.com/Eugeny/tabby/commits?author=mezner" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="http://www.morwire.com"><img src="https://avatars1.githubusercontent.com/u/3991658?v=4?s=100" width="100px;" alt="Austin Warren"/><br /><sub><b>Austin Warren</b></sub></a><br /><a href="https://github.com/Eugeny/tabby/commits?author=ehwarren" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/Drachenkaetzchen"><img src="https://avatars1.githubusercontent.com/u/162974?v=4?s=100" width="100px;" alt="Felicia Hummel"/><br /><sub><b>Felicia Hummel</b></sub></a><br /><a href="https://github.com/Eugeny/tabby/commits?author=Drachenkaetzchen" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/mikemaccana"><img src="https://avatars2.githubusercontent.com/u/172594?v=4?s=100" width="100px;" alt="Mike MacCana"/><br /><sub><b>Mike MacCana</b></sub></a><br /><a href="https://github.com/Eugeny/tabby/commits?author=mikemaccana" title="Tests">⚠️</a> <a href="#design-mikemaccana" title="Design">🎨</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/yxuko"><img src="https://avatars1.githubusercontent.com/u/1786317?v=4?s=100" width="100px;" alt="Yacine Kanzari"/><br /><sub><b>Yacine Kanzari</b></sub></a><br /><a href="https://github.com/Eugeny/tabby/commits?author=yxuko" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/BBJip"><img src="https://avatars2.githubusercontent.com/u/32908927?v=4?s=100" width="100px;" alt="BBJip"/><br /><sub><b>BBJip</b></sub></a><br /><a href="https://github.com/Eugeny/tabby/commits?author=BBJip" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/Futagirl"><img src="https://avatars2.githubusercontent.com/u/33533958?v=4?s=100" width="100px;" alt="Futagirl"/><br /><sub><b>Futagirl</b></sub></a><br /><a href="#design-Futagirl" title="Design">🎨</a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="https://www.levrik.io"><img src="https://avatars3.githubusercontent.com/u/9491603?v=4?s=100" width="100px;" alt="Levin Rickert"/><br /><sub><b>Levin Rickert</b></sub></a><br /><a href="https://github.com/Eugeny/tabby/commits?author=levrik" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://kwonoj.github.io"><img src="https://avatars2.githubusercontent.com/u/1210596?v=4?s=100" width="100px;" alt="OJ Kwon"/><br /><sub><b>OJ Kwon</b></sub></a><br /><a href="https://github.com/Eugeny/tabby/commits?author=kwonoj" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/Domain"><img src="https://avatars2.githubusercontent.com/u/903197?v=4?s=100" width="100px;" alt="domain"/><br /><sub><b>domain</b></sub></a><br /><a href="#plugin-Domain" title="Plugin/utility libraries">🔌</a> <a href="https://github.com/Eugeny/tabby/commits?author=Domain" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="http://www.jbrumond.me"><img src="https://avatars1.githubusercontent.com/u/195127?v=4?s=100" width="100px;" alt="James Brumond"/><br /><sub><b>James Brumond</b></sub></a><br /><a href="#plugin-kbjr" title="Plugin/utility libraries">🔌</a></td>
      <td align="center" valign="top" width="14.28%"><a href="http://www.growingwiththeweb.com"><img src="https://avatars0.githubusercontent.com/u/2193314?v=4?s=100" width="100px;" alt="Daniel Imms"/><br /><sub><b>Daniel Imms</b></sub></a><br /><a href="https://github.com/Eugeny/tabby/commits?author=Tyriar" title="Code">💻</a> <a href="#plugin-Tyriar" title="Plugin/utility libraries">🔌</a> <a href="https://github.com/Eugeny/tabby/commits?author=Tyriar" title="Tests">⚠️</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/baflo"><img src="https://avatars2.githubusercontent.com/u/834350?v=4?s=100" width="100px;" alt="Florian Bachmann"/><br /><sub><b>Florian Bachmann</b></sub></a><br /><a href="https://github.com/Eugeny/tabby/commits?author=baflo" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="http://michael-kuehnel.de"><img src="https://avatars2.githubusercontent.com/u/441011?v=4?s=100" width="100px;" alt="Michael Kühnel"/><br /><sub><b>Michael Kühnel</b></sub></a><br /><a href="https://github.com/Eugeny/tabby/commits?author=mischah" title="Code">💻</a> <a href="#design-mischah" title="Design">🎨</a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/NieLeben"><img src="https://avatars3.githubusercontent.com/u/47182955?v=4?s=100" width="100px;" alt="Tilmann Meyer"/><br /><sub><b>Tilmann Meyer</b></sub></a><br /><a href="https://github.com/Eugeny/tabby/commits?author=NieLeben" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="http://www.jubeat.net"><img src="https://avatars3.githubusercontent.com/u/11289158?v=4?s=100" width="100px;" alt="PM Extra"/><br /><sub><b>PM Extra</b></sub></a><br /><a href="https://github.com/Eugeny/tabby/issues?q=author%3APMExtra" title="Bug reports">🐛</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://jjuhas.keybase.pub//"><img src="https://avatars1.githubusercontent.com/u/6438760?v=4?s=100" width="100px;" alt="Jonathan"/><br /><sub><b>Jonathan</b></sub></a><br /><a href="https://github.com/Eugeny/tabby/commits?author=IgnusG" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://hans-koch.me"><img src="https://avatars0.githubusercontent.com/u/1093709?v=4?s=100" width="100px;" alt="Hans Koch"/><br /><sub><b>Hans Koch</b></sub></a><br /><a href="https://github.com/Eugeny/tabby/commits?author=hammster" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="http://thepuzzlemaker.info"><img src="https://avatars3.githubusercontent.com/u/12666617?v=4?s=100" width="100px;" alt="Dak Smyth"/><br /><sub><b>Dak Smyth</b></sub></a><br /><a href="https://github.com/Eugeny/tabby/commits?author=ThePuzzlemaker" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="http://yfwz100.github.io"><img src="https://avatars2.githubusercontent.com/u/983211?v=4?s=100" width="100px;" alt="Wang Zhi"/><br /><sub><b>Wang Zhi</b></sub></a><br /><a href="https://github.com/Eugeny/tabby/commits?author=yfwz100" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/jack1142"><img src="https://avatars0.githubusercontent.com/u/6032823?v=4?s=100" width="100px;" alt="jack1142"/><br /><sub><b>jack1142</b></sub></a><br /><a href="https://github.com/Eugeny/tabby/commits?author=jack1142" title="Code">💻</a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/hdougie"><img src="https://avatars1.githubusercontent.com/u/450799?v=4?s=100" width="100px;" alt="Howie Douglas"/><br /><sub><b>Howie Douglas</b></sub></a><br /><a href="https://github.com/Eugeny/tabby/commits?author=hdougie" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://chriskaczor.com"><img src="https://avatars2.githubusercontent.com/u/180906?v=4?s=100" width="100px;" alt="Chris Kaczor"/><br /><sub><b>Chris Kaczor</b></sub></a><br /><a href="https://github.com/Eugeny/tabby/commits?author=ckaczor" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://www.boxmein.net"><img src="https://avatars1.githubusercontent.com/u/358714?v=4?s=100" width="100px;" alt="Johannes Kadak"/><br /><sub><b>Johannes Kadak</b></sub></a><br /><a href="https://github.com/Eugeny/tabby/commits?author=boxmein" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/LeSeulArtichaut"><img src="https://avatars1.githubusercontent.com/u/38361244?v=4?s=100" width="100px;" alt="LeSeulArtichaut"/><br /><sub><b>LeSeulArtichaut</b></sub></a><br /><a href="https://github.com/Eugeny/tabby/commits?author=LeSeulArtichaut" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/CyrilTaylor"><img src="https://avatars0.githubusercontent.com/u/12631466?v=4?s=100" width="100px;" alt="Cyril Taylor"/><br /><sub><b>Cyril Taylor</b></sub></a><br /><a href="https://github.com/Eugeny/tabby/commits?author=CyrilTaylor" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/nstefanou"><img src="https://avatars3.githubusercontent.com/u/51129173?v=4?s=100" width="100px;" alt="nstefanou"/><br /><sub><b>nstefanou</b></sub></a><br /><a href="https://github.com/Eugeny/tabby/commits?author=nstefanou" title="Code">💻</a> <a href="#plugin-nstefanou" title="Plugin/utility libraries">🔌</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/orin220444"><img src="https://avatars3.githubusercontent.com/u/30747229?v=4?s=100" width="100px;" alt="orin220444"/><br /><sub><b>orin220444</b></sub></a><br /><a href="https://github.com/Eugeny/tabby/commits?author=orin220444" title="Code">💻</a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/Goobles"><img src="https://avatars3.githubusercontent.com/u/8776771?v=4?s=100" width="100px;" alt="Gobius Dolhain"/><br /><sub><b>Gobius Dolhain</b></sub></a><br /><a href="https://github.com/Eugeny/tabby/commits?author=Goobles" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/3l0w"><img src="https://avatars2.githubusercontent.com/u/37798980?v=4?s=100" width="100px;" alt="Gwilherm Folliot"/><br /><sub><b>Gwilherm Folliot</b></sub></a><br /><a href="https://github.com/Eugeny/tabby/commits?author=3l0w" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/Dimitory"><img src="https://avatars0.githubusercontent.com/u/475955?v=4?s=100" width="100px;" alt="Dmitry Pronin"/><br /><sub><b>Dmitry Pronin</b></sub></a><br /><a href="https://github.com/Eugeny/tabby/commits?author=dimitory" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/JonathanBeverley"><img src="https://avatars1.githubusercontent.com/u/20328966?v=4?s=100" width="100px;" alt="Jonathan Beverley"/><br /><sub><b>Jonathan Beverley</b></sub></a><b
