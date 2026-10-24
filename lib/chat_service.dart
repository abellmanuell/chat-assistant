import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class ChatException implements Exception {
  ChatException(this.message);
  final String message;

  @override
  String toString() => message;
}

class CheckoutLine {
  CheckoutLine(this.name, this.quantity, this.subtotal);
  final String name;
  final int quantity;
  final int subtotal;
}

class Checkout {
  Checkout({required this.address, required this.lines, required this.total});
  final String address;
  final List<CheckoutLine> lines;
  final int total;

  factory Checkout.fromJson(Map<String, dynamic> j) => Checkout(
    address: (j['address'] ?? '').toString(),
    total: (j['total'] as num).toInt(),
    lines: (j['lines'] as List)
        .map(
          (l) => CheckoutLine(
            l['name'].toString(),
            (l['quantity'] as num).toInt(),
            (l['subtotal'] as num).toInt(),
          ),
        )
        .toList(),
  );
}

class BotReply {
  BotReply({required this.reply, this.transcript, this.checkout});
  final String reply;
  final String? transcript; // set only for voice messages
  final Checkout? checkout;

  factory BotReply.fromJson(Map<String, dynamic> j) => BotReply(
    reply: j['reply'].toString(),
    transcript: j['transcript'] as String?,
    checkout: j['checkout'] == null ? null : Checkout.fromJson(j['checkout']),
  );
}

class ChatService {
  ChatService({
    required this.baseUrl,
    required this.sessionId,
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// Android emulator: http://10.0.2.2:3000 | Real device: your server URL
  /// (use https in production).
  final String baseUrl;
  final String sessionId;
  final http.Client _client;

  static const _textTimeout = Duration(seconds: 30);
  static const _voiceTimeout = Duration(seconds: 60);

  Future<BotReply> sendText(String message) {
    return _guard(_textTimeout, () async {
      final response = await _client.post(
        Uri.parse('$baseUrl/api/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'sessionId': sessionId, 'message': message}),
      );
      return BotReply.fromJson(_decode(response));
    });
  }

  Future<BotReply> sendVoice(String filePath) {
    // One timeout covers the upload AND reading the response body.
    return _guard(_voiceTimeout, () async {
      final request =
          http.MultipartRequest('POST', Uri.parse('$baseUrl/api/voice'))
            ..fields['sessionId'] = sessionId
            ..files.add(await http.MultipartFile.fromPath('audio', filePath));
      final streamed = await _client.send(request);
      final response = await http.Response.fromStream(streamed);
      return BotReply.fromJson(_decode(response));
    });
  }

  /// Returns the order id.
  Future<String> confirmOrder() {
    return _guard(_textTimeout, () async {
      final response = await _client.post(
        Uri.parse('$baseUrl/api/orders/confirm'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'sessionId': sessionId}),
      );
      return _decode(response)['orderId'].toString();
    });
  }

  void dispose() => _client.close();

  /// Runs [action] with a timeout and converts low-level failures into a
  /// [ChatException] with a user-friendly message.
  Future<T> _guard<T>(Duration timeout, Future<T> Function() action) async {
    try {
      return await action().timeout(timeout);
    } on ChatException {
      rethrow;
    } on TimeoutException {
      throw ChatException('The server took too long to respond. Try again.');
    } on SocketException {
      throw ChatException(
        'Network problem. Please check your connection and try again.',
      );
    } on http.ClientException {
      throw ChatException(
        'Network problem. Please check your connection and try again.',
      );
    } on FormatException {
      throw ChatException('Unexpected response from the server.');
    } on TypeError {
      throw ChatException('Unexpected response from the server.');
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic>? body;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) body = decoded;
    } on FormatException {
      // Non-JSON body (e.g. HTML error page from a proxy). Handled below.
    }

    if (response.statusCode >= 400) {
      throw ChatException(
        body?['error'] as String? ??
            'Server error (${response.statusCode}). Please try again.',
      );
    }
    if (body == null) {
      throw ChatException('Unexpected response from the server.');
    }
    return body;
  }
}
