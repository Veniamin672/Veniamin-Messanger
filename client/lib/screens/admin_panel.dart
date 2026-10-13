import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../theme.dart';
import '../services/connection.dart';

class AdminPanel extends StatefulWidget {
  final ConnectionService connection;
  const AdminPanel({super.key, required this.connection});

  @override
  State<AdminPanel> createState() => _AdminPanelState();
}

class _AdminPanelState extends State<AdminPanel> {
  final _broadcastCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  ConnectionService get conn => widget.connection;

  @override
  void initState() {
    super.initState();
    conn.addListener(_refresh);
    conn.adminListPending();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    conn.removeListener(_refresh);
    _broadcastCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _sendBroadcast() {
    final t = _broadcastCtrl.text.trim();
    if (t.isEmpty) return;
    conn.adminBroadcast(t);
    _broadcastCtrl.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('broadcast sent'),
        backgroundColor: VColors.surface,
      ),
    );
  }

  void _resetMessages() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: VColors.surface,
        title: const Text('Сброс всех сообщений'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Удалит ВСЕ сообщения и файлы у всех. Введите пароль:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordCtrl,
              obscureText: true,
              decoration: const InputDecoration(hintText: 'password'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('отмена'),
          ),
          TextButton(
            onPressed: () {
              conn.adminResetMessages(_passwordCtrl.text);
              _passwordCtrl.clear();
              Navigator.pop(context);
            },
            child: const Text('СБРОСИТЬ', style: TextStyle(color: VColors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ADMIN PANEL'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Broadcast
          const Text(
            'SYSTEM BROADCAST',
            style: TextStyle(color: VColors.dim, fontSize: 11, letterSpacing: 1.5),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _broadcastCtrl,
                  decoration: const InputDecoration(
                    hintText: 'сообщение всем…',
                  ),
                  maxLines: 2,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _sendBroadcast,
                child: const Text('send'),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Reset
          const Text(
            'DANGER ZONE',
            style: TextStyle(color: VColors.red, fontSize: 11, letterSpacing: 1.5),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _resetMessages,
            style: OutlinedButton.styleFrom(
              foregroundColor: VColors.red,
              side: const BorderSide(color: VColors.red),
            ),
            child: const Text('полный сброс сообщений (пароль)'),
          ),
          const SizedBox(height: 32),

          // Pending
          const Text(
            'PENDING REQUESTS',
            style: TextStyle(color: VColors.dim, fontSize: 11, letterSpacing: 1.5),
          ),
          const SizedBox(height: 8),
          if (conn.pending.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'no pending requests',
                style: TextStyle(color: VColors.dim),
                textAlign: TextAlign.center,
              ),
            )
          else
            ...conn.pending.map((p) => _PendingCard(
                  pending: p,
                  onAccept: () => conn.adminAccept(p.uuid),
                  onReject: () => conn.adminReject(p.uuid),
                )),
          const SizedBox(height: 32),

          // Users
          const Text(
            'ALL USERS',
            style: TextStyle(color: VColors.dim, fontSize: 11, letterSpacing: 1.5),
          ),
          const SizedBox(height: 8),
          ...conn.users.map((u) {
            final aid = u.accountId ?? u.uuid;
            return ListTile(
              dense: true,
              leading: Icon(
                u.online ? Icons.circle : Icons.circle_outlined,
                size: 12,
                color: u.online ? VColors.green : VColors.dim,
              ),
              title: Text(u.displayName),
              subtitle: Text(
                '${u.role} · account ${aid.length > 8 ? '${aid.substring(0, 8)}…' : aid}',
                style: const TextStyle(fontSize: 11, color: VColors.dim),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.copy, size: 16, color: VColors.dim),
                    tooltip: 'copy account_id',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: aid));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'account_id скопирован.\n'
                            'Осторожно, ни с кем не делитесь этим account_id — '
                            'благодаря нему можно зайти на аккаунт.',
                          ),
                          duration: Duration(seconds: 5),
                          backgroundColor: VColors.surface,
                        ),
                      );
                    },
                  ),
                  if (u.role != 'admin')
                    TextButton(
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (_) => AlertDialog(
                            backgroundColor: VColors.surface,
                            title: const Text('Kick user?'),
                            content: Text('Remove ${u.displayName}?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('cancel'),
                              ),
                              TextButton(
                                onPressed: () {
                                  conn.adminKick(u.uuid);
                                  Navigator.pop(context);
                                },
                                child: const Text('kick',
                                    style: TextStyle(color: VColors.red)),
                              ),
                            ],
                          ),
                        );
                      },
                      child: const Text('kick',
                          style: TextStyle(color: VColors.red, fontSize: 12)),
                    )
                  else
                    const Text('admin',
                        style: TextStyle(color: VColors.purple, fontSize: 11)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _PendingCard extends StatelessWidget {
  final PendingUser pending;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  const _PendingCard({
    required this.pending,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('dd.MM HH:mm').format(
      DateTime.fromMillisecondsSinceEpoch(pending.requestedAt),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: VColors.surface,
        border: Border.all(color: VColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            pending.displayName,
            style: const TextStyle(
                fontWeight: FontWeight.w600, color: VColors.yellow),
          ),
          const SizedBox(height: 4),
          Text(
            'uuid: ${pending.uuid}',
            style: const TextStyle(fontSize: 11, color: VColors.dim),
          ),
          Text(
            'requested: $time',
            style: const TextStyle(fontSize: 11, color: VColors.dim),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              ElevatedButton(
                onPressed: onAccept,
                style: ElevatedButton.styleFrom(
                  backgroundColor: VColors.green,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                child: const Text('accept'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: onReject,
                style: OutlinedButton.styleFrom(
                  foregroundColor: VColors.red,
                  side: const BorderSide(color: VColors.red),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                child: const Text('reject'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
