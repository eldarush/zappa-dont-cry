# π RuView

<p align="center">
  <a href="https://cognitum.one/seed">
    <img src="assets/ruview-seed.png" alt="RuView - WiFi DensePose" width="100%">
  </a>
</p>
<p align="center">
  <a href="https://cognitum.one/seed">
    <img src="assets/seed.png" alt="Cognitum Seed" width="100%">
  </a>
</p>

## **See through walls with WiFi** ##

**Turn ordinary WiFi into a spatial intelligence / sensing system.** Detect people, measure breathing and heart rate, track movement, and monitor rooms — through walls, in the dark, with no cameras or wearables. Just physics.

Works natively with the four major smart-home ecosystems: **[Home Assistant](docs/integrations/home-assistant.md)** via the HA-DISCO MQTT publisher, **[Apple Home & HomePod](docs/user-guide-apple-homepod.md)** as a discoverable HAP-1.1 bridge, **[Google Home](docs/integrations/home-assistant.md)** + **[Amazon Alexa](docs/integrations/home-assistant.md)** via the same HA bridge or a [Matter](docs/adr/ADR-122-bfld-ruview-ha-matter-exposure.md) endpoint. Siri, Google Assistant, and Alexa can voice presence and vitals by room with zero custom skills.

[![Works with Home Assistant](https://img.shields.io/badge/Works%20with-Home%20Assistant-blue?logo=home-assistant&logoColor=white&labelColor=41BDF5)](docs/integrations/home-assistant.md) [![Works with Matter](https://img.shields.io/badge/Works%20with-Matter-blue?labelColor=4285F4)](docs/adr/ADR-122-bfld-ruview-ha-matter-exposure.md) [![Works with Apple Home](https://img.shields.io/badge/Works%20with-Apple%20Home-black?logo=apple)](docs/user-guide-apple-homepod.md) [![Works with Google Home](https://img.shields.io/badge/Works%20with-Google%20Home-blue?logo=googlehome)](docs/integrations/home-assistant.md) [![Works with Alexa](https://img.shields.io/badge/Works%20with-Alexa-blue?logo=amazon&logoColor=white&labelColor=00CAFF)](docs/integrations/home-assistant.md)

> Drop into any **Home Assistant** install with one `--mqtt` flag. Or pair into **Apple Home / Google Home / Alexa / SmartThings** as a Matter Bridge. Ships 21 entities per node (11 raw signals + 10 inferred semantic states: someone-sleeping, possible-distress, room-active, elderly-inactivity-anomaly, meeting-in-progress, bathroom-occupied, fall-risk-elevated, bed-exit, no-movement, multi-room-transition) plus 3 starter HA Blueprints. See [`docs/integrations/home-assistant.md`](docs/integrations/home-assistant.md) · [ADR-115](docs/adr/ADR-115-home-assistant-integration.md).

### π RuView is a WiFi sensing platform that turns radio signals into spatial intelligence.

Every WiFi router already fills your space with radio waves. When people move, breathe, or even sit still, they disturb those waves in measurable ways. RuView captures these disturbances using Channel State Information (CSI) from low-cost ESP32 sensors and turns them into actionable data: who's there, what they're doing, and whether they're okay.

**What it senses:**
- **Presence and occupancy** — detect people through walls, count them, track entries and exits
- **Vital signs** — breathing rate and heart rate, contactless, while sleeping or sitting
- **Activity recognition** — walking, sitting, gestures, falls — from temporal CSI patterns
- **Environment mapping** — RF fingerprinting identifies rooms, detects moved furniture, spots new objects
- **Sleep quality** — overnight monitoring with sleep stage classification and apnea screening

Built on [RuVector](https://github.com/ruvnet/ruvector/) and [Cognitum Seed](https://cognitum.one), RuView runs entirely on edge hardware — an ESP32 mesh (as low as $9 per node) paired with a Cognitum Seed for persistent memory, cryptographic attestation, and AI integration. No cloud, no cameras, no internet required.

The system learns each environment locally using spiking neural networks that adapt in under 30 seconds, with multi-frequency mesh scanning across 6 WiFi channels that uses your neighbors' routers as free radar illuminators. Every measurement is cryptographically attested via an Ed25519 witness chain.

RuView turns ordinary WiFi into a contactless sensor. A $9 ESP32 board reads the radio reflections off the people in a room, and a small pretrained model — published on Hugging Face at [`ruvnet/wifi-densepose-pretrained`](https://huggingface.co/ruvnet/wifi-densepose-pretrained) — tells you who's there, how they're breathing, and how their heart rate is trending. The model fits in 8 KB (4-bit quantized) and runs in microseconds on a Raspberry Pi. (The [v2 encoder](https://huggingface.co/ruvnet/wifi-densepose-pretrained) reports an honest, label-free held-out **temporal-triplet accuracy of 82.3%** — up from 66.4% raw; the older "100% presence" figure was measured on a single-class recording and has been retracted in favor of this.) No cameras, no wearables, no app on the user's phone.

### Built for low-power edge applications

[Edge modules](#edge-intelligence-adr-041) are small programs that run directly on the ESP32 sensor — no internet needed, no cloud fees, instant response.

[![Rust 1.85+](https://img.shields.io/badge/rust-1.85+-orange.svg)](https://www.rust-lang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Tests: 1463](https://img.shields.io/badge/tests-1463%20passed-brightgreen.svg)](https://github.com/ruvnet/RuView)
[![Docker: multi-arch](https://img.shields.io/badge/docker-amd64%20%2B%20arm64-blue.svg)](https://hub.docker.com/r/ruvnet/wifi-densepose)
[![Vital Signs](https://img.shields.io/badge/vital%20signs-breathing%20%2B%20heartbeat-red.svg)](#vital-sign-detection)
[![ESP32 Ready](https://img.shields.io/badge/ESP32--S3-CSI%20streaming-purple.svg)](#esp32-s3-hardware-pipeline)
[![crates.io](https://img.shields.io/crates/v/wifi-densepose-ruvector.svg)](https://crates.io/crates/wifi-densepose-ruvector)
[![Downloads](https://img.shields.io/badge/downloads-10M%2B-brightgreen.svg)](#-edge-module-catalog)

 
> | What | How | Speed / scale |
> |------|-----|---------------|
> | 🫁 **Breathing rate** | Bandpass 0.1–0.5 Hz on wrapped phase, circular variance, zero-crossing BPM ([#593](https://github.com/ruvnet/RuView/issues/593)) | 6–30 BPM, real-time |
> | 💓 **Heart rate** | Bandpass 0.8–2.0 Hz, zero-crossing BPM | 40–120 BPM, real-time |
> | 👤 **Presence detection** | Trained head on Hugging Face ([`ruvnet/wifi-densepose-pretrained`](https://huggingface.co/ruvnet/wifi-densepose-pretrained); v2 encoder = 82.3% held-out temporal-triplet acc, honestly re-benchmarked) + a phase-variance fallback that needs no model | < 1 ms, ~30 s ambient calibration |
> | 🧬 **CSI embeddings** | 128-dim contrastive encoder shipped on Hugging Face, 4-bit quantised variant fits in 8 KB | **164,183 emb/s** on M4 Pro |
> | 🦴 **17-keypoint pose estimation** | `cog-pose-estimation` Cog v0.0.1 — signed aarch64 + x86_64 binaries on GCS, loads `pose_v1.safetensors` via Candle. Train your own from paired data in 2.1 s on an RTX 5080 ([ADR-101](docs/adr/ADR-101-pose-estimation-cog.md), [benchmarks](docs/benchmarks/pose-estimation-cog.md)). **SOTA on MM-Fi:** [`ruvnet/wifi-densepose-mmfi-pose`](https://huggingface.co/ruvnet/wifi-densepose-mmfi-pose) hits **82.69% torso-PCK@20** (ensemble 83.59%), beating MultiFormer (72.25%) and CSI2Pose (68.41%) on the matched MM-Fi `random_split` protocol — self-corrected and auditable on [AetherArena](https://huggingface.co/spaces/ruvnet/aether-arena) | 8.4 ms cold-start on a Pi 5 |
> | 🚶 **Motion / activity** | Motion-band power + phase acceleration | Real-time |
> | 🤸 **Fall detection** | Phase-acceleration threshold + 3-frame debounce + 5 s cooldown ([#263](https://github.com/ruvnet/RuView/issues/263)) | < 200 ms |
> | 🧮 **Multi-person count** | Adaptive P95 normalisation + runtime-tunable dedup factor (`/api/v1/config/dedup-factor`, [#491](https://github.com/ruvnet/RuView/pull/491)). Six specialised learned counters available as Cogs: `occupancy-zones`, `elevator-count`, `queue-length`, `customer-flow`, `clean-room`, `person-matching` | Real-time, self-calibrating |
> | 🌍 **World model prediction** | OccWorld TransVQVAE — 15-frame future occupancy prediction, 209 ms inference, 3.4 GB VRAM on RTX 5080; fine-tune on your space with `occworld_retrain.py` ([ADR-147](docs/adr/ADR-147-nvidia-cosmos-world-foundation-model-integration.md)) | 15 frames × 200×200×16 vox |
> | 🧱 **Through-wall sensing** | Fresnel-zone geometry + multipath modeling | Up to ~5 m, signal-dependent |
> | 🧠 **Edge intelligence** | **105-cog catalog** ([ADR-102](docs/adr/ADR-102-edge-module-registry.md)) live from `app-registry.json` — health, security, building, retail, industrial, research, AI, swarm, signal, network, and developer modules. Optional Cognitum Seed adds persistent vector store + kNN + witness chain | $140 total BOM |
> | 🎯 **Camera-free pre-training** | Self-supervised contrastive encoder, 12.2M training steps on 60K frames, shipped on Hugging Face | 84 s/epoch retrain on M4 Pro |
> | 📷 **Camera-supervised fine-tune** | MediaPipe + ESP32 CSI paired training, end-to-end Candle pipeline on RTX 5080 ([ADR-079](docs/adr/ADR-079-camera-supervised-pose-finetune.md)) | 2.1 s for 400 epochs (~5 ms/epoch) |
> | 📡 **Multi-frequency mesh** | Channel hopping across 6 bands, TDM slot scheduling ([ADR-029](docs/adr/ADR-029-multifrequency-mesh.md)) | 3× sensing bandwidth |
> | 🌐 **3D point cloud fusion** | Camera depth (MiDaS) + WiFi CSI + mmWave radar → unified spatial model | 22 ms pipeline · 19K+ points/frame |
>
> Browse the full 105-module catalog (with practical descriptions, sizes, and difficulty) below in [🧩 Edge Module Catalog](#-edge-module-catalog), or visit [seed.cognitum.one/store](https://seed.cognitum.one/store).
>
> 🤗 **Pretrained weights**: download from [`ruvnet/wifi-densepose-pretrained`](https://huggingface.co/ruvnet/wifi-densepose-pretrained) — see [Loading the pretrained model](#loading-the-pretrained-model) below for one-command setup.

```bash
# Option 1: Docker (simulated data, no hardware needed)
docker pull ruvnet/wifi-densepose:latest
docker run -p 3000:3000 ruvnet/wifi-densepose:latest
# Open http://localhost:3000

# Option 2a: Live sensing with ESP32-S3 hardware ($9)
# Flash firmware, provision WiFi, and start sensing:
python -m esptool --chip esp32s3 --port COM9 --baud 460800 \
  write_flash 0x0 bootloader.bin 0x8000 partition-table.bin \
  0xf000 ota_data_initial.bin 0x20000 esp32-csi-node.bin
python firmware/esp32-csi-node/provision.py --port COM9 \
  --ssid "YourWiFi" --password "secret" --target-ip 192.168.1.20

# Option 2b: WiFi 6 + 802.15.4 research sensing with ESP32-C6 ($6-10, ADR-110)
# Same csi-node firmware compiled for the C6 target — picks up the C6
# overlay (sdkconfig.defaults.esp32c6) automatically.
cd firmware/esp32-csi-node
idf.py set-target esp32c6 && idf.py build
idf.py -p COM6 flash
# C6 boot extras (vs S3): HE-LTF subcarrier tagging in ADR-018 bytes 18-19,
#   802.15.4 mesh time-sync on channel 15, TWT setup when the AP supports it,
#   opt-in LP-core wake-on-motion for ~5 µA battery seed nodes.
# v0.6.7 adds: real LP-core RISC-V motion-gate program (debounce + motion
#   counter) and a Wi-Fi 6 soft-AP with TWT Responder so two C6 boards can
#   benchmark real iTWT without buying an 11ax router. Both default off,
#   flip CONFIG_C6_{LP_CORE,SOFTAP_HE}_ENABLE to turn them on.

# Option 3: Full system with Cognitum Seed ($140)
# ESP32 streams CSI → bridge forwards to Seed for persistent storage + kNN + witness chain
node scripts/rf-scan.js --port 5006           # Live RF room scan
node scripts/snn-csi-processor.js --port 5006  # SNN real-time learning
node scripts/mincut-person-counter.js --port 5006  # Correct person counting

# Option 4: Python — live on PyPI (ADR-117)
pip install ruview                        # or: pip install wifi-densepose
# Both ship the same compiled PyO3 wheel (~250 KB, abi3-py310, Linux/macOS/Windows).
# Add [client] for the asyncio WebSocket + paho-mqtt clients:
pip install "ruview[client]"              # or: pip install "wifi-densepose[client]"

# from ruview import BreathingExtractor, HeartRateExtractor   # equivalent to:
# from wifi_densepose import BreathingExtractor, HeartRateExtractor
# from ruview.client import SensingClient, RuViewMqttClient
```

[![PyPI ruview](https://img.shields.io/pypi/v/ruview?label=ruview)](https://pypi.org/project/ruview/) [![PyPI wifi-densepose](https://img.shields.io/pypi/v/wifi-densepose?label=wifi-densepose)](https://pypi.org/project/wifi-densepose/)

> [!NOTE]
> **CSI-capable hardware recommended.** Presence, vital signs, through-wall sensing, and all advanced capabilities require Channel State Information (CSI) from an ESP32-S3 ($9) or research NIC. The Docker image runs with simulated data for evaluation. Consumer WiFi laptops provide RSSI-only presence detection.

> **Hardware options** for live CSI capture:
>
> | Option | Hardware | Cost | Full CSI | Capabilities |
> |--------|----------|------|----------|-------------|
> | **ESP32 + Cognitum Seed** (recommended) | ESP32-S3 + [Cognitum Seed](https://cognitum.one) | ~$140 | Yes | Presence, motion, breathing, heart rate, fall detection, multi-person counting, 17-keypoint pose (signed Cog binary), 105-cog catalog, persistent vector store, kNN search, witness chain, MCP proxy |
> | **ESP32 Mesh** | 3-6× ESP32-S3 + WiFi router | ~$54 | Yes | Same capabilities as above without the persistent-memory features |
> | **ESP32-C6 research node** ([ADR-110](docs/adr/ADR-110-esp32-c6-firmware-extension.md), [witness](docs/WITNESS-LOG-110.md), [reviewer guide](docs/ADR-110-REVIEW-GUIDE.md), [firmware v0.7.0](https://github.com/ruvnet/RuView/releases/tag/v0.7.0-esp32)) | ESP32-C6-DevKit ($6–10) | ~$10 | Yes (Wi-Fi 6 capable) | Same CSI pipeline as S3 with the dual-target firmware. **Firmware-side ADR-110 substrate now closed** (v0.7.0): ESP-NOW cross-board mesh quantified at **99.56 % match / 104 µs smoothed offset stdev / 3.95× EMA suppression** over a 5-min two-board soak (witness §A0.10), 32-byte UDP sync packet with operator-tunable cadence (§A0.12), ADR-018 byte 19 bit 4 wire-fix sourced from the working ESP-NOW path (§A0.13). Wire format ready for HE-LTF PPDU tagging in ADR-018 bytes 18-19 (firmware encoder + Rust + Python decoders verified end-to-end across 23 unit tests). LP-core motion-gate RISC-V program and Wi-Fi 6 soft-AP with TWT Responder both ship as opt-in code paths (default off). **Hardware-gated for measurement**: HE-LTF live subcarrier capture needs an 11ax AP (IDF v5.4 doesn't expose AP-side HE config — §A0.6); ~5 µA LP-core hibernation needs an INA meter to capture; 802.15.4 raw RX is broken in IDF v5.4 (workaround: ESP-NOW transport, shipped + measured). See witness log for the empirical / claimed split. |
> | **Research NIC** | Intel 5300 / Atheros AR9580 | ~$50-100 | Yes | Full CSI with 3x3 MIMO |
> | **Any WiFi** | Windows, macOS, or Linux laptop | $0 | No | RSSI-only: coarse presence and motion (see [tutorial #36](https://github.com/ruvnet/RuView/issues/36)) |
>
> No hardware? Verify the signal processing pipeline with the deterministic reference signal: `python archive/v1/data/proof/verify.py`
>
---


  <a href="https://ruvnet.github.io/RuView/">
    <img src="assets/v2-screen.png" alt="WiFi DensePose — Live pose detection with setup guide" width="800">
  </a>
  <br>
  <em>Real-time pose skeleton from WiFi CSI signals — no cameras, no wearables</em>
  <br><br>
  <a href="https://ruvnet.github.io/RuView/"><strong>▶ Live Observatory Demo</strong></a>
  &nbsp;|&nbsp;
  <a href="https://ruvnet.github.io/RuView/pose-fusion.html"><strong>▶ Dual-Modal Pose Fusion Demo</strong></a>
  &nbsp;|&nbsp;
  <a href="https://ruvnet.github.io/RuView/pointcloud/"><strong>▶ Live 3D Point Cloud</strong></a>
  &nbsp;|&nbsp;
  <a href="https://ruvnet.github.io/RuView/three.js/"><strong>▶ three.js Demos (5)</strong></a>

> The [server](#-quick-start) is optional for visualization and aggregation — the ESP32 [runs independently](#esp32-s3-hardware-pipeline) for presence detection, vital signs, and fall alerts.
>
> **Live ESP32 pipeline**: Connect an ESP32-S3 node → run the [sensing server](#sensing-server) → open the [pose fusion demo](https://ruvnet.github.io/RuView/pose-fusion.html) for real-time dual-modal pose estimation (webcam + WiFi CSI). See [ADR-059](docs/adr/ADR-059-live-esp32-csi-pipeline.md).
>
> **three.js scene gallery** at [`/three.js/`](https://ruvnet.github.io/RuView/three.js/) — five progressively richer ADR-097 demos: helpers, cinematic, GLTF skinned, FBX skinned, and a live MediaPipe→Mixamo retargeting feed driven by ESP32 CSI. Demos 04 and 05 require a local Mixamo `X Bot.fbx` (license boundary — not redistributed).


## 🤗 Pretrained model on Hugging Face

Pretrained CSI weights live at [`ruvnet/wifi-densepose-pretrained`](https://huggingface.co/ruvnet/wifi-densepose-pretrained) — 12.2M training steps on 60K frames / 610K contrastive triplets, **82.3% held-out temporal-triplet accuracy** (up from 66.4% raw; the older "100% presence" figure was measured on a single-class recording and has been retracted), 4-bit quantized variant fits in 8 KB. The release includes a contrastive **CSI encoder** producing 128-dim embeddings (164,183 emb/s on M4 Pro) and a **presence-detection head**. Per-node LoRA adapters are included for environment-specific fine-tuning.

```bash
# Download the model bundle
pip install huggingface_hub
huggingface-cli download ruvnet/wifi-densepose-pretrained --local-dir models/wifi-densepose-pretrained
```

**What works today vs. what's pending wiring:**

| Consumer | Format used | Status |
|----------|-------------|--------|
| Python training / evaluation / embedding extraction | `model.safetensors` | ✅ Works — load with `safetensors.torch.load_file` |
| Inspect / re-export the bundle | `model.rvf.jsonl` (line-by-line JSON) | ✅ Works — plain JSONL |
| Sensing-server `--model <PATH>` flag | binary RVF (`RVFS` magic) | ⚠️ Loader does not yet accept the JSONL container |

**Known gap:** the HF model ships in JSONL RVF format, but `v2/crates/wifi-densepose-sensing-server/src/rvf_container.rs` only parses the binary RVF segment format. Pointing `--model` at `model.rvf.jsonl` currently errors with `invalid magic at offset 0: expected 0x52564653, got 0x7974227B` and the live pipeline degrades to null output rather than falling back to heuristic mode — so for the live sensing-server, run **without** `--model` until a JSONL adapter lands (or the model is re-published as binary RVF). Use the weights from Python / training in the meantime.

**Quantization choices** (all in the HF repo): `model-q2.bin` (4 KB) · `model-q4.bin` ⭐ recommended (8 KB) · `model-q8.bin` (16 KB) · `model.safetensors` full (48 KB)

The separate **17-keypoint pose-estimation model** is now published at [`ruvnet/wifi-densepose-mmfi-pose`](https://huggingface.co/ruvnet/wifi-densepose-mmfi-pose) — **82.69% torso-PCK@20** on MM-Fi (single model) / **83.59%** (3-model ensemble + TTA), beating the prior published SOTA MultiFormer (72.25%) and CSI2Pose (68.41%) on the matched `random_split` protocol. See **Results & proof** below.

### Results & proof

| What | Where | Numbers |
|------|-------|---------|
| **MM-Fi pose model (SOTA)** | [`ruvnet/wifi-densepose-mmfi-pose`](https://huggingface.co/ruvnet/wifi-densepose-mmfi-pose) | 82.69% torso-PCK@20 (single) · 83.59% (ensemble+TTA) · 75K-param micro variant 74.30% |
| **AetherArena benchmark Space** | [`ruvnet/aether-arena`](https://huggingface.co/spaces/ruvnet/aether-arena) | self-correcting, auditable MM-Fi leaderboard |
| **Full MM-Fi study (honest picture)** | [`docs/benchmarks/mmfi-wifi-sensing-study.md`](docs/benchmarks/mmfi-wifi-sensing-study.md) | pose + action; zero-shot cross-subject ~64%, 
