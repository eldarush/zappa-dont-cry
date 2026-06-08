# [Awesome Python](https://awesome-python.com/)

An opinionated guide to the best Python frameworks, libraries, tools, and resources.

**Visit the [website](https://awesome-python.com/) to search and filter projects more easily.**

## **Sponsors**

> The **#10 most-starred repo on GitHub**. Put your product in front of Python developers. [Become a sponsor](SPONSORSHIP.md).

## Categories

**AI & ML**

- [AI and Agents](#ai-and-agents)
- [Deep Learning](#deep-learning)
- [Machine Learning](#machine-learning)
- [Natural Language Processing](#natural-language-processing)
- [Computer Vision](#computer-vision)
- [Recommender Systems](#recommender-systems)

**Web Development**

- [Web Frameworks](#web-frameworks)
- [Web APIs](#web-apis)
- [Web Servers](#web-servers)
- [WebSocket](#websocket)
- [Template Engines](#template-engines)
- [Web Asset Management](#web-asset-management)
- [Authentication](#authentication)
- [Admin Panels](#admin-panels)
- [CMS](#cms)
- [Static Site Generators](#static-site-generators)

**HTTP & Scraping**

- [HTTP Clients](#http-clients)
- [Web Scraping](#web-scraping)
- [Email](#email)

**Database & Storage**

- [ORM](#orm)
- [Database Drivers](#database-drivers)
- [Database](#database)
- [Caching](#caching)
- [Search](#search)
- [Serialization](#serialization)

**Data & Science**

- [Data Analysis](#data-analysis)
- [Data Ingestion / ETL](#data-ingestion--etl)
- [Data Validation](#data-validation)
- [Data Visualization](#data-visualization)
- [Geolocation](#geolocation)
- [Science](#science)
- [Quantum Computing](#quantum-computing)

**Developer Tools**

- [Algorithms and Design Patterns](#algorithms-and-design-patterns)
- [Interactive Interpreter](#interactive-interpreter)
- [Code Analysis](#code-analysis)
- [Testing](#testing)
- [Debugging Tools](#debugging-tools)
- [Build Tools](#build-tools)
- [Documentation](#documentation)

**DevOps**

- [DevOps Tools](#devops-tools)
- [Distributed Computing](#distributed-computing)
- [Task Queues](#task-queues)
- [Messaging](#messaging)
- [Job Schedulers](#job-schedulers)
- [Logging](#logging)
- [Network Virtualization](#network-virtualization)

**CLI & GUI**

- [CLI Development](#cli-development)
- [CLI Tools](#cli-tools)
- [GUI Development](#gui-development)

**Text & Documents**

- [Text Processing](#text-processing)
- [HTML Manipulation](#html-manipulation)
- [File Format Processing](#file-format-processing)
- [File Manipulation](#file-manipulation)

**Media**

- [Image Processing](#image-processing)
- [Audio & Video Processing](#audio--video-processing)
- [Game Development](#game-development)

**Python Language**

- [Implementations](#implementations)
- [Built-in Classes Enhancement](#built-in-classes-enhancement)
- [Functional Programming](#functional-programming)
- [Asynchronous Programming](#asynchronous-programming)
- [Date and Time](#date-and-time)

**Python Toolchain**

- [Environment Management](#environment-management)
- [Package Management](#package-management)
- [Package Repositories](#package-repositories)
- [Distribution](#distribution)
- [Configuration Files](#configuration-files)

**Security**

- [Cryptography](#cryptography)
- [Penetration Testing](#penetration-testing)
- [Web Security](#web-security)

**Other**

- [Hardware](#hardware)
- [Microsoft Windows](#microsoft-windows)
- [Miscellaneous](#miscellaneous)

## Projects

**AI & ML**

### AI and Agents

_Libraries for building AI applications, LLM integrations, and autonomous agents._

- Agent Skills
  - [django-ai-plugins](https://github.com/vintasoftware/django-ai-plugins) - Django backend agent skills for Django, DRF, Celery, and Django-specific code review.
  - [graphify](https://github.com/safishamsi/graphify) - Turn any folder of code, SQL schemas, docs, papers, images, or videos into a queryable knowledge graph.
  - [nuwa-skill](https://github.com/alchaincyf/nuwa-skill/blob/main/README_EN.md) - Nuwa distills the thinking of anyone — let Musk, Naval, Munger, and Feynman work for you.
  - [sentry-skills](https://github.com/getsentry/skills) - Python-focused engineering skills for code review, debugging, and backend workflows.
  - [trailofbits-skills](https://github.com/trailofbits/skills) - Python-friendly security skills for auditing, testing, and safer backend development.
- Orchestration
  - [ag2](https://github.com/ag2ai/ag2) - An open-source AgentOS for multi-agent orchestration and building agentic AI systems.
  - [autogen](https://github.com/microsoft/autogen) - A programming framework for building agentic AI applications.
  - [bernstein](https://github.com/sipyourdrink-ltd/bernstein) - A deterministic Python orchestrator for CLI coding agents (Claude Code, Codex, Gemini CLI, and 40+ more) with parallel git worktrees and an HMAC-signed audit chain.
  - [bindu](https://github.com/getbindu/Bindu) - A framework that wraps any agent handler with DID-based cryptographic identity, A2A JSON-RPC over HTTP, OAuth2 auth, x402 (USDC) payments, and a built-in operator inbox.
  - [bub](https://github.com/bubbuild/bub) - A lightweight, hook-first Python framework for channel-native agents that live alongside people.
  - [crewai](https://github.com/crewAIInc/crewAI) - A framework for orchestrating role-playing autonomous AI agents for collaborative task solving.
  - [dspy](https://github.com/stanfordnlp/dspy) - A framework for programming, not prompting, language models.
  - [hermes-agent](https://github.com/nousresearch/hermes-agent) - An adaptive AI agent framework that grows with you.
  - [langchain](https://github.com/langchain-ai/langchain) - Building applications with LLMs through composability.
  - [openai-agents](https://github.com/openai/openai-agents-python) - OpenAI's framework for building and managing AI agents.
  - [OpenChronicle](https://github.com/Einsia/OpenChronicle) - Open-source, local-first memory for any tool-capable LLM agent.
  - [promptise](https://github.com/promptise-com/foundry) - A framework for building end-to-end production-ready agentic systems, scalable & secure MCP's and autonomous agents.
  - [pydantic-ai](https://github.com/pydantic/pydantic-ai) - A Python agent framework for building generative AI applications with structured schemas.
  - [TradingAgents](https://github.com/TauricResearch/TradingAgents) - A multi-agents LLM financial trading framework.
- Data Layer
  - [instructor](https://github.com/567-labs/instructor) - A library for extracting structured data from LLMs, powered by Pydantic.
  - [llama-index](https://github.com/run-llama/llama_index) - A data framework for your LLM application.
  - [mem0](https://github.com/mem0ai/mem0) - An intelligent memory layer for AI agents enabling personalized interactions.
- Pre-trained Models and Inference
  - [diffusers](https://github.com/huggingface/diffusers) - A library that provides pre-trained diffusion models for generating and editing images, audio, and video.
  - [mlx-lm](https://github.com/ml-explore/mlx-lm) - Run and fine-tune large language models on Apple Silicon with MLX.
  - [sglang](https://github.com/sgl-project/sglang) - A high-performance serving framework for large language models and multimodal models.
  - [transformers](https://github.com/huggingface/transformers) - A framework that lets you easily use pre-trained transformer models for NLP, vision, and audio tasks.
  - [unsloth](https://github.com/unslothai/unsloth) - A library for faster LLM fine-tuning and training with reduced memory usage.
  - [vllm](https://github.com/vllm-project/vllm) - A high-throughput and memory-efficient inference and serving engine for LLMs.
- Speech
  - [openai-whisper](https://github.com/openai/whisper) - A general-purpose automatic speech recognition model trained on 680k hours of multilingual and multitask supervised data.
  - [funasr](https://github.com/modelscope/FunASR) - Industrial-grade speech recognition toolkit with 170x realtime speed, 50+ languages, speaker diarization, and emotion detection.
  - [vibevoice](https://github.com/microsoft/VibeVoice) - A family of open-source voice AI models from Microsoft for text-to-speech and long-form speech recognition.
  - [voxcpm](https://github.com/OpenBMB/VoxCPM) - A tokenizer-free text-to-speech foundation model for multilingual speech generation and voice cloning.

### Deep Learning

_Frameworks for Neural Networks and Deep Learning. Also see [awesome-deep-learning](https://github.com/ChristosChristofidis/awesome-deep-learning)._

- [jax](https://github.com/jax-ml/jax) - A library for high-performance numerical computing with automatic differentiation and JIT compilation.
- [keras](https://github.com/keras-team/keras) - A high-level deep learning library with support for JAX, TensorFlow, and PyTorch backends.
- [pytorch-lightning](https://github.com/Lightning-AI/pytorch-lightning) - Deep learning framework to train, deploy, and ship AI products Lightning fast.
- [pytorch](https://github.com/pytorch/pytorch) - Tensors and Dynamic neural networks in Python with strong GPU acceleration.
- [stable-baselines3](https://github.com/DLR-RM/stable-baselines3) - PyTorch implementations of Stable Baselines (deep) reinforcement learning algorithms.
- [tensorflow](https://github.com/tensorflow/tensorflow) - The most popular Deep Learning framework created by Google.

### Machine Learning

_Libraries for Machine Learning. Also see [awesome-machine-learning](https://github.com/josephmisiti/awesome-machine-learning#python)._

- [catboost](https://github.com/catboost/catboost) - A fast, scalable, high performance gradient boosting on decision trees library.
- [feature_engine](https://github.com/feature-engine/feature_engine) - sklearn compatible API with the widest toolset for feature engineering and selection.
- [h2o](https://github.com/h2oai/h2o-3) - Open Source Fast Scalable Machine Learning Platform.
- [lightgbm](https://github.com/lightgbm-org/LightGBM) - A fast, distributed, high performance gradient boosting framework.
- [mindsdb](https://github.com/mindsdb/minds-platform) - MindsDB is an open source AI layer for existing databases that allows you to effortlessly develop, train and deploy state-of-the-art machine learning models using standard queries.
- [pgmpy](https://github.com/pgmpy/pgmpy) - A Python library for probabilistic graphical models and Bayesian networks.
- [scikit-learn](https://github.com/scikit-learn/scikit-learn) - The most popular Python library for Machine Learning with extensive documentation and community support.
- - [scikit-lego](https://github.com/koaning/scikit-lego) - A collection of lego bricks for scikit-learn pipelines.
- [spark.ml](https://github.com/apache/spark) - [Apache Spark](https://spark.apache.org/)'s scalable [Machine Learning library](https://spark.apache.org/docs/latest/ml-guide.html) for distributed computing.
- [TabGAN](https://github.com/Diyago/Tabular-data-generation) - Synthetic tabular data generation using GANs, Diffusion Models, and LLMs.
- [timesfm](https://github.com/google-research/timesfm) - A pretrained foundation model from Google Research for time-series forecasting.
- [xgboost](https://github.com/dmlc/xgboost) - A scalable, portable, and distributed gradient boosting library.

### Natural Language Processing

_Libraries for working with human languages._

- General
  - [gensim](https://github.com/piskvorky/gensim) - Topic Modeling for Humans.
  - [nltk](https://github.com/nltk/nltk) - A leading platform for building Python programs to work with human language data.
  - [spacy](https://github.com/explosion/spaCy) - A library for industrial-strength natural language processing in Python and Cython.
  - [stanza](https://github.com/stanfordnlp/stanza) - The Stanford NLP Group's official Python library, supporting 60+ languages.
- Chinese
  - [funnlp](https://github.com/fighting41love/funNLP) - A collection of tools and datasets for Chinese NLP.
  - [jieba](https://github.com/fxsjy/jieba) - The most popular Chinese text segmentation library.

### Computer Vision

_Libraries for Computer Vision._

- [easyocr](https://github.com/JaidedAI/EasyOCR) - Ready-to-use OCR with 40+ languages supported.
- [kornia](https://github.com/kornia/kornia/) - Open Source Differentiable Computer Vision Library for PyTorch.
- [opencv](https://github.com/opencv/opencv-python) - Open Source Computer Vision Library.
- [pytesseract](https://github.com/madmaze/pytesseract) - A wrapper for [Google Tesseract OCR](https://github.com/tesseract-ocr).
- [ultralytics](https://github.com/ultralytics/ultralytics) - Ultralytics YOLO for object detection, segmentation, pose estimation, and classification with state-of-the-art accuracy and speed.

### Recommender Systems

_Libraries for building recommender systems._

- [annoy](https://github.com/spotify/annoy) - Approximate Nearest Neighbors in C++/Python optimized for memory usage.
- [implicit](https://github.com/benfred/implicit) - A fast Python implementation of collaborative filtering for implicit datasets.
- [scikit-surprise](https://github.com/NicolasHug/Surprise) - A scikit for building and analyzing recommender systems.

**Web Development**

### Web Frameworks

_Traditional full stack web frameworks. Also see [Web APIs](#web-apis)._

- Synchronous
  - [bottle](https://github.com/bottlepy/bottle) - A fast and simple micro-framework distributed as a single file with no dependencies.
  - [django](https://github.com/django/django) - The most popular web framework in Python.
    - [awesome-django](https://github.com/wsvincent/awesome-django)
  - [flask](https://github.com/pallets/flask) - A microframework for Python.
    - [awesome-flask](https://github.com/humiaozuzu/awesome-flask)
  - [pyramid](https://github.com/Pylons/pyramid) - A small, fast, down-to-earth, open source Python web framework.
    - [awesome-pyramid](https://github.com/uralbash/awesome-pyramid)
  - [fasthtml](https://github.com/AnswerDotAI/fasthtml) - The fastest way to create an HTML app.
    - [awesome-fasthtml](https://github.com/amosgyamfi/awesome-fasthtml)
  - [masonite](https://github.com/MasoniteFramework/masonite) - The modern and developer centric Python web framework.
- Asynchronous
  - [litestar](https://github.com/litestar-org/litestar) - Production-ready, capable and extensible ASGI Web framework.
  - [microdot](https://github.com/miguelgrinberg/microdot) - The impossibly small web framework for Python and MicroPython.
  - [reflex](https://github.com/reflex-dev/reflex) - A framework for building reactive, full-stack web applications entirely with Python.
  - [robyn](https://github.com/sparckles/Robyn) - A high-performance async Python web framework with a Rust runtime.
  - [starlette](https://github.com/Kludex/starlette) - A lightweight ASGI framework and toolkit for building high-performance async services.
  - [tornado](https://github.com/tornadoweb/tornado) - A web framework and asynchronous networking library.

### Web APIs

_Libraries for building RESTful and GraphQL APIs._

- Django
  - [django-modern-rest](https://github.com/wemake-services/django-modern-rest) - Modern REST with speed, types, async, `msgspec`, `pydantic` and other goodies!
  - [django-ninja](https://github.com/vitalik/django-ninja) - Fast, Django REST framework based on type hints and Pydantic.
  - [django-rest-framework](https://github.com/encode/django-rest-framework) - A powerful and flexible toolkit to build web APIs.
  - [strawberry-django](https://github.com/strawberry-graphql/strawberry-django) - Strawberry GraphQL integration with Django.
- Flask
  - [apiflask](https://github.com/apiflask/apiflask) - A lightweight Python web API framework based on Flask and Marshmallow.
- Framework Agnostic
  - [connexion](https://github.com/spec-first/connexion) - A spec-first framework that automatically handles requests based on your OpenAPI specification.
  - [falcon](https://github.com/falconry/falcon) - A high-performance framework for building cloud APIs and web app backends.
  - [fastapi](https://github.com/fastapi/fastapi) - A modern, fast, web framework for building APIs with standard Python type hints.
  - [sanic](https://github.com/sanic-org/sanic) - A Python web server and web framework that's written to go fast.
  - [strawberry](https://github.com/strawberry-graphql/strawberry) - A GraphQL library that leverages Python type annotations for schema definition.
  - [webargs](https://github.com/marshmallow-code/webargs) - A friendly library for parsing HTTP request arguments with built-in support for popular web frameworks.

### Web Servers

_ASGI and WSGI compatible web servers._

- ASGI
  - [daphne](https://github.com/django/daphne) - An HTTP, HTTP/2 and WebSocket protocol server for ASGI and ASGI-HTTP.
  - [granian](https://github.com/emmett-framework/granian) - A Rust HTTP server for Python applications built on top of Hyper and Tokio, supporting WSGI/ASGI/RSGI.
  - [hypercorn](https://github.com/pgjones/hypercorn) - An ASGI and WSGI Server based on Hyper libraries and inspired by Gunicorn.
  - [uvicorn](https://github.com/Kludex/uvicorn) - A lightning-fast ASGI server implementation, using uvloop and httptools.
- WSGI
  - [gunicorn](https://github.com/benoitc/gunicorn) - Pre-forked, ported from Ruby's Unicorn project.
  - [uwsgi](https://github.com/unbit/uwsgi) - A project aims at developing a full stack for building hosting services, written in C.
  - [waitress](https://github.com/Pylons/waitress) - Multi-threaded, powers Pyramid.
- RPC
  - [grpcio](https://github.com/grpc/grpc) - HTTP/2-based RPC framework with Python bindings, built by Google.
  - [rpyc](https://github.com/tomerfiliba-org/rpyc) (Remote Python Call) - A transparent and symmetric RPC library for Python.

### WebSocket

_Libraries for working with WebSocket._

- [autobahn-python](https://github.com/crossbario/autobahn-python) - WebSocket & WAMP for Python on Twisted and [asyncio](https://docs.python.org/3/library/asyncio.html).
- [channels](https://github.com/django/channels) - Developer-friendly asynchrony for Django.
- [flask-socketio](https://github.com/miguelgrinberg/Flask-SocketIO) - Socket.IO integration for Flask applications.
- [picows](https://github.com/tarasko/picows) - Fastest WebSocket clients and servers with a frame level interface for the most demanding use-cases.
- [websockets](https://github.com/python-websockets/websockets) - A library for building WebSocket servers and clients with a focus on correctness and simplicity.

### Template Engines

_Libraries and tools for templating and lexing._

- [jinja](https://github.com/pallets/jinja) - A modern and designer friendly templating language.
- [mako](https://github.com/sqlalchemy/mako) - Hyperfast and lightweight templating for the Python platform.

### Web Asset Management

_Tools for managing, compressing and minifying website assets._

- [django-compressor](https://github.com/django-compressor/django-compressor) - Compresses linked and inline JavaScript or CSS into a single cached file.
- [django-storages](https://github.com/jschneier/django-storages) - A collection of custom storage back ends for Django.

### Authentication

_Libraries for implementing authentication schemes._

- OAuth
  - [authlib](https://github.com/authlib/authlib) - JavaScript Object Signing and Encryption draft implementation.
  - [django-allauth](https://github.com/pennersr/django-allauth) - Authentication app for Django that "just works."
  - [django-oauth-toolkit](https://github.com/django-oauth/django-oauth-toolkit) - OAuth 2 goodies for Django.
  - [oauthlib](https://github.com/oauthlib/oauthlib) - A generic and thorough implementation of the OAuth request-signing logic.
- JWT
  - [pyjwt](https:
