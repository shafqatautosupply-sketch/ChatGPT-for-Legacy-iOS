# Legacy-Chatbox (Agentic Edition)

> *A lightweight AI client and native Agentic Harness tailored for legacy iOS devices.*

[中文](#中文) | [English](#english)

---

## 中文

**Legacy-Chatbox (Agentic Edition)** 是一个专为旧版 iOS 设备设计的轻量化 AI 聊天客户端与智能体（Agent）运行环境。在继承经典 OpenAI 兼容接口的基础上，本项目**深度集成了 Google 原生 API 端点以及轻量级原生 Tool Calling（工具调用）框架**，首次在 iOS 6 时代设备上实现了完整的 Agentic 交互能力。

---

### 📌 核心特性

- **Google 原生 API 支持**：直接对接 Google 强大的生成式 AI 接口。
- **原生工具调用框架 (Tool Calling)**：在 iOS 6 复古设备上运行轻量级 Agentic Harness，支持模型动态调用工具与执行任务。
- **多模型配置切换**：支持保存与无缝切换多个 Provider（Google API / OpenAI 兼容接口）。
- **可定制 System Prompt**：支持在设置中自定义每次请求前发送的系统提示词。
- **本地安全存储**：所有会话历史与 API Key 均严格仅保存在本地设备上，保护隐私。
- **流式输出与思考展示**：支持 SSE 流式传输，并带有推理过程（Reasoning/Thinking）的动态显示与收起。
- **原生 iOS 6 界面**：完美适配经典 UIKit 审美，复刻 iOS 6 风格的导航栏、按钮、启动图与应用图标。

---

### 📱 支持设备

- **iPhone 4 / 4S** (iOS 6, 竖屏)
- **iPhone 5** (iOS 6, 竖屏)
- **iPad 4** (iOS 6, 竖屏)

---

### 📦 构建与安装

本项目采用 **Theos** 打包流程进行越狱插件/应用构建：

1. 确保您的开发机已正确安装 Theos。
2. 进入应用源码目录：
   ```sh
   cd theos/LegacyChatApp
   ```
3. 执行打包命令：
   ```sh
   make package FINALPACKAGE=1
   ```
4. 生成的 `.deb` 安装包将位于 `theos/LegacyChatApp/packages/` 目录下，将其传输并安装到已越狱的 iOS 6 设备中。

---

### ⚙️ 配置指南

在设备上打开 **`Settings > Model Configurations`** 添加并配置您的 Provider：

- **Base URL**: 服务根地址（例如 Google API 根路径或兼容网关）。
- **Chat Path**: 接口路径（例如 `/chat/completions`）。
- **Model**: 模型准确名称。
- **API Key**: 您的 API 密钥（仅存储于本地）。
- **Tool Calling**: 开启并配置原生工具调用参数。

---

### 🤝 致谢与鸣谢

本项目的发展离不开社区优秀开发者的卓越贡献：

- **主仓库原作者**：[BagXML](https://github.com/BagXML) — 感谢其创建了优秀的旧 iOS 设备 AI 客户端基础架构。
- **中间分支开发者**：Li Xiang — 感谢其前期界面的优化与中间分支代码，为本项目的二次开发提供了优秀起点。

---

### ⚠️ 已知限制

- 目前仅针对竖屏（Portrait）进行了深度优化。
- 工具调用及智能体执行效率取决于所配置模型的原生 Tool 支持能力及老旧硬件性能。
- 无云端同步功能，所有配置与聊天记录均为本地存储。

---

## English

**Legacy-Chatbox (Agentic Edition)** is a lightweight AI chat client and native agent execution framework designed specifically for legacy iOS devices. Building upon standard OpenAI-compatible provider support, this version **deeply integrates Google's native API endpoints and a lightweight native Tool Calling framework**, introducing full Agentic Harness capabilities to iOS 6 hardware.

---

### 📌 Key Features

- **Google Native API Integration**: Direct communication with Google's generative AI API endpoints.
- **Native Tool Calling Framework**: Runs a lightweight Agentic Harness on iOS 6, empowering models to dynamically invoke tools and execute tasks.
- **Multi-Provider Profiles**: Easily configure, save, and switch between Google API and OpenAI-compatible endpoints.
- **Editable System Prompt**: Customize or clear the runtime system prompt sent prior to requests.
- **Local Secure Storage**: All conversation history and API keys remain strictly local on device.
- **Streaming & Reasoning Display**: SSE streaming support with dynamic reasoning/thinking display and collapsing.
- **Authentic iOS 6 Interface**: Meticulously styled with classic UIKit elements, navigation bars, buttons, launch images, and app icons tailored for retro Apple hardware.

---

### 📱 Supported Devices

- **iPhone 4 / 4S** (iOS 6, Portrait)
- **iPhone 5** (iOS 6, Portrait)
- **iPad 4** (iOS 6, Portrait)

---

### 📦 Build & Installation

This project utilizes the **Theos** build pipeline for jailbroken iOS packages:

1. Ensure Theos is installed on your development environment.
2. Navigate to the app directory:
   ```sh
   cd theos/LegacyChatApp
   ```
3. Build the package:
   ```sh
   make package FINALPACKAGE=1
   ```
4. Locate the generated `.deb` file in `theos/LegacyChatApp/packages/` and install it onto your jailbroken iOS 6 device.

---

### ⚙️ Configuration Guide

Open **`Settings > Model Configurations`** on your device to add your provider profile:

- **Base URL**: The API root endpoint address.
- **Chat Path**: The API endpoint path.
- **Model**: Exact model identifier.
- **API Key**: Your API credential (stored locally).
- **Tool Calling**: Enable and configure native tool-calling parameters.

---

### 🤝 Acknowledgments & Credits

This project builds upon the foundational work of talented community developers:

- **Original Creator**: [BagXML](https://github.com/BagXML) — For creating the brilliant foundational legacy iOS AI client repository.
- **Intermediate Fork Developer**: Li Xiang — For the intermediate modifications and codebase used as a solid starting point for this enhanced edition.

---

### ⚠️ Known Limitations

- Optimized for portrait orientation only.
- Tool calling and agent execution performance depend on model tool-use capabilities and legacy hardware constraints.
- No cloud synchronization; all provider settings and chat histories are stored locally.
