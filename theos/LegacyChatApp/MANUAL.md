# LegacyChatApp / Legacy-Chatbox — User Manual

Welcome to **LegacyChatApp**, an AI assistant and autonomous agent designed to bring modern artificial intelligence and developer tools to classic iOS devices (running **iOS 6** on devices like the iPhone 4, iPhone 4S, iPhone 5, and iPad 4).

This guide explains how to use the app and what each setting does in simple, everyday language.

---

## Table of Contents
1. [Getting Started](#1-getting-started)
2. [Setting Up Your API Key](#2-setting-up-your-api-key)
3. [Chat Modes (Standard Chat vs. Agent Mode)](#3-chat-modes-standard-chat-vs-agent-mode)
4. [Understanding the Settings](#4-understanding-the-settings)
   - [Model Configurations](#model-configurations)
   - [System Prompt](#system-prompt)
   - [Chat & Message Limits](#chat--message-limits)
   - [Agent Guardrails & Obfuscation Blocks](#agent-guardrails--obfuscation-blocks) *(Deprecated)*
5. [Frequently Asked Questions (FAQ)](#5-frequently-asked-questions-FAQ)

---

## 1. Getting Started
When you open LegacyChatApp on your jailbroken iOS 6 device, you will see a clean, classic interface modeled after traditional Apple design. 
- **Send Messages**: Type your message in the bottom input bar and tap **Send**.
- **Sidebar Menu**: Tap the menu button to view your local conversation history, start a new chat, or access **Settings**.

---

## 2. Setting Up Your API Key
To chat with AI or run agent tasks, the app needs to connect to Google Gemini.
1. Tap **Settings** in the sidebar.
2. Select **Model Configurations**.
3. Enter your **API Key** (you can get a free key from Google AI Studio).
4. Save your profile. Your key is stored securely and strictly on your device—it is never sent anywhere else.

---

## 3. Chat Modes (Standard Chat vs. Agent Mode)
The app features two distinct ways to interact with the AI:
- **Pure Chat Mode**: Standard conversation mode. The AI answers your questions directly, writes text, and chats without executing any actions on your device.
- **Agent Mode**: Advanced autonomous mode. In this mode, the AI can use built-in tools (like running safe terminal commands or writing code files in your workspace) to accomplish complex tasks for you.

---

## 4. Understanding the Settings

### Model Configurations
- **Provider Name**: A friendly label for your AI service (e.g., "Google Gemini").
- **Base URL**: The server address for the API (default: `https://generativelanguage.googleapis.com`).
- **Model Name**: The specific version of the AI model you want to use (e.g., `gemini-2.5-flash`).
- **API Key**: Your secret key used to authenticate your requests.

### System Prompt
- **What it does**: Allows you to customize the personality and instructions given to the AI before every conversation starts. 
- **Default instruction**: Tells the AI to be concise, helpful, and direct on legacy iOS hardware. You can customize or clear this anytime.

### Chat & Message Limits
- **Loaded Message Limit**: Controls how many recent messages are displayed in your chat view to keep the app fast and save memory on older devices (default is 30).
- **Saved Message Limit**: Controls how many messages are saved per conversation file.
- **Auto-Compression**: Automatically summarizes older chat history into a brief archive when conversations get very long, saving memory and preventing quota limits.

### Agent Guardrails & Obfuscation Blocks *(Deprecated)*
The app features a built-in, highly robust security logic to ensure your device remains safe during Agent tasks. 
- **Obfuscation Blocks Setting**: This old text-matching settings field is **deprecated**. Because the app now handles command filtering and safety checks automatically through its updated native command logic, **you do not need to use this setting—leave it blank**.

---

## 5. Frequently Asked Questions (FAQ)

**Q: Why do I see a network error?**  
A: Check that your Wi-Fi or cellular connection is working, and verify that your API key is correct and has not exceeded its usage quota.

**Q: Are my chats sent to the cloud?**  
A: No! All your conversation histories and API keys remain completely private and stored locally on your device.

**Q: Can I use this on non-jailbroken devices?**  
A: No, LegacyChatApp requires a jailbroken iOS 6 device with Theos support and vendored SSL libraries to handle modern HTTPS secure connections.
