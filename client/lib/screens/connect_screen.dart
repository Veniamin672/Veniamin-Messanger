import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../services/connection.dart';
import '../services/device_id.dart';

class ConnectScreen extends StatefulWidget {
  final ConnectionService connection;
  const ConnectScreen({super.key, required this.connection});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _hostCtrl = TextEditingController(text: '127.0.0.1');
  final _portCtrl = TextEditingController(text: '8765');
  final _nameCtrl = TextEditingController();
  final _accountCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  List<KnownAccount> _known = [];
  String? _selectedKnownId;

  @override
  void initState() {
    super.initState();
    _reloadKnown();
  }

  Future<void> _reloadKnown() async {
    await DeviceId.loadAccountId();
    await DeviceId.loadLastServer();
    if (!mounted) return;
    setState(() {
      _known = List.from(DeviceId.knownAccounts);
      _selectedKnownId = DeviceId.accountId;
      if (_selectedKnownId != null) {
        _accountCtrl.text = _selectedKnownId!;
      }
      if (DeviceId.lastServerHost != null &&
          DeviceId.lastServerHost!.isNotEmpty) {
        _hostCtrl.text = DeviceId.lastServerHost!;
      }
      if (DeviceId.lastServerPort != null) {
        _portCtrl.text = '${DeviceId.lastServerPort}';
      }
      if (_nameCtrl.text.isEmpty &&
          DeviceId.lastDisplayName != null &&
          DeviceId.lastDisplayName!.isNotEmpty) {
        _nameCtrl.text = DeviceId.lastDisplayName!;
      }
    });
  }

  Future<void> _connectLast() async {
    await DeviceId.loadLastServer();
    final host = DeviceId.lastServerHost;
    if (host == null || host.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'нет сохранённого сервера — подключись один раз вручную'),
          backgroundColor: VColors.surface,
        ),
      );
      return;
    }
    setState(() {
      _hostCtrl.text = host;
      _portCtrl.text = '${DeviceId.lastServerPort ?? 8765}';
      if (DeviceId.lastDisplayName != null &&
          DeviceId.lastDisplayName!.isNotEmpty &&
          _nameCtrl.text.trim().isEmpty) {
        _nameCtrl.text = DeviceId.lastDisplayName!;
      }
    });
    await _connect();
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _nameCtrl.dispose();
    _accountCtrl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (!_formKey.currentState!.validate()) return;
    final port = int.tryParse(_portCtrl.text) ?? 8765;
    final aid = _accountCtrl.text.trim();
    await widget.connection.connect(
      _hostCtrl.text,
      port: port,
      name: _nameCtrl.text,
      accountId: aid.isEmpty ? null : aid,
    );
  }

  Future<void> _useKnown(KnownAccount a) async {
    setState(() {
      _selectedKnownId = a.id;
      _accountCtrl.text = a.id;
      if (a.label.isNotEmpty && a.label != 'аккаунт') {
        _nameCtrl.text = a.label;
      }
    });
    await DeviceId.saveAccountId(a.id, label: a.label);
  }

  Future<void> _newAccount() async {
    await DeviceId.clearActiveAccount();
    setState(() {
      _selectedKnownId = null;
      _accountCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final conn = widget.connection;
    final isBusy = conn.state == ConnState.connecting ||
        conn.state == ConnState.connected ||
        conn.state == ConnState.pending;

    final myAccount = conn.me?.accountId;

    // refresh known when authenticated with new id
    if (myAccount != null &&
        myAccount.isNotEmpty &&
        !_known.any((a) => a.id == myAccount)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reloadKnown());
    }

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: 24 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 48,
                  maxWidth: 420,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'VENIAMIN',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              letterSpacing: 4,
                              fontSize: 28,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'closed group messenger',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 20),
                      _InfoLine(
                        label: 'device_uuid',
                        value: DeviceId.uuid,
                        copyable: true,
                      ),
                      if (myAccount != null) ...[
                        const SizedBox(height: 8),
                        _InfoLine(
                          label: 'account_id',
                          value: myAccount,
                          copyable: true,
                        ),
                      ],
                      const SizedBox(height: 16),

                      // Known accounts switcher
                      if (_known.isNotEmpty) ...[
                        const Text(
                          'СМЕНА АККАУНТА',
                          style: TextStyle(
                            color: VColors.dim,
                            fontSize: 11,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ..._known.map((a) {
                          final selected = a.id == _selectedKnownId;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Material(
                              color: selected
                                  ? VColors.green.withValues(alpha: 0.12)
                                  : VColors.surface,
                              borderRadius: BorderRadius.circular(4),
                              child: InkWell(
                                onTap: isBusy ? null : () => _useKnown(a),
                                borderRadius: BorderRadius.circular(4),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: selected
                                          ? VColors.green
                                          : VColors.border,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        selected
                                            ? Icons.radio_button_checked
                                            : Icons.radio_button_off,
                                        size: 16,
                                        color: selected
                                            ? VColors.green
                                            : VColors.dim,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              a.label.isNotEmpty
                                                  ? a.label
                                                  : 'аккаунт',
                                              style: TextStyle(
                                                color: selected
                                                    ? VColors.green
                                                    : VColors.text,
                                                fontSize: 13,
                                              ),
                                            ),
                                            Text(
                                              a.id.length > 12
                                                  ? '${a.id.substring(0, 12)}…'
                                                  : a.id,
                                              style: const TextStyle(
                                                color: VColors.dim,
                                                fontSize: 10,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline,
                                            size: 16, color: VColors.dim),
                                        onPressed: isBusy
                                            ? null
                                            : () async {
                                                await DeviceId.removeKnown(
                                                    a.id);
                                                await _reloadKnown();
                                              },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                        TextButton.icon(
                          onPressed: isBusy ? null : _newAccount,
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('новый / другой account_id'),
                          style: TextButton.styleFrom(
                            foregroundColor: VColors.blue,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _hostCtrl,
                              enabled: !isBusy,
                              decoration: const InputDecoration(
                                labelText: 'server IP / host',
                                prefixIcon: Icon(Icons.dns_outlined,
                                    size: 18, color: VColors.dim),
                              ),
                              style: const TextStyle(
                                  fontFamily: 'JetBrains Mono'),
                              validator: (v) =>
                                  (v == null || v.trim().isEmpty)
                                      ? 'required'
                                      : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: IconButton(
                              tooltip: DeviceId.lastServerHost == null
                                  ? 'нет сохранённого сервера'
                                  : 'последний: ${DeviceId.lastServerHost}:${DeviceId.lastServerPort ?? 8765}',
                              onPressed: isBusy ? null : _connectLast,
                              style: IconButton.styleFrom(
                                backgroundColor: VColors.surface,
                                side: const BorderSide(color: VColors.border),
                              ),
                              icon: const Icon(Icons.history,
                                  color: VColors.green, size: 22),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _portCtrl,
                        enabled: !isBusy,
                        decoration: const InputDecoration(
                          labelText: 'port',
                          prefixIcon: Icon(Icons.numbers,
                              size: 18, color: VColors.dim),
                        ),
                        keyboardType: TextInputType.number,
                        style: const TextStyle(fontFamily: 'JetBrains Mono'),
                        validator: (v) {
                          final p = int.tryParse(v ?? '');
                          if (p == null || p < 1 || p > 65535) {
                            return 'invalid port';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _nameCtrl,
                        enabled: !isBusy,
                        decoration: const InputDecoration(
                          labelText: 'display name',
                          prefixIcon: Icon(Icons.person_outline,
                              size: 18, color: VColors.dim),
                        ),
                        style: const TextStyle(fontFamily: 'JetBrains Mono'),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'required' : null,
                        maxLength: 32,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _accountCtrl,
                        enabled: !isBusy,
                        decoration: const InputDecoration(
                          labelText: 'account id (optional)',
                          hintText: 'пусто = этот device как новый',
                          prefixIcon:
                              Icon(Icons.link, size: 18, color: VColors.dim),
                        ),
                        style: const TextStyle(fontFamily: 'JetBrains Mono'),
                        onChanged: (_) => setState(() {
                          _selectedKnownId = null;
                        }),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Выбери сохранённый аккаунт выше или вставь account_id. '
                        'Пустое поле — вход как новое устройство/аккаунт.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 20),
                      _StatusBox(conn: conn),
                      const SizedBox(height: 16),
                      if (conn.state == ConnState.disconnected ||
                          conn.state == ConnState.error ||
                          conn.state == ConnState.rejected) ...[
                        ElevatedButton(
                          onPressed: _connect,
                          child: const Text('> connect'),
                        ),
                        if (DeviceId.lastServerHost != null &&
                            DeviceId.lastServerHost!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _connectLast,
                            icon: const Icon(Icons.history, size: 16),
                            label: Text(
                              'последний сервер  ${DeviceId.lastServerHost}:${DeviceId.lastServerPort ?? 8765}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ]
                      else if (conn.state == ConnState.pending)
                        OutlinedButton(
                          onPressed: () => conn.disconnect(),
                          child: const Text('cancel / disconnect'),
                        )
                      else if (conn.state == ConnState.connecting) ...[
                        const Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: VColors.green,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: () => conn.disconnect(),
                          child: const Text('cancel / disconnect'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final String label;
  final String value;
  final bool copyable;
  const _InfoLine(
      {required this.label, required this.value, this.copyable = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: VColors.surface,
        border: Border.all(color: VColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: const TextStyle(color: VColors.dim, fontSize: 12),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: VColors.blue, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (copyable)
            IconButton(
              icon: const Icon(Icons.copy, size: 14, color: VColors.dim),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('copied'),
                    duration: Duration(seconds: 1),
                    backgroundColor: VColors.surface,
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _StatusBox extends StatelessWidget {
  final ConnectionService conn;
  const _StatusBox({required this.conn});

  @override
  Widget build(BuildContext context) {
    String text;
    Color color;
    switch (conn.state) {
      case ConnState.disconnected:
        text = 'status: offline';
        color = VColors.dim;
        break;
      case ConnState.connecting:
        text = DeviceId.wantAutoConnect
            ? 'status: автоподключение…'
            : 'status: connecting…';
        color = VColors.yellow;
        break;
      case ConnState.connected:
        text = 'status: handshake ok, requesting access…';
        color = VColors.blue;
        break;
      case ConnState.pending:
        text = 'status: waiting for admin approval';
        color = VColors.yellow;
        break;
      case ConnState.authenticated:
        text = 'status: authenticated';
        color = VColors.green;
        break;
      case ConnState.rejected:
        text = 'status: access denied';
        color = VColors.red;
        break;
      case ConnState.error:
        text = 'status: error — ${conn.errorMessage ?? "unknown"}';
        color = VColors.red;
        break;
    }
    return Text(
      text,
      style: TextStyle(color: color, fontSize: 12),
      textAlign: TextAlign.center,
    );
  }
}
