# Legacy-Chatbox (Agentic Edition)

> *A lightweight AI client and native Agentic Harness tailored for legacy iOS devices.*

[![Download .deb](https://img.shields.io/badge/Download-.deb%20Package-blue?style=for-the-badge&logo=app-store)](https://github.com/shafqatautosupply-sketch/ChatGPT-for-Legacy-iOS/releases/latest/download/ChatGPT-for-Legacy-iOS.deb)

---

## Overview

**Legacy-Chatbox (Agentic Edition)** is a lightweight AI chat client and native agent execution framework designed specifically for legacy iOS devices. Building upon standard OpenAI-compatible provider support, this version **deeply integrates Google's native API endpoints and a lightweight native Tool Calling framework**, introducing full Agentic Harness capabilities to iOS 6 hardware.

---

## Key Features

- **Google Native API Integration**: Direct communication with Google's generative AI API endpoints.
- **Native Tool Calling Framework**: Runs a lightweight Agentic Harness on iOS 6, empowering models to dynamically invoke tools and execute tasks.
- **Multi-Provider Profiles**: Easily configure, save, and switch between Google API and OpenAI-compatible endpoints.
- **Editable System Prompt**: Customize or clear the runtime system prompt sent prior to requests.
- **Local Secure Storage**: All conversation history and API keys remain strictly local on device.
- **Streaming & Reasoning Display**: SSE streaming support with dynamic reasoning/thinking display and collapsing.
- **Authentic iOS 6 Interface**: Meticulously styled with classic UIKit elements, navigation bars, buttons, launch images, and app icons tailored for retro Apple hardware.

---

## Supported Devices

- **iPhone 4 / 4S** (iOS 6, Portrait)
- **iPhone 5** (iOS 6, Portrait)
- **iPad 4** (iOS 6, Portrait)

---

## Download & Installation

### Option 1: Direct Download (Recommended)
You can download the pre-compiled `.deb` package directly for your jailbroken device:
👉 [Download Latest `.deb` Release](https://github.com/shafqatautosupply-sketch/ChatGPT-for-Legacy-iOS/releases/latest/download/ChatGPT-for-Legacy-iOS.deb)

### Option 2: Build from Source (Theos)
If you prefer building it yourself using Theos:
1. Ensure Theos is installed on your development environment.
2. Navigate to the app directory:
   ```sh
   cd theos/LegacyChatApp
   ```
3. Build the package:
   ```sh
   make package FINALPACKAGE=1
   ```
4. The generated `.deb` package will be located in `theos/LegacyChatApp/packages/`.

---

## Configuration Guide

Open **`Settings > Model Configurations`** on your device to add your provider profile:

- **Base URL**: The API root endpoint address.
- **Chat Path**: The API endpoint path.
- **Model**: Exact model identifier.
- **API Key**: Your API credential (stored locally).
- **Tool Calling**: Enable and configure native tool-calling parameters.

---

## Acknowledgments & Credits

This project builds upon the foundational work of talented community developers:

- **Original Creator**: [BagXML](https://github.com/BagXML) — For creating the brilliant foundational legacy iOS AI client repository.
- **Intermediate Fork Developer**: Li Xiang — For the intermediate modifications and codebase used as a solid starting point for this enhanced edition.

---

## Known Limitations

- Optimized for portrait orientation only.
- Tool calling and agent execution performance depend on model tool-use capabilities and legacy hardware constraints.
- No cloud synchronization; all provider settings and chat histories are stored locally.
