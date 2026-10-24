import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'chat_service.dart';

class _Message {
  const _Message(this.text, {required this.fromUser, this.isError = false});
  final String text;
  final bool fromUser;
  final bool isError;
}

/// 12500 -> "12,500"
String _naira(int amount) {
  final digits = amount.abs().toString();
  final grouped = digits.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return '₦${amount < 0 ? '-' : ''}$grouped';
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.service});
  final ChatService service;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _recorder = AudioRecorder();
  final _tts = FlutterTts();
  final _messages = <_Message>[
    const _Message("Hi! What would you like to eat today?", fromUser: false),
  ];

  Checkout? _checkout;
  bool _busy = false;
  bool _recording = false;
  bool _speakReplies = true;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _tts.stop();
    // Stop any in-progress recording before releasing the recorder.
    _recorder.stop().whenComplete(_recorder.dispose);
    super.dispose();
  }

  Future<void> _handle(Future<BotReply> Function() call, {String? echo}) async {
    setState(() {
      _busy = true;
      if (echo != null) _messages.add(_Message(echo, fromUser: true));
    });
    _scrollToEnd();

    try {
      final reply = await call();
      if (!mounted) return;
      setState(() {
        if (reply.transcript != null) {
          _messages.add(_Message(reply.transcript!, fromUser: true));
        }
        _messages.add(_Message(reply.reply, fromUser: false));
        _checkout = reply.checkout;
      });
      await _speak(reply.reply);
    } on ChatException catch (e) {
      _addError(e.message);
    } catch (_) {
      _addError('Something went wrong. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _scrollToEnd();
      }
    }
  }

  /// TTS problems must never be reported as network errors.
  Future<void> _speak(String text) async {
    if (!_speakReplies || !mounted) return;
    try {
      await _tts.speak(text);
    } catch (_) {
      // Ignore: speech is optional.
    }
  }

  void _addError(String text) {
    if (!mounted) return;
    setState(
      () => _messages.add(_Message(text, fromUser: false, isError: true)),
    );
  }

  Future<void> _sendText() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy || _recording) return;
    _input.clear();
    await _handle(() => widget.service.sendText(text), echo: text);
  }

  Future<void> _toggleRecording() async {
    if (_busy) return;

    if (_recording) {
      String? path;
      try {
        path = await _recorder.stop();
      } catch (_) {
        _addError('Could not finish the recording. Please try again.');
      }
      if (!mounted) return;
      setState(() => _recording = false);
      if (path != null) {
        final recordedPath = path;
        try {
          await _handle(() => widget.service.sendVoice(recordedPath));
        } finally {
          _deleteQuietly(recordedPath);
        }
      }
      return;
    }

    try {
      if (!await _recorder.hasPermission()) {
        _addError('Microphone permission is needed to order by voice.');
        return;
      }
      await _tts.stop();
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/order_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      if (!mounted) return;
      setState(() => _recording = true);
    } catch (_) {
      _addError('Could not start recording. Please try again.');
    }
  }

  void _deleteQuietly(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }

  Future<void> _confirmOrder() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final orderId = await widget.service.confirmOrder();
      if (!mounted) return;
      setState(() {
        _checkout = null;
        _messages.add(
          _Message('Order $orderId placed. Thank you!', fromUser: false),
        );
      });
      _scrollToEnd();
    } on ChatException catch (e) {
      _addError(e.message);
    } catch (_) {
      _addError('Could not place the order. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Foodrive Assistant'),
        actions: [
          IconButton(
            tooltip: _speakReplies ? 'Mute replies' : 'Speak replies',
            icon: Icon(_speakReplies ? Icons.volume_up : Icons.volume_off),
            onPressed: () {
              setState(() => _speakReplies = !_speakReplies);
              if (!_speakReplies) _tts.stop();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (_, i) => _Bubble(message: _messages[i]),
            ),
          ),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          if (_checkout != null)
            _CheckoutCard(
              checkout: _checkout!,
              busy: _busy,
              onConfirm: _confirmOrder,
            ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    final canSend = !_busy && !_recording;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Row(
          children: [
            IconButton.filledTonal(
              tooltip: _recording ? 'Stop and send' : 'Speak',
              isSelected: _recording,
              icon: const Icon(Icons.mic),
              selectedIcon: const Icon(Icons.stop),
              onPressed: _busy ? null : _toggleRecording,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _input,
                enabled: !_recording,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendText(),
                decoration: InputDecoration(
                  hintText: _recording
                      ? 'Listening… tap stop to send'
                      : 'Type your order',
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(24)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Send',
              icon: const Icon(Icons.send),
              onPressed: canSend ? _sendText : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});
  final _Message message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = message.isError
        ? scheme.errorContainer
        : message.fromUser
        ? scheme.primaryContainer
        : scheme.surfaceContainerHighest;

    return Align(
      alignment: message.fromUser
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(16),
        ),
        child: SelectableText(message.text),
      ),
    );
  }
}

class _CheckoutCard extends StatelessWidget {
  const _CheckoutCard({
    required this.checkout,
    required this.busy,
    required this.onConfirm,
  });
  final Checkout checkout;
  final bool busy;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Confirm your order',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final l in checkout.lines)
              Text('${l.quantity} × ${l.name}  —  ${_naira(l.subtotal)}'),
            const Divider(),
            Text(
              'Total: ${_naira(checkout.total)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text('Deliver to: ${checkout.address}'),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: busy ? null : onConfirm,
                child: const Text('Confirm order'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
