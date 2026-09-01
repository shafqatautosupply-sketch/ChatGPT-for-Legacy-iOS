# LegacyChatApp 0.1.0

LegacyChatApp is an advanced AI assistant and autonomous agent client built for legacy iOS devices (iOS 6) using Theos. It bridges classic iOS hardware with the Google Gemini API, featuring autonomous tool execution, shell command guardrails, thinking/reasoning configuration, and lightweight Markdown support.

## Supported Devices

- iPhone 4 / 4S (iOS 6, 3.5-inch portrait)
- iPhone 5 (iOS 6, 4-inch portrait)
- iPad 4 (iOS 6, portrait)

## Main Features

- **Google Gemini API Integration**: Native support for Gemini model endpoints, system instructions, and `x-goog-api-key` authorization.
- **Autonomous Agent Mode**: Multi-turn agent loop supporting tool execution (`runShellCommand`, `writeFile`).
- **Safety Guardrails**: Strict whitelist for binaries (`make`, `git`, `clang`, `cc`, `c++`, `dpkg-deb`, `ldid`, `echo`, `cat`, `ls`, `cp`, `mv`, `mkdir`, `rm`) scoped securely within the workspace/Theos directory.
- **High Reasoning Support**: Configured with `thinkingLevel: "HIGH"` for enhanced problem solving.
- **Local Conversation History**: Persistent local chat storage.
- **Lightweight Markdown**: Clean readability for code snippets, headers, and text formatting.

## Build

```sh
make package FINALPACKAGE=1
```

Install the generated `.deb` package from `packages/` onto a jailbroken iOS 6 device.

## Provider Setup

Open **Settings > Model Configurations** to enter your Google Gemini API key and configure model options.

## System Prompt

Open **Settings > System Prompt** to customize or view the system instructions sent with requests.
