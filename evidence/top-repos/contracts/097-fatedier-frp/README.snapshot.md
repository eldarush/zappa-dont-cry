# frp

[![Build Status](https://circleci.com/gh/fatedier/frp.svg?style=shield)](https://circleci.com/gh/fatedier/frp)
[![GitHub release](https://img.shields.io/github/tag/fatedier/frp.svg?label=release)](https://github.com/fatedier/frp/releases)
[![Go Report Card](https://goreportcard.com/badge/github.com/fatedier/frp)](https://goreportcard.com/report/github.com/fatedier/frp)
[![GitHub Releases Stats](https://img.shields.io/github/downloads/fatedier/frp/total.svg?logo=github)](https://somsubhra.github.io/github-release-stats/?username=fatedier&repository=frp)

[README](README.md) | [中文文档](README_zh.md)

## Sponsors

frp is an open source project with its ongoing development made possible entirely by the support of our awesome sponsors. If you'd like to join them, please consider [sponsoring frp's development](https://github.com/sponsors/fatedier).

<h3 align="center">Gold Sponsors</h3>
<!--gold sponsors start-->
<p align="center">
  <a href="https://jb.gg/frp" target="_blank">
    <img width="420px" src="https://raw.githubusercontent.com/fatedier/frp/dev/doc/pic/sponsor_jetbrains.jpg">
	<br>
	<b>The complete IDE crafted for professional Go developers</b>
  </a>
</p>

<p align="center">
  <a href="https://github.com/beclab/Olares" target="_blank">
    <img width="420px" src="https://raw.githubusercontent.com/fatedier/frp/dev/doc/pic/sponsor_olares.jpeg">
	<br>
	<b>The sovereign cloud that puts you in control</b>
	<br>
	<sub>An open source, self-hosted alternative to public clouds, built for data ownership and privacy</sub>
  </a>
</p>

<div align="center">

## Recall.ai - API for meeting recordings

If you're looking for a meeting recording API, consider checking out [Recall.ai](https://www.recall.ai/?utm_source=github&utm_medium=sponsorship&utm_campaign=fatedier-frp),

an API that records Zoom, Google Meet, Microsoft Teams, in-person meetings, and more.

</div>
<!--gold sponsors end-->

## What is frp?

frp is a fast reverse proxy that allows you to expose a local server located behind a NAT or firewall to the Internet. It currently supports **TCP** and **UDP**, as well as **HTTP** and **HTTPS** protocols, enabling requests to be forwarded to internal services via domain name.

frp also offers a P2P connect mode.

## Table of Contents

<!-- vim-markdown-toc GFM -->

* [Development Status](#development-status)
    * [About V2](#about-v2)
* [Architecture](#architecture)
* [Example Usage](#example-usage)
    * [Access your computer in a LAN network via SSH](#access-your-computer-in-a-lan-network-via-ssh)
    * [Multiple SSH services sharing the same port](#multiple-ssh-services-sharing-the-same-port)
    * [Accessing Internal Web Services with Custom Domains in LAN](#accessing-internal-web-services-with-custom-domains-in-lan)
    * [Forward DNS query requests](#forward-dns-query-requests)
    * [Forward Unix Domain Socket](#forward-unix-domain-socket)
    * [Expose a simple HTTP file server](#expose-a-simple-http-file-server)
    * [Enable HTTPS for a local HTTP(S) service](#enable-https-for-a-local-https-service)
    * [Expose your service privately](#expose-your-service-privately)
    * [P2P Mode](#p2p-mode)
* [Features](#features)
    * [Configuration Files](#configuration-files)
    * [Using Environment Variables](#using-environment-variables)
    * [Split Configures Into Different Files](#split-configures-into-different-files)
    * [Server Dashboard](#server-dashboard)
    * [Client Admin UI](#client-admin-ui)
        * [Dynamic Proxy Management (Store)](#dynamic-proxy-management-store)
    * [Monitor](#monitor)
        * [Prometheus](#prometheus)
    * [Authenticating the Client](#authenticating-the-client)
        * [Token Authentication](#token-authentication)
        * [OIDC Authentication](#oidc-authentication)
    * [Encryption and Compression](#encryption-and-compression)
        * [TLS](#tls)
    * [Hot-Reloading frpc configuration](#hot-reloading-frpc-configuration)
    * [Get proxy status from client](#get-proxy-status-from-client)
    * [Only allowing certain ports on the server](#only-allowing-certain-ports-on-the-server)
    * [Port Reuse](#port-reuse)
    * [Bandwidth Limit](#bandwidth-limit)
        * [For Each Proxy](#for-each-proxy)
    * [TCP Stream Multiplexing](#tcp-stream-multiplexing)
    * [Support KCP Protocol](#support-kcp-protocol)
    * [Support QUIC Protocol](#support-quic-protocol)
    * [Connection Pooling](#connection-pooling)
    * [Load balancing](#load-balancing)
    * [Service Health Check](#service-health-check)
    * [Rewriting the HTTP Host Header](#rewriting-the-http-host-header)
    * [Setting other HTTP Headers](#setting-other-http-headers)
    * [Get Real IP](#get-real-ip)
        * [HTTP X-Forwarded-For](#http-x-forwarded-for)
        * [Proxy Protocol](#proxy-protocol)
    * [Require HTTP Basic Auth (Password) for Web Services](#require-http-basic-auth-password-for-web-services)
    * [Custom Subdomain Names](#custom-subdomain-names)
    * [URL Routing](#url-routing)
    * [TCP Port Multiplexing](#tcp-port-multiplexing)
    * [Connecting to frps via PROXY](#connecting-to-frps-via-proxy)
    * [Port range mapping](#port-range-mapping)
    * [Client Plugins](#client-plugins)
    * [Server Manage Plugins](#server-manage-plugins)
    * [SSH Tunnel Gateway](#ssh-tunnel-gateway)
    * [Virtual Network (VirtualNet)](#virtual-network-virtualnet)
* [Feature Gates](#feature-gates)
    * [Available Feature Gates](#available-feature-gates)
    * [Enabling Feature Gates](#enabling-feature-gates)
    * [Feature Lifecycle](#feature-lifecycle)
* [Related Projects](#related-projects)
* [Contributing](#contributing)
* [Donation](#donation)
    * [GitHub Sponsors](#github-sponsors)
    * [PayPal](#paypal)

<!-- vim-markdown-toc -->

## Development Status

frp is currently under development. You can try the latest release version in the `master` branch, or use the `dev` branch to access the version currently in development.

We are currently working on version 2 and attempting to perform some code refactoring and improvements. However, please note that it will not be compatible with version 1.

We will transition from version 0 to version 1 at the appropriate time and will only accept bug fixes and improvements, rather than big feature requests.

### About V2

The complexity and difficulty of the v2 version are much higher than anticipated. I can only work on its development during fragmented time periods, and the constant interruptions disrupt productivity significantly. Given this situation, we will continue to optimize and iterate on the current version until we have more free time to proceed with the major version overhaul.

The concept behind v2 is based on my years of experience and reflection in the cloud-native domain, particularly in K8s and ServiceMesh. Its core is a modernized four-layer and seven-layer proxy, similar to envoy. This proxy itself is highly scalable, not only capable of implementing the functionality of intranet penetration but also applicable to various other domains. Building upon this highly scalable core, we aim to implement all the capabilities of frp v1 while also addressing the functionalities that were previously unachievable or difficult to implement in an elegant manner. Furthermore, we will maintain efficient development and iteration capabilities.

In addition, I envision frp itself becoming a highly extensible system and platform, similar to how we can provide a range of extension capabilities based on K8s. In K8s, we can customize development according to enterprise needs, utilizing features such as CRD, controller mode, webhook, CSI, and CNI. In frp v1, we introduced the concept of server plugins, which implemented some basic extensibility. However, it relies on a simple HTTP protocol and requires users to start independent processes and manage them on their own. This approach is far from flexible and convenient, and real-world demands vary greatly. It is unrealistic to expect a non-profit open-source project maintained by a few individuals to meet everyone's needs.

Finally, we acknowledge that the current design of modules such as configuration management, permission verification, certificate management, and API management is not modern enough. While we may carry out some optimizations in the v1 version, ensuring compatibility remains a challenging issue that requires a considerable amount of effort to address.

We sincerely appreciate your support for frp.

## Architecture

<p align="center">
  <img src="/doc/pic/architecture.jpg" alt="architecture" width="760">
</p>

## Example Usage

To begin, download the latest program for your operating system and architecture from the [Release](https://github.com/fatedier/frp/releases) page.

Next, place the `frps` binary and server configuration file on Server A, which has a public IP address.

Finally, place the `frpc` binary and client configuration file on Server B, which is located on a LAN that cannot be directly accessed from the public internet.

Some antiviruses improperly mark frpc as malware and delete it. This is due to frp being a networking tool capable of creating reverse proxies. Antiviruses sometimes flag reverse proxies due to their ability to bypass firewall port restrictions. If you are using antivirus, then you may need to whitelist/exclude frpc in your antivirus settings to avoid accidental quarantine/deletion. See [issue 3637](https://github.com/fatedier/frp/issues/3637) for more details.

### Access your computer in a LAN network via SSH

1. Modify `frps.toml` on server A by setting the `bindPort` for frp clients to connect to:

  ```toml
  # frps.toml
  bindPort = 7000
  ```

2. Start `frps` on server A:

  `./frps -c ./frps.toml`

3. Modify `frpc.toml` on server B and set the `serverAddr` field to the public IP address of your frps server:

  ```toml
  # frpc.toml
  serverAddr = "x.x.x.x"
  serverPort = 7000

  [[proxies]]
  name = "ssh"
  type = "tcp"
  localIP = "127.0.0.1"
  localPort = 22
  remotePort = 6000
  ```

Note that the `localPort` (listened on the client) and `remotePort` (exposed on the server) are used for traffic going in and out of the frp system, while the `serverPort` is used for communication between frps and frpc.

4. Start `frpc` on server B:

  `./frpc -c ./frpc.toml`

5. To access server B from another machine through server A via SSH (assuming the username is `test`), use the following command:

  `ssh -oPort=6000 test@x.x.x.x`

### Multiple SSH services sharing the same port

This example implements multiple SSH services exposed through the same port using a proxy of type tcpmux. Similarly, as long as the client supports the HTTP Connect proxy connection method, port reuse can be achieved in this way.

1. Deploy frps on a machine with a public IP and modify the frps.toml file. Here is a simplified configuration:

  ```toml
  bindPort = 7000
  tcpmuxHTTPConnectPort = 5002
  ```

2. Deploy frpc on the internal machine A with the following configuration:

  ```toml
  serverAddr = "x.x.x.x"
  serverPort = 7000

  [[proxies]]
  name = "ssh1"
  type = "tcpmux"
  multiplexer = "httpconnect"
  customDomains = ["machine-a.example.com"]
  localIP = "127.0.0.1"
  localPort = 22
  ```

3. Deploy another frpc on the internal machine B with the following configuration:

  ```toml
  serverAddr = "x.x.x.x"
  serverPort = 7000

  [[proxies]]
  name = "ssh2"
  type = "tcpmux"
  multiplexer = "httpconnect"
  customDomains = ["machine-b.example.com"]
  localIP = "127.0.0.1"
  localPort = 22
  ```

4. To access internal machine A using SSH ProxyCommand, assuming the username is "test":

  `ssh -o 'proxycommand socat - PROXY:x.x.x.x:%h:%p,proxyport=5002' test@machine-a.example.com`

5. To access internal machine B, the only difference is the domain name, assuming the username is "test":

  `ssh -o 'proxycommand socat - PROXY:x.x.x.x:%h:%p,proxyport=5002' test@machine-b.example.com`

### Accessing Internal Web Services with Custom Domains in LAN

Sometimes we need to expose a local web service behind a NAT network to others for testing purposes with our own domain name.

Unfortunately, we cannot resolve a domain name to a local IP. However, we can use frp to expose an HTTP(S) service.

1. Modify `frps.toml` and set the HTTP port for vhost to 8080:

  ```toml
  # frps.toml
  bindPort = 7000
  vhostHTTPPort = 8080
  ```

  If you want to configure an https proxy, you need to set up the `vhostHTTPSPort`.

2. Start `frps`:

  `./frps -c ./frps.toml`

3. Modify `frpc.toml` and set `serverAddr` to the IP address of the remote frps server. Specify the `localPort` of your web service:

  ```toml
  # frpc.toml
  serverAddr = "x.x.x.x"
  serverPort = 7000

  [[proxies]]
  name = "web"
  type = "http"
  localPort = 80
  customDomains = ["www.example.com"]
  ```

4. Start `frpc`:

  `./frpc -c ./frpc.toml`

5. Map the A record of `www.example.com` to either the public IP of the remote frps server or a CNAME record pointing to your original domain.

6. Visit your local web service using url `http://www.example.com:8080`.

### Forward DNS query requests

1. Modify `frps.toml`:

  ```toml
  # frps.toml
  bindPort = 7000
  ```

2. Start `frps`:

  `./frps -c ./frps.toml`

3. Modify `frpc.toml` and set `serverAddr` to the IP address of the remote frps server. Forward DNS query requests to the Google Public DNS server `8.8.8.8:53`:

  ```toml
  # frpc.toml
  serverAddr = "x.x.x.x"
  serverPort = 7000

  [[proxies]]
  name = "dns"
  type = "udp"
  localIP = "8.8.8.8"
  localPort = 53
  remotePort = 6000
  ```

4. Start frpc:

  `./frpc -c ./frpc.toml`

5. Test DNS resolution using the `dig` command:

  `dig @x.x.x.x -p 6000 www.google.com`

### Forward Unix Domain Socket

Expose a Unix domain socket (e.g. the Docker daemon socket) as TCP.

Configure `frps` as above.

1. Start `frpc` with the following configuration:

  ```toml
  # frpc.toml
  serverAddr = "x.x.x.x"
  serverPort = 7000

  [[proxies]]
  name = "unix_domain_socket"
  type = "tcp"
  remotePort = 6000
  [proxies.plugin]
  type = "unix_domain_socket"
  unixPath = "/var/run/docker.sock"
  ```

2. Test the configuration by getting the docker version using `curl`:

  `curl http://x.x.x.x:6000/version`

### Expose a simple HTTP file server

Expose a simple HTTP file server to access files stored in the LAN from the public Internet.

Configure `frps` as described above, then:

1. Start `frpc` with the following configuration:

  ```toml
  # frpc.toml
  serverAddr = "x.x.x.x"
  serverPort = 7000

  [[proxies]]
  name = "test_static_file"
  type = "tcp"
  remotePort = 6000
  [proxies.plugin]
  type = "static_file"
  localPath = "/tmp/files"
  stripPrefix = "static"
  httpUser = "abc"
  httpPassword = "abc"
  ```

2. Visit `http://x.x.x.x:6000/static/` from your browser and specify correct username and password to view files in `/tmp/files` on the `frpc` machine.

### Enable HTTPS for a local HTTP(S) service

You may substitute `https2https` for the plugin, and point the `localAddr` to a HTTPS endpoint.

1. Start `frpc` with the following configuration:

  ```toml
  # frpc.toml
  serverAddr = "x.x.x.x"
  serverPort = 7000

  [[proxies]]
  name = "test_https2http"
  type = "https"
  customDomains = ["test.example.com"]

  [proxies.plugin]
  type = "https2http"
  localAddr = "127.0.0.1:80"
  crtPath = "./server.crt"
  keyPath = "./server.key"
  hostHeaderRewrite = "127.0.0.1"
  requestHeaders.set.x-from-where = "frp"
  ```

2. Visit `https://test.example.com`.

### Expose your service privately

To mitigate risks associated with exposing certain services directly to the public network, STCP (Secret TCP) mode requires a preshared key to be used for access to the service from other clients.

Configure `frps` same as above.

1. Start `frpc` on machine B with the following config. This example is for exposing the SSH service (port 22), and note the `secretKey` field for the preshared key, and that the `remotePort` field is removed here:

  ```toml
  # frpc.toml
  serverAddr = "x.x.x.x"
  serverPort = 7000

  [[proxies]]
  name = "secret_ssh"
  type = "stcp"
  secretKey = "abcdefg"
  localIP = "127.0.0.1"
  localPort = 22
  ```

2. Start another `frpc` (typically on another machine C) with the following config to access the SSH service with a security key (`secretKey` field):

  ```toml
  # frpc.toml
  serverAddr = "x.x.x.x"
  serverPort = 7000

  [[visitors]]
  name = "secret_ssh_visitor"
  type = "stcp"
  serverName = "secret_ssh"
  secretKey = "abcdefg"
  bindAddr = "127.0.0.1"
  bindPort = 6000
  ```

3. On machine C, connect to SSH on machine B, using this command:

  `ssh -oPort=6000 127.0.0.1`

### P2P Mode

**xtcp** is designed to transmit large amounts of data directly between clients. A frps server is still needed, as P2P here only refers to the actual data transmission.

Note that it may not work with all types of NAT devices. You might want to fallback to stcp if xtcp doesn't work.

1. Start `frpc` on machine B, and expose the SSH port. Note that the `remotePort` field is removed:

  ```toml
  # frpc.toml
  serverAddr = "x.x.x.x"
  serverPort = 7000
  # set up a new stun server if the default one is not available.
  # natHoleStunServer = "xxx"

  [[proxies]]
  name = "p2p_ssh"
  type = "xtcp"
  secretKey = "abcdefg"
  localIP = "127.0.0.1"
  localPort = 22
  ```

2. Start another `frpc` (typically on another machine C) with the configuration to connect to SSH using P2P mode:

  ```toml
  # frpc.toml
  serverAddr = "x.x.x.x"
  serverPort = 7000
  # set up a new stun server if the default one is not available.
  # natHoleStunServer = "xxx"

  [[visitors]]
  name = "p2p_ssh_visitor"
  type = "xtcp"
  serverName = "p2p_ssh"
  secretKey = "abcdefg"
  bindAddr = "127.0.0.1"
  bindPort = 6000
  # when automatic tunnel persistence is required, set it to true
  keepTunnelOpen = false
  ```

3. On machine C, connect to SSH on machine B, using this command:

  `ssh -oPort=6000 127.0.0.1`

## Features

### Configuration Files

Since v0.52.0, we support TOML, YAML, and JSON for configuration. Please note that INI is deprecated and will be removed in future releases. New features will only be available in TOML, YAML, or JSON. Users wanting these new features should switch their configuration format accordingly.

Read the full example configuration files to find out even more features not described here.

Examples use TOML format, but you can still use YAML or JSON.

These configuration files is for reference only. Please do not use this configuration directly to run the program as it may have various issues.

[Full configuration file for frps (Server)](./conf/frps_full_example.toml)

[Full configuration file for frpc (Client)](./conf/frpc_full_example.toml)

### Using Environment Variables

Environment variables can be referenced in the configuration file, using Go's standard format:

```toml
# frpc.toml
serverAddr = "{{ .Envs.FRP_SERVER_ADDR }}"
serverPort = 7000

[[proxies]]
name = "ssh"
type = "tcp"
localIP = "127.0.0.1"
localPort = 22
remotePort = {{ .Envs.FRP_SSH_REMOTE_PORT }}
```

With the config above, variables can be passed into `frpc` program like this:

```
export FRP_SERVER_ADDR=x.x.x.x
export FRP_SSH_REMOTE_PORT=6000
./frpc -c ./frpc.toml
```

`frpc` will render configuration file template using OS environment variables. Remember to prefix your reference with `.Envs`.

### Split Configures Into Different Files


