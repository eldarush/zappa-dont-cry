# Awesome Go

<a href="https://awesome-go.com/"><img align="right" src="https://github.com/avelino/awesome-go/raw/main/tmpl/assets/logo.png" alt="awesome-go" title="awesome-go" /></a>

[![Build Status](https://github.com/avelino/awesome-go/actions/workflows/tests.yaml/badge.svg?branch=main)](https://github.com/avelino/awesome-go/actions/workflows/tests.yaml?query=branch%3Amain)
[![Awesome](https://cdn.rawgit.com/sindresorhus/awesome/d7305f38d29fed78fa85652e3a63e154dd8e8829/media/badge.svg)](https://github.com/sindresorhus/awesome)
[![Slack Widget](https://img.shields.io/badge/join-us%20on%20slack-gray.svg?longCache=true&logo=slack&colorB=red)](https://gophers.slack.com/messages/awesome)
[![Netlify Status](https://api.netlify.com/api/v1/badges/83a6dcbe-0da6-433e-b586-f68109286bd5/deploy-status)](https://app.netlify.com/sites/awesome-go/deploys)
[![Track Awesome List](https://www.trackawesomelist.com/badge.svg)](https://www.trackawesomelist.com/avelino/awesome-go/)
[![Last Commit](https://img.shields.io/github/last-commit/avelino/awesome-go)](https://github.com/avelino/awesome-go/commits/main)

We use the _[Golang Bridge](https://github.com/gobridge/about-us/blob/master/README.md)_ community Slack for instant communication, follow the [form here to join](https://invite.slack.golangbridge.org/).

<a href="https://www.producthunt.com/posts/awesome-go?utm_source=badge-featured&utm_medium=badge&utm_souce=badge-awesome-go" target="_blank"><img src="https://api.producthunt.com/widgets/embed-image/v1/featured.svg?post_id=291535&theme=light" alt="awesome-go - Curated list awesome Go frameworks, libraries and software | Product Hunt" style="width: 250px; height: 54px;" width="250" height="54" /></a>

**Sponsorships:**

_Special thanks to_

<div align="center">
<table cellpadding="5">
<tbody align="center">
<tr>
<td colspan="2">
<a href="https://bit.ly/awesome-go-digitalocean">
<img src="https://avelino.run/sponsors/do_logo_horizontal_blue-210.png" width="200" alt="Digital Ocean">
</a>
</td>
</tr>
</tbody>
</table>
</div>

**Awesome Go has no monthly fee**_, but we have employees who **work hard** to keep it running. With money raised, we can repay the effort of each person involved! You can see how we calculate our billing and distribution as it is open to the entire community. Want to be a supporter of the project click [here](mailto:avelinorun+oss@gmail.com?subject=awesome-go%3A%20project%20support)._

> A curated list of awesome Go frameworks, libraries, and software. Inspired by [awesome-python](https://github.com/vinta/awesome-python).

**Contributing:**

Please take a quick gander at the [contribution guidelines](https://github.com/avelino/awesome-go/blob/main/CONTRIBUTING.md) first. Thanks to all [contributors](https://github.com/avelino/awesome-go/graphs/contributors); you rock!

> _If you see a package or project here that is no longer maintained or is not a good fit, please submit a pull request to improve this file. Thank you!_

## Contents

<details>
<summary>Expand contents</summary>

- [Awesome Go](#awesome-go)
  - [Contents](#contents)
  - [Actor Model](#actor-model)
  - [Artificial Intelligence](#artificial-intelligence)
  - [Audio and Music](#audio-and-music)
  - [Authentication and Authorization](#authentication-and-authorization)
  - [Blockchain](#blockchain)
  - [Bot Building](#bot-building)
  - [Build Automation](#build-automation)
  - [Command Line](#command-line)
    - [Advanced Console UIs](#advanced-console-uis)
    - [Standard CLI](#standard-cli)
  - [Configuration](#configuration)
  - [Continuous Integration](#continuous-integration)
  - [CSS Preprocessors](#css-preprocessors)
  - [Data Integration Frameworks](#data-integration-frameworks)
  - [Data Structures and Algorithms](#data-structures-and-algorithms)
    - [Bit-packing and Compression](#bit-packing-and-compression)
    - [Bit Sets](#bit-sets)
    - [Bloom and Cuckoo Filters](#bloom-and-cuckoo-filters)
    - [Data Structure and Algorithm Collections](#data-structure-and-algorithm-collections)
    - [Iterators](#iterators)
    - [Maps](#maps)
    - [Miscellaneous Data Structures and Algorithms](#miscellaneous-data-structures-and-algorithms)
    - [Nullable Types](#nullable-types)
    - [Queues](#queues)
    - [Sets](#sets)
    - [Text Analysis](#text-analysis)
    - [Trees](#trees)
    - [Pipes](#pipes)
  - [Database](#database)
    - [Caches](#caches)
    - [Databases Implemented in Go](#databases-implemented-in-go)
    - [Database Schema Migration](#database-schema-migration)
    - [Database Tools](#database-tools)
    - [SQL Query Builders](#sql-query-builders)
  - [Database Drivers](#database-drivers)
    - [Interfaces to Multiple Backends](#interfaces-to-multiple-backends)
    - [Relational Database Drivers](#relational-database-drivers)
    - [NoSQL Database Drivers](#nosql-database-drivers)
    - [Search and Analytic Databases](#search-and-analytic-databases)
  - [Date and Time](#date-and-time)
  - [Distributed Systems](#distributed-systems)
  - [Dynamic DNS](#dynamic-dns)
  - [Email](#email)
  - [Embeddable Scripting Languages](#embeddable-scripting-languages)
  - [Error Handling](#error-handling)
  - [File Handling](#file-handling)
  - [Financial](#financial)
  - [Forms](#forms)
  - [Functional](#functional)
  - [Game Development](#game-development)
  - [Generators](#generators)
  - [Geographic](#geographic)
  - [Go Compilers](#go-compilers)
  - [Goroutines](#goroutines)
  - [GUI](#gui)
  - [Hardware](#hardware)
  - [Images](#images)
  - [IoT (Internet of Things)](#iot-internet-of-things)
  - [Job Scheduler](#job-scheduler)
  - [JSON](#json)
  - [Logging](#logging)
  - [Machine Learning](#machine-learning)
  - [Messaging](#messaging)
  - [Microsoft Office](#microsoft-office)
    - [Microsoft Excel](#microsoft-excel)
    - [Microsoft Word](#microsoft-word)
  - [Miscellaneous](#miscellaneous)
    - [Dependency Injection](#dependency-injection)
    - [Project Layout](#project-layout)
    - [Strings](#strings)
    - [Uncategorized](#uncategorized)
  - [Natural Language Processing](#natural-language-processing)
    - [Language Detection](#language-detection)
    - [Morphological Analyzers](#morphological-analyzers)
    - [Slugifiers](#slugifiers)
    - [Tokenizers](#tokenizers)
    - [Translation](#translation)
    - [Transliteration](#transliteration)
  - [Networking](#networking)
    - [HTTP Clients](#http-clients)
  - [OpenGL](#opengl)
  - [ORM](#orm)
  - [Package Management](#package-management)
  - [Performance](#performance)
  - [Query Language](#query-language)
  - [Reflection](#reflection)
  - [Resource Embedding](#resource-embedding)
  - [Science and Data Analysis](#science-and-data-analysis)
  - [Security](#security)
  - [Serialization](#serialization)
  - [Server Applications](#server-applications)
  - [Stream Processing](#stream-processing)
  - [Template Engines](#template-engines)
  - [Testing](#testing)
    - [Testing Frameworks](#testing-frameworks)
    - [Mock](#mock)
    - [Fuzzing and delta-debugging/reducing/shrinking](#fuzzing-and-delta-debuggingreducingshrinking)
    - [Selenium and browser control tools](#selenium-and-browser-control-tools)
    - [Fail injection](#fail-injection)
  - [Text Processing](#text-processing)
    - [Formatters](#formatters)
    - [Markup Languages](#markup-languages)
    - [Parsers/Encoders/Decoders](#parsersencodersdecoders)
    - [Regular Expressions](#regular-expressions)
    - [Sanitation](#sanitation)
    - [Scrapers](#scrapers)
    - [RSS](#rss)
    - [Utility/Miscellaneous](#utilitymiscellaneous)
  - [Third-party APIs](#third-party-apis)
  - [Utilities](#utilities)
  - [UUID](#uuid)
  - [Validation](#validation)
  - [Version Control](#version-control)
  - [Video](#video)
  - [Web Frameworks](#web-frameworks)
    - [Middlewares](#middlewares)
      - [Actual middlewares](#actual-middlewares)
      - [Libraries for creating HTTP middlewares](#libraries-for-creating-http-middlewares)
    - [Routers](#routers)
  - [WebAssembly](#webassembly)
  - [Webhooks Server](#webhooks-server)
  - [Windows](#windows)
  - [Workflow Frameworks](#workflow-frameworks)
  - [XML](#xml)
  - [Zero Trust](#zero-trust)
  - [Code Analysis](#code-analysis)
  - [Editor Plugins](#editor-plugins)
  - [Go Generate Tools](#go-generate-tools)
  - [Go Tools](#go-tools)
  - [Software Packages](#software-packages)
    - [DevOps Tools](#devops-tools)
    - [Other Software](#other-software)
- [Resources](#resources)
  - [Benchmarks](#benchmarks)
  - [Conferences](#conferences)
  - [E-Books](#e-books)
    - [E-books for purchase](#e-books-for-purchase)
    - [Free e-books](#free-e-books)
  - [Gophers](#gophers)
  - [Meetups](#meetups)
  - [Style Guides](#style-guides)
  - [Social Media](#social-media)
    - [Twitter](#twitter)
    - [Reddit](#reddit)
  - [Websites](#websites)
    - [Tutorials](#tutorials)
    - [Guided Learning](#guided-learning)
  - [Contribution](#contribution)
  - [License](#license)

**[⬆ back to top](#contents)**



</details>

## Actor Model

_Libraries for building actor-based programs._

- [asyncmachine-go/pkg/machine](https://github.com/pancsta/asyncmachine-go/tree/main/pkg/machine) - Graph control flow library (AOP, actor, state-machine).
- [Ergo](https://github.com/ergo-services/ergo) - An actor-based Framework with network transparency for creating event-driven architecture in Golang. Inspired by Erlang.
- [Goakt](https://github.com/Tochemey/goakt) - Fast and Distributed Actor framework using protocol buffers as message for Golang.
- [Hollywood](https://github.com/anthdm/hollywood) - Blazingly fast and light-weight Actor engine written in Golang.
- [ProtoActor](https://github.com/asynkron/protoactor-go) - Distributed actors for Go, C#, and Java/Kotlin.

**[⬆ back to top](#contents)**

## Artificial Intelligence

_Libraries for building programs that leverage AI._

- [AegisFlow](https://github.com/saivedant169/AegisFlow) - AI gateway for routing, securing, and monitoring LLM traffic across 10+ providers. OpenAI-compatible API, WASM policy plugins, canary rollouts, real-time dashboard.
- [Aetheris](https://github.com/Colin4k1024/Aetheris) - AI Agent execution runtime with event sourcing, checkpoint recovery, and At-Most-Once execution guarantee. Written in Go.
- [agent-sdk-go](https://github.com/agenticenv/agent-sdk-go) - Go SDK for building durable AI agents on Temporal with support for tools, MCP, human approvals, and sub-agent delegation.
- [ai](https://github.com/joakimcarlsson/ai) - A Go toolkit for building AI agents and applications across multiple providers with unified LLM, embeddings, tool calling, and MCP integration.
- [chromem-go](https://github.com/philippgille/chromem-go) - Embeddable vector database for Go with Chroma-like interface and zero third-party dependencies. In-memory with optional persistence.
- [dakera-go](https://github.com/dakera-ai/dakera-go) - Official Go client SDK for the Dakera self-hosted agent memory server, providing typed interfaces for memory store/recall, session management, namespace operations, and decay configuration.
- [fun](https://gitlab.com/tozd/go/fun) - The simplest but powerful way to use large language models (LLMs) in Go.
- [goai](https://github.com/zendev-sh/goai) - Go SDK for building AI applications. One SDK, 20+ providers. Inspired by Vercel AI SDK.
- [hotplex](https://github.com/hrygo/hotplex) - AI Agent runtime engine with long-lived sessions for Claude Code, OpenCode, pi-mono and other CLI AI tools. Provides full-duplex streaming, multi-platform integrations, and secure sandbox.
- [langchaingo](https://github.com/tmc/langchaingo) - LangChainGo is a framework for developing applications powered by language models.
- [langgraphgo](https://github.com/smallnest/langgraphgo) - A Go library for building stateful, multi-actor applications with LLMs, built on the concept of LangGraph，with a lot of builtin Agent architectures.
- [LocalAI](https://github.com/mudler/LocalAI) - Open Source OpenAI alternative, self-host AI models.
- [localaik](https://github.com/harshaneel/localaik) - LocalStack-style local emulation of OpenAI and Gemini APIs; single Docker container, llama.cpp + Gemma 3 backend.
- [mcp-go](https://github.com/mark3labs/mcp-go) - Go implementation of the Model Context Protocol for building MCP servers and clients in Go.
- [Ollama](https://github.com/jmorganca/ollama) - Run large language models locally.
- [OllamaFarm](https://github.com/presbrey/ollamafarm) - Manage, load-balance, and failover packs of Ollamas.
- [otellix](https://github.com/oluwajubelo1/otellix) - OpenTelemetry-native LLM observability and budget guardrails for cost-constrained production environments.
- [routex](https://github.com/Ad3bay0c/routex) - YAML-driven multi-agent AI runtime for Go with Erlang-style supervision, MCP tool server support, and a CLI.
- [web-researcher-mcp](https://github.com/zoharbabin/web-researcher-mcp) - MCP server providing AI assistants with web search, content extraction, and multi-source research capabilities. Single binary, 5 search providers with circuit-breaker failover, 4-tier scraping pipeline.
- [zenflow](https://github.com/zendev-sh/zenflow) - Multi-agent orchestration & workflow engine. Declarative YAML workflows, LLM coordinator with hub-and-spoke mailboxes, race-safe delivery. One YAML file, one Go binary. Runs on any goai-supported provider.

**[⬆ back to top](#contents)**

## Audio and Music

_Libraries for manipulating audio and music._

- [beep](https://github.com/gopxl/beep) - A simple library for playback and audio manipulation.
- [flac](https://github.com/mewkiz/flac) - Native Go FLAC encoder/decoder with support for FLAC streams.
- [gaad](https://github.com/Comcast/gaad) - Native Go AAC bitstream parser.
- [go-mpris](https://github.com/leberKleber/go-mpris) - Client for mpris dbus interfaces.
- [GoAudio](https://github.com/DylanMeeus/GoAudio) - Native Go Audio Processing Library.
- [gosamplerate](https://github.com/dh1tw/gosamplerate) - libsamplerate bindings for go.
- [id3v2](https://github.com/bogem/id3v2) - ID3 decoding and encoding library for Go.
- [malgo](https://github.com/gen2brain/malgo) - Mini audio library.
- [minimp3](https://github.com/tosone/minimp3) - Lightweight MP3 decoder library.
- [music-theory](https://github.com/go-music-theory/music-theory) - Music theory models in Go.
- [Oto](https://github.com/hajimehoshi/oto) - A low-level library to play sound on multiple platforms.
- [PortAudio](https://github.com/gordonklaus/portaudio) - Go bindings for the PortAudio audio I/O library.
-[voxrai-ai](https://github.com/Voxray-AI/Voxray) - AI voice agents with a JSON configuration,  STT → LLM → TTS pipelines over WebSocket and WebRTC 

**[⬆ back to top](#contents)**

## Authentication and Authorization

_Libraries for implementing authentication and authorization._

- [authboss](https://github.com/volatiletech/authboss) - Modular authentication system for the web. It tries to remove as much boilerplate and "hard things" as possible so that each time you start a new web project in Go, you can plug it in, configure it, and start building your app without having to build an authentication system each time.
- [authgate](https://github.com/go-authgate/authgate) - A lightweight OAuth 2.0 Authorization Server supporting Device Authorization Grant ([RFC 8628](https://datatracker.ietf.org/doc/html/rfc8628)), Authorization Code Flow with PKCE ([RFC 6749](https://datatracker.ietf.org/doc/html/rfc6749) + [RFC 7636](https://datatracker.ietf.org/doc/html/rfc7636)), and Client Credentials Grant for machine-to-machine authentication.
- [branca](https://github.com/essentialkaos/branca) - branca token [specification implementation](https://github.com/tuupola/branca-spec) for Golang 1.15+.
- [casbin](https://github.com/hsluoyz/casbin) - Authorization library that supports access control models like ACL, RBAC, and ABAC.
- [cookiestxt](https://github.com/mengzhuo/cookiestxt) - provides a parser of cookies.txt file format.
- [go-githubauth](https://github.com/jferrl/go-githubauth) - Utilities for GitHub authentication: generate and use GitHub application and installation tokens.
- [go-guardian](https://github.com/shaj13/go-guardian) - Go-Guardian is a golang library that provides a simple, clean, and idiomatic way to create powerful modern API and web authentication that supports LDAP, Basic, Bearer token, and Certificate based authentication.
- [go-iam](https://github.com/melvinodsa/go-iam) - Developer-first Identity and Access Management system with a simple UI.
- [go-jose](https://github.com/go-jose/go-jose) - Fairly complete implementation of the JOSE working group's JSON Web Token, JSON Web Signatures, and JSON Web Encryption specs.
- [go-jwt](https://github.com/deatil/go-jwt) - A JWT (JSON Web Token) library for Go.
- [go-jwt](https://github.com/pardnchiu/go-jwt) - JWT authentication package providing access tokens and refresh tokens with fingerprinting, Redis storage, and automatic refresh capabilities.
- [goiabada](https://github.com/leodip/goiabada) - An open-source authentication and authorization server supporting OAuth2 and OpenID Connect.
- [gologin](https://github.com/dghubble/gologin) - chainable handlers for login with OAuth1 and OAuth2 authentication providers.
- [gorbac](https://github.com/mikespook/gorbac) - provides a lightweight role-based access control (RBAC) implementation in Golang.
- [gosession](https://github.com/Kwynto/gosession) - This is quick session for net/http in GoLang. This package is perhaps the best implementation of the session mechanism, or at least it tries to become one.
- [goth](https://github.com/markbates/goth) - provides a simple, clean, and idiomatic way to use OAuth and OAuth2. Handles multiple providers out of the box.
- [jeff](https://github.com/abraithwaite/jeff) - Simple, flexible, secure, and idiomatic web session management with pluggable backends.
- [jwt](https://github.com/pascaldekloe/jwt) - Lightweight JSON Web Token (JWT) library.
- [jwt](https://github.com/cristalhq/jwt) - Safe, simple, and fast JSON Web Tokens for Go.
- [jwt-auth](https://github.com/adam-hanna/jwt-auth) - JWT middleware for Golang http servers with many configuration options.
- [jwt-go](https://github.com/golang-jwt/jwt) - A full featured implementation of JSON Web Tokens (JWT). This library supports the parsing and verification as well as the generation and signing of JWTs.
- [jwx](https://github.com/lestrrat-go/jwx) - Go module implementing various JWx (JWA/JWE/JWK/JWS/JWT, otherwise known as JOSE) technologies.
- [keto](https://github.com/ory/keto) - Open Source (Go) implementation of "Zanzibar: Google's Consistent, Global Authorization System". Ships gRPC, REST APIs, newSQL, and an easy and granular permission language. Supports ACL, RBAC, and other access models.
- [loginsrv](https://github.com/tarent/loginsrv) - JWT login microservice with pluggable backends such as OAuth2 (Github), htpasswd, osiam.
- [oauth2](https://github.com/golang/oauth2) - Successor of goauth2. Generic OAuth 2.0 package that comes with JWT, Google APIs, Compute Engine, and App Engine support.
- [oidc](https://github.com/zitadel/oidc) - Easy to use OpenID Connect client and server library written for Go and certified by the OpenID Foundation.
- [openfga](https://github.com/openfga/openfga) - Implementation of fine-grained authorization based on the "Zanzibar: Google's Consistent, Global Authorization System" paper. Backed by [CNCF](https://www.cncf.io/).
- [osin](https://github.com/openshift/osin) - Golang OAuth2 server library.
- [otpgen](https://github.com/grijul/otpgen) - Library to generate TOTP/HOTP codes.
- [otpgo](https://github.
