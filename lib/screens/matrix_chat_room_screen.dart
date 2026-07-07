import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../theme/brutal_theme.dart';
import '../widgets/brutal.dart';

class MatrixChatRoomScreen extends StatefulWidget {
  final Room room;
  final Map user;

  const MatrixChatRoomScreen({
    super.key,
    required this.room,
    required this.user,
  });

  @override
  State<MatrixChatRoomScreen> createState() => _MatrixChatRoomScreenState();
}

class _MatrixChatRoomScreenState extends State<MatrixChatRoomScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  Timeline? _timeline;

  @override
  void initState() {
    super.initState();
    widget.room
        .getTimeline(onUpdate: () {
          if (mounted) setState(() {});
          _scrollToBottom();
        })
        .then((t) {
      if (mounted) setState(() => _timeline = t);
      _scrollToBottom();
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _timeline?.cancelSubscriptions();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    await widget.room.sendTextEvent(text);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final myId = widget.room.client.userID;
    final title = widget.room.getLocalizedDisplayname();
    final encrypted = widget.room.encrypted;
    final timeline = _timeline;
    final messages = timeline?.events
            .where((e) => e.type == EventTypes.Message)
            .toList() ??
        [];

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16)),
            if (encrypted)
              Text(
                'End-to-end encrypted',
                style: TextStyle(fontSize: 11, color: c.accent),
              ),
          ],
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: c.ink),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: timeline == null
                ? const Center(child: CircularProgressIndicator())
                : messages.isEmpty
                    ? Center(
                        child: Text(
                          'No messages yet.\nSay hello.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: c.inkSoft),
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                        itemCount: messages.length,
                        itemBuilder: (_, i) {
                          final e = messages[i];
                          final mine = e.senderId == myId;
                          return _Bubble(event: e, mine: mine);
                        },
                      ),
          ),
          Divider(height: 1, color: c.ink.withOpacity(0.08)),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'Message',
                        filled: true,
                        fillColor: c.surface2,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  BrutalTap(
                    fill: c.accent,
                    radius: 22,
                    padding: const EdgeInsets.all(12),
                    onTap: _send,
                    child: Icon(Icons.send_rounded, color: c.onAccent, size: 22),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final Event event;
  final bool mine;

  const _Bubble({required this.event, required this.mine});

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final time = TimeOfDay.fromDateTime(event.originServerTs).format(context);
    final pending = !event.status.isSent;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: mine ? c.accent : c.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(mine ? 18 : 4),
            bottomRight: Radius.circular(mine ? 4 : 18),
          ),
          boxShadow: [
            BoxShadow(
              color: c.shadow.withOpacity(0.12),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Opacity(
              opacity: pending ? 0.6 : 1,
              child: Text(
                event.body,
                style: TextStyle(
                  color: mine ? c.onAccent : c.ink,
                  fontSize: 15,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              pending ? 'Sending…' : time,
              style: TextStyle(
                fontSize: 10,
                color: (mine ? c.onAccent : c.inkSoft).withOpacity(0.75),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
