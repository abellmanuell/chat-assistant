import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'chat_screen.dart';
import 'chat_service.dart';

/// Android emulator -> http://10.0.2.2:3000
/// Real device on same Wi-Fi -> http://<your-computer-LAN-ip>:3000
/// Production -> https://your-server.com (plain http is blocked by default on
/// Android 9+ and iOS).
const String kAssistantBaseUrl = 'http://192.168.1.23:3000';

ChatService? _assistantService;

/// One service (and one sessionId) per app session, so reopening the assistant
/// keeps the same conversation and cart. Call [resetAssistant] on logout.
ChatService _getAssistantService() {
  return _assistantService ??= ChatService(
    baseUrl: kAssistantBaseUrl,
    sessionId: const Uuid().v4(),
  );
}

void resetAssistant() {
  _assistantService?.dispose();
  _assistantService = null;
}

void openAssistant(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ChatScreen(service: _getAssistantService()),
    ),
  );
}
