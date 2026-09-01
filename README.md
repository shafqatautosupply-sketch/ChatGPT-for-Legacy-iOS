# Legacy-Chatbox (Agentic Edition)

[中文](#中文) | [English](#english)

## 中文

Legacy-Chatbox (Agentic Edition) 是一个面向旧 iOS 设备的轻量 AI 聊天客户端与智能体框架。当前版本在支持 OpenAI 兼容接口的基础上，**深度集成了 Google 原生 API 端点以及原生 Tool Calling（工具调用）框架**，在 iOS 6 时代设备上实现了完整的轻量 Agentic Harness（智能体运行环境）。

### 状态

当前版本基于 Theos 构建流程，带有增强的 Google API 与工具调用支持。

原始 Xcode 工程仍保留在仓库中作为参考，当前活跃发布版本位于：

```sh
theos/LegacyChatApp
```

### 支持设备

- iPhone 4 / 4S，iOS 6，竖屏
- iPhone 5，iOS 6，竖屏
- iPad 4，iOS 6，竖屏

### 核心功能

- **Google 原生 API 端点支持**：直接对接 Google 强大的生成式 AI API 接口。
- **原生 Tool Calling（工具调用）框架**：在 iOS 6 设备上运行轻量 Agentic Harness，支持模型动态调用工具与执行任务。
- **多 Provider 配置**：支持 Google API 及 OpenAI-compatible provider 配置、保存与快速切换。
- **系统提示词 (System Prompt)**：可自由编辑或清空每次请求前发送的 system prompt。
- **本地会话历史**：所有聊天记录与配置完全保存在本地设备上。
- **流式输出与思考过程展示**：支持 SSE 流式传输，并带有 reasoning / thinking 临时显示与折叠。
- **iOS 6 经典界面**：高度复刻 iOS 6 风格的导航栏、按钮、启动图和应用图标，完美适配复古设备审美。

### 构建与安装

安装 Theos 后，在 app 目录中构建：

```sh
cd theos/LegacyChatApp
make package FINALPACKAGE=1
```

生成的 `.deb` 文件位于：

```sh
theos/LegacyChatApp/packages/
```

请将 `.deb` 安装到已越狱的 iOS 6 设备上。

### Provider 与 Tool Calling 配置

在设备上打开 `Settings > Model Configurations` 并添加 provider：

- **Base URL**：填写服务根地址（例如 Google API 或兼容网关）。
- **Chat Path**：填写接口路径。
- **Model**：填写准确的模型名称。
- **API Key**：保存在本机设备上。
- **Tool Calling**：配置并启用原生工具调用框架相关参数。

### 致谢与鸣谢

- **主仓库原作者**：[BagXML](https://github.com/BagXML)，感谢其创建了优秀的旧 iOS 设备 AI 客户端基础项目。
- **中间分支开发者**：Li Xiang，感谢其在此基础上的修改与中间分支代码，作为本项目二次开发的起点。

### 已知限制

- 目前仅支持竖屏。
- 工具调用及 Agent 执行依赖于所配置模型的原生 tool support 与设备性能。
- 无云同步，所有数据仅存储于本地。

---

## English

Legacy-Chatbox (Agentic Edition) is a lightweight AI chat client and agent framework for legacy iOS devices. Building upon OpenAI-compatible provider support, this version **deeply integrates the Google native API endpoint and a native Tool Calling framework**, bringing a full-blown lightweight Agentic Harness to iOS 6-era hardware.

### Status

This version is built using the Theos build pipeline with enhanced Google API and agentic tool-calling capabilities.

The original Xcode project remains in this repository for reference, but active release work lives in:

```sh
theos/LegacyChatApp
```

### Supported Devices

- iPhone 4 / 4S on iOS 6, portrait
- iPhone 5 on iOS 6, portrait
- iPad 4 on iOS 6, portrait

### Key Features

- **Google Native API Endpoint Integration**: Direct communication with Google's generative AI API endpoints.
- **Native Tool Calling Framework**: A lightweight Agentic Harness running on iOS 6, enabling models to perform tool-use and execute tasks dynamically.
- **Multi-Provider Profiles**: Configure, save, and switch between Google API and OpenAI-compatible providers.
- **Editable System Prompt**: Customize or clear the system prompt sent before requests.
- **Local Conversation History**: All data and history remain strictly local on device.
- **Streamed Output & Thinking Display**: SSE streaming support with temporary reasoning/thinking display and replacement.
- **Classic iOS 6 UI**: Authentic iOS 6 styling including navigation bars, buttons, launch images, and app icons tailored for retro Apple hardware.

### Build & Installation

Install Theos, then build from the app directory:

```sh
cd theos/LegacyChatApp
make package FINALPACKAGE=1
```

The generated `.deb` package will be placed in:

```sh
theos/LegacyChatApp/packages/
```

Install the package on a jailbroken iOS 6 device.

### Provider & Tool Calling Setup

Open `Settings > Model Configurations` on device and add your provider:

- **Base URL**: Enter the root endpoint address (e.g., for Google API or compatible proxies).
- **Chat Path**: Enter the API endpoint path.
- **Model**: Enter the exact model name.
- **API Key**: Stored securely on device.
- **Tool Calling**: Configure and enable the native tool-calling framework parameters.

### Acknowledgments & Credits

- **Original Project Creator**: [BagXML](https://github.com/BagXML) for creating the foundational legacy iOS AI client repository.
- **Intermediate Fork Developer**: Li Xiang, for the intermediate modifications and codebase used as a starting point for this enhanced version.

### Known Limitations

- Optimized for portrait orientation only.
- Tool calling and agent execution performance depend on model capabilities and legacy hardware limits.
- No cloud sync; all provider configurations and conversation history are stored locally.
