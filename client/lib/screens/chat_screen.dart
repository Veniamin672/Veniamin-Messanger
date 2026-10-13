import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../theme.dart';
import '../services/connection.dart';
import '../services/device_id.dart';
import '../services/local_labels.dart';
import 'admin_panel.dart';
import 'call_screen.dart';

class ChatScreen extends StatefulWidget {
  final ConnectionService connection;
  const ChatScreen({super.key, required this.connection});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _showSidebar = true;
  ChatMessage? _replyTo;
  String? _highlightId;
  final Map<String, GlobalKey> _msgKeys = {};

  ConnectionService get conn => widget.connection;

  @override
  void initState() {
    super.initState();
    conn.addListener(_onUpdate);
  }

  void _onUpdate() {
    if (mounted) {
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(
            _scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    conn.removeListener(_onUpdate);
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _send() {
    final text = _inputCtrl.text;
    if (text.trim().isEmpty) return;
    MessageReply? reply;
    final r = _replyTo;
    if (r != null) {
      final preview = r.msgType == 'text'
          ? (r.text ?? '')
          : (r.filename ?? r.msgType);
      reply = MessageReply(
        id: r.id,
        fromName: r.fromName,
        text: preview.length > 120 ? '${preview.substring(0, 120)}…' : preview,
        msgType: r.msgType,
      );
    }
    conn.sendMessage(text, replyTo: reply);
    _inputCtrl.clear();
    setState(() => _replyTo = null);
    conn.sendTyping(false);
  }

  void _setReply(ChatMessage m) {
    if (m.msgType == 'system' || m.msgType == 'date') return;
    setState(() => _replyTo = m);
  }

  String _userLabel(UserInfo u) => LocalLabels.userNameFor(
        uuid: u.uuid,
        accountId: u.accountId,
        fallback: u.displayName,
      );

  String _userLabelMsg(ChatMessage m) => LocalLabels.userNameFor(
        uuid: m.fromUuid,
        accountId: null,
        fallback: m.fromName,
      );

  String _groupLabel(GroupInfo g) =>
      LocalLabels.groupName(g.id, g.name);

  Future<void> _renameUser(UserInfo u) async {
    final id = (u.accountId != null && u.accountId!.isNotEmpty)
        ? u.accountId!
        : u.uuid;
    final ctrl = TextEditingController(text: _userLabel(u));
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: VColors.surface,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.viewInsetsOf(ctx).bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Локальная подпись',
                style: TextStyle(
                  color: VColors.green,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Оригинал: ${u.displayName}',
                style: const TextStyle(color: VColors.dim, fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                style: const TextStyle(color: VColors.text),
                decoration: const InputDecoration(
                  hintText: 'как отображать у вас…',
                  hintStyle: TextStyle(color: VColors.dim),
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (v) async {
                  await LocalLabels.setUserLabel(id, v);
                  if (ctx.mounted) Navigator.pop(ctx, true);
                },
              ),
              const SizedBox(height: 8),
              const Text(
                'Видно только вам на этом устройстве',
                style: TextStyle(color: VColors.dim, fontSize: 11),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton(
                    onPressed: () async {
                      await LocalLabels.setUserLabel(id, null);
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    },
                    child: const Text('сбросить'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('отмена'),
                  ),
                  TextButton(
                    onPressed: () async {
                      await LocalLabels.setUserLabel(id, ctrl.text);
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    },
                    child: const Text(
                      'сохранить',
                      style: TextStyle(color: VColors.green),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    if (ok == true && mounted) setState(() {});
  }

  Future<void> _renameGroup(GroupInfo g) async {
    final ctrl = TextEditingController(text: _groupLabel(g));
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: VColors.surface,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.viewInsetsOf(ctx).bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Подпись группы',
                style: TextStyle(
                  color: VColors.green,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Оригинал: ${g.name}',
                style: const TextStyle(color: VColors.dim, fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                style: const TextStyle(color: VColors.text),
                decoration: const InputDecoration(
                  hintText: 'название только у вас…',
                  hintStyle: TextStyle(color: VColors.dim),
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (v) async {
                  await LocalLabels.setGroupLabel(g.id, v);
                  if (ctx.mounted) Navigator.pop(ctx, true);
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton(
                    onPressed: () async {
                      await LocalLabels.setGroupLabel(g.id, null);
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    },
                    child: const Text('сбросить'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('отмена'),
                  ),
                  TextButton(
                    onPressed: () async {
                      await LocalLabels.setGroupLabel(g.id, ctrl.text);
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    },
                    child: const Text(
                      'сохранить',
                      style: TextStyle(color: VColors.green),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    if (ok == true && mounted) setState(() {});
  }

  GlobalKey _keyForMessage(String id) =>
      _msgKeys.putIfAbsent(id, () => GlobalKey());

  double _estimateMsgHeight(ChatMessage m) {
    if (m.msgType == 'system' || m.msgType == 'date') return 36;
    var h = 52.0;
    if (m.replyTo != null) h += 44;
    if (m.edited) h += 14;
    if (m.mediaId != null) {
      final mime = (m.mime ?? '').toLowerCase();
      final fn = (m.filename ?? '').toLowerCase();
      if (mime.startsWith('image/') ||
          fn.endsWith('.jpg') ||
          fn.endsWith('.png') ||
          fn.endsWith('.webp') ||
          fn.endsWith('.gif')) {
        h += 180;
      } else if (mime.startsWith('video/') ||
          fn.endsWith('.mp4') ||
          fn.endsWith('.mov')) {
        h += 200;
      } else if (mime.startsWith('audio/')) {
        h += 56;
      } else {
        h += 28;
      }
    }
    final text = m.text ?? '';
    if (text.isNotEmpty) {
      // ~36 символов в строку в узком чате
      final lines = (text.length / 36).ceil().clamp(1, 20);
      h += lines * 18.0;
    }
    return h;
  }

  double _estimateOffsetTo(List<ChatMessage> msgs, int index) {
    var o = 0.0;
    for (var i = 0; i < index && i < msgs.length; i++) {
      o += _estimateMsgHeight(msgs[i]);
    }
    return o;
  }

  Future<void> _jumpToMessage(String messageId) async {
    if (messageId.isEmpty) return;
    final msgs = conn.currentMessages;
    final index = msgs.indexWhere((m) => m.id == messageId);
    if (index < 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Исходное сообщение не найдено в истории'),
            backgroundColor: VColors.surface,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    setState(() => _highlightId = messageId);

    // несколько попыток: сначала грубый скролл, затем ensureVisible по GlobalKey
    for (var attempt = 0; attempt < 10; attempt++) {
      if (!mounted) return;

      final ctx = _msgKeys[messageId]?.currentContext;
      if (ctx != null) {
        await Scrollable.ensureVisible(
          ctx,
          duration: Duration(milliseconds: attempt == 0 ? 280 : 180),
          curve: Curves.easeOut,
          alignment: 0.2,
        );
        // ещё раз после layout — точная позиция
        await Future.delayed(const Duration(milliseconds: 40));
        final ctx2 = _msgKeys[messageId]?.currentContext;
        if (ctx2 != null && mounted) {
          await Scrollable.ensureVisible(
            ctx2,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            alignment: 0.2,
          );
        }
        break;
      }

      if (_scrollCtrl.hasClients) {
        final max = _scrollCtrl.position.maxScrollExtent;
        final est = _estimateOffsetTo(msgs, index);
        // чуть недоскролливаем/перескролливаем по попыткам, чтобы виджет построился
        final bias = (attempt % 3 - 1) * 40.0;
        final target = (est + bias).clamp(0.0, max);
        await _scrollCtrl.animateTo(
          target,
          duration: const Duration(milliseconds: 100),
          curve: Curves.linear,
        );
      }
      await Future.delayed(const Duration(milliseconds: 60));
    }

    Future.delayed(const Duration(milliseconds: 2200), () {
      if (mounted && _highlightId == messageId) {
        setState(() => _highlightId = null);
      }
    });
  }


  void _editMessage(ChatMessage m) {
    if (m.msgType != 'text') return;
    final ctrl = TextEditingController(text: m.text ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: VColors.surface,
        title: const Text('Изменить сообщение'),
        content: TextField(
          controller: ctrl,
          maxLines: 5,
          autofocus: true,
          style: const TextStyle(color: VColors.text, fontSize: 14),
          decoration: const InputDecoration(
            hintText: 'текст…',
            hintStyle: TextStyle(color: VColors.dim),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('отмена'),
          ),
          TextButton(
            onPressed: () {
              final text = ctrl.text.trim();
              Navigator.pop(ctx);
              if (text.isNotEmpty) {
                conn.editMessage(m.id, text);
              }
            },
            child: const Text('сохранить',
                style: TextStyle(color: VColors.green)),
          ),
        ],
      ),
    );
  }

  Future<void> _showFileTooBig([int? bytes]) async {
    if (!mounted) return;
    final sizeStr = bytes != null && bytes > 0
        ? 'Размер файла: ${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ.\n\n'
        : '';
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D30),
        title: const Text(
          'Файл слишком большой',
          style: TextStyle(color: Color(0xFFFF6B6B), fontWeight: FontWeight.bold),
        ),
        content: Text(
          '${sizeStr}Максимальный размер вложения — 25 МБ.\n'
          'Выберите файл или фото меньшего размера.',
          style: const TextStyle(color: Color(0xFFD4D4D4), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'ПОНЯТНО',
              style: TextStyle(
                color: Color(0xFF007c42),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }


  Future<void> _pickFile() => _pickAndSend(FileType.any);

  /// Системная галерея (image_picker), не файловый проводник.
  Future<void> _pickGallery() async {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: VColors.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_outlined, color: VColors.green),
              title: const Text('Фото', style: TextStyle(color: VColors.text)),
              onTap: () {
                Navigator.pop(ctx);
                _pickFromGallery(photo: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined, color: VColors.blue),
              title: const Text('Видео', style: TextStyle(color: VColors.text)),
              onTap: () {
                Navigator.pop(ctx);
                _pickFromGallery(photo: false);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFromGallery({required bool photo}) async {
    try {
      final picker = ImagePicker();
      final XFile? x = photo
          ? await picker.pickImage(
              source: ImageSource.gallery,
              imageQuality: 92,
            )
          : await picker.pickVideo(source: ImageSource.gallery);
      if (x == null) return;
      final path = x.path;
      final name = x.name.isNotEmpty
          ? x.name
          : path.split(RegExp(r'[/\\]')).last;

      // размер: XFile.length() надёжнее File() на Android
      int fileLen = 0;
      try {
        fileLen = await x.length();
      } catch (_) {
        try {
          fileLen = await File(path).length();
        } catch (_) {}
      }
      if (fileLen > ConnectionService.maxFileBytes) {
        await _showFileTooBig(fileLen);
        return;
      }

      final ext = name.contains('.')
          ? name.split('.').last.toLowerCase()
          : (photo ? 'jpg' : 'mp4');
      String mime;
      if (photo) {
        mime = (ext == 'png')
            ? 'image/png'
            : (ext == 'webp')
                ? 'image/webp'
                : (ext == 'gif')
                    ? 'image/gif'
                    : 'image/jpeg';
      } else {
        mime = ext == 'mov' ? 'video/quicktime' : 'video/$ext';
        if (mime == 'video/$ext' && ext.length > 5) mime = 'video/mp4';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('отправка $name…'),
            backgroundColor: VColors.surface,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      final ok = await conn.sendFile(path, name, mime);
      if (!ok) {
        await _showFileTooBig(fileLen > 0 ? fileLen : null);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ошибка галереи: $e'),
            backgroundColor: VColors.surface,
          ),
        );
      }
    }
  }

  Future<void> _pickAndSend(FileType type) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: type,
        withData: false,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      final f = result.files.first;
      if (f.path == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('не удалось получить путь к файлу'),
              backgroundColor: VColors.surface,
            ),
          );
        }
        return;
      }

      // PlatformFile.size — реальный размер с Android-picker
      final fileLen = f.size;
      if (fileLen > ConnectionService.maxFileBytes) {
        await _showFileTooBig(fileLen);
        return;
      }

      final ext = (f.extension ?? '').toLowerCase();
      String mime = 'application/octet-stream';
      if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif'].contains(ext)) {
        mime = (ext == 'jpg' || ext == 'jpeg')
            ? 'image/jpeg'
            : (ext == 'heic' || ext == 'heif')
                ? 'image/heic'
                : 'image/$ext';
      } else if (['mp4', 'mov', 'webm', 'mkv', 'avi', 'm4v'].contains(ext)) {
        mime = ext == 'mov' ? 'video/quicktime' : 'video/$ext';
      } else if (['mp3', 'wav', 'ogg', 'm4a', 'aac', 'flac', 'opus'].contains(ext)) {
        mime = ext == 'mp3' ? 'audio/mpeg' : 'audio/$ext';
      } else if (ext == 'pdf') {
        mime = 'application/pdf';
      } else if (['txt', 'md', 'log'].contains(ext)) {
        mime = 'text/plain';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('отправка ${f.name}…'),
            backgroundColor: VColors.surface,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      final ok = await conn.sendFile(f.path!, f.name, mime);
      if (!ok) {
        await _showFileTooBig(fileLen > 0 ? fileLen : null);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ошибка файла: $e'),
            backgroundColor: VColors.surface,
          ),
        );
      }
    }
  }


  void _showAttachSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: VColors.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: VColors.green),
              title: const Text('Галерея (фото / видео)',
                  style: TextStyle(color: VColors.text)),
              onTap: () {
                Navigator.pop(ctx);
                _pickGallery();
              },
            ),
            ListTile(
              leading: const Icon(Icons.attach_file, color: VColors.dim),
              title: const Text('Файл', style: TextStyle(color: VColors.text)),
              onTap: () {
                Navigator.pop(ctx);
                _pickFile();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(ChatMessage m) {
    final mine = m.fromUuid == DeviceId.uuid ||
        m.fromUuid == (conn.me?.uuid ?? '') ||
        m.fromUuid == (conn.me?.accountId ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: VColors.surface,
        title: Text(mine ? 'Удалить сообщение?' : 'Удалить чужое сообщение?'),
        content: Text(
          mine
              ? 'Сообщение исчезнет у всех в этой группе.'
              : 'Вы админ: сообщение «${m.fromName}» будет удалено у всех.',
          style: const TextStyle(color: VColors.dim, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('отмена'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              conn.deleteMessage(m.id);
            },
            child: const Text('удалить', style: TextStyle(color: VColors.red)),
          ),
        ],
      ),
    );
  }

  void _copyAccountId(String aid, {String who = 'мой'}) {
    if (aid.isEmpty) return;
    Clipboard.setData(ClipboardData(text: aid));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$who account_id скопирован.\n'
          'Осторожно, ни с кем не делитесь этим account_id — '
          'благодаря нему можно зайти на аккаунт.',
        ),
        duration: const Duration(seconds: 5),
        backgroundColor: VColors.surface,
      ),
    );
  }

  void _startCall(UserInfo user) {
    if (conn.activeCallId != null || conn.isIncomingCall) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Линия этого абонента занята, попробуйте перезвонить позже',
          ),
          backgroundColor: VColors.surface,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }
    final myAcc = conn.me?.accountId ?? conn.me?.uuid;
    final theirAcc = user.accountId ?? user.uuid;
    if (myAcc != null && myAcc == theirAcc) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('нельзя позвонить самому себе'),
          backgroundColor: VColors.surface,
        ),
      );
      return;
    }
    // account_id → сервер разошлёт на все онлайн-устройства
    final target = user.accountId ?? user.callDeviceUuid ?? user.uuid;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CallScreen(
          connection: conn,
          peerUuid: target,
          peerName: LocalLabels.userNameFor(
            uuid: user.uuid,
            accountId: user.accountId,
            fallback: user.displayName,
          ),
          isIncoming: false,
        ),
      ),
    );
  }

  void _createGroup() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: VColors.surface,
        title: const Text('Новая группа'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: 'название'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('отмена'),
          ),
          TextButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) {
                conn.createGroup(ctrl.text.trim());
              }
              Navigator.pop(context);
            },
            child: const Text('создать', style: TextStyle(color: VColors.green)),
          ),
        ],
      ),
    );
  }

  void _manageGroup(GroupInfo g) {
    showModalBottomSheet(
      context: context,
      backgroundColor: VColors.surface,
      isScrollControlled: true,
      builder: (_) => _GroupManageSheet(conn: conn, group: g),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 700;
    final msgs = conn.currentMessages;

    final groupsPanel = Container(
      color: VColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 4),
            child: Row(
              children: [
                const Expanded(
                  child: Text('GROUPS',
                      style: TextStyle(
                          color: VColors.dim,
                          fontSize: 11,
                          letterSpacing: 1.5)),
                ),
                IconButton(
                  icon: const Icon(Icons.add, size: 16, color: VColors.green),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: _createGroup,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: conn.groups.length,
              itemBuilder: (_, i) {
                final g = conn.groups[i];
                final selected = g.id == conn.currentGroupId;
                return ListTile(
                  dense: true,
                  selected: selected,
                  selectedTileColor: VColors.bg,
                  title: Text(
                    _groupLabel(g),
                    style: TextStyle(
                      fontSize: 13,
                      color: selected ? VColors.green : VColors.text,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${g.memberCount} чел.',
                    style: const TextStyle(fontSize: 10, color: VColors.dim),
                  ),
                  trailing: g.id != 'global'
                      ? IconButton(
                          icon: const Icon(Icons.more_horiz, size: 16, color: VColors.dim),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => _manageGroup(g),
                        )
                      : null,
                  onTap: () {
                    conn.selectGroup(g.id);
                    if (!isWide) Navigator.of(context).maybePop();
                  },
                  onLongPress: () {
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: VColors.surface,
                      builder: (ctx) => SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: const Icon(Icons.edit,
                                  color: VColors.green, size: 20),
                              title: const Text('Переименовать у себя',
                                  style: TextStyle(color: VColors.text)),
                              onTap: () {
                                Navigator.pop(ctx);
                                _renameGroup(g);
                              },
                            ),
                            if (g.id != 'global')
                              ListTile(
                                leading: const Icon(Icons.group,
                                    color: VColors.blue, size: 20),
                                title: const Text('Управление группой',
                                    style: TextStyle(color: VColors.text)),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _manageGroup(g);
                                },
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );

    final groupMemberIds = Set<String>.from(conn.currentGroup?.members ?? []);
    bool _userInGroup(UserInfo u) {
      if (groupMemberIds.isEmpty) return true;
      if (groupMemberIds.contains(u.uuid)) return true;
      if (u.accountId != null && groupMemberIds.contains(u.accountId)) return true;
      if (u.callDeviceUuid != null && groupMemberIds.contains(u.callDeviceUuid)) {
        return true;
      }
      for (final d in u.deviceUuids) {
        if (groupMemberIds.contains(d)) return true;
      }
      return false;
    }

    final groupUsers = conn.users.where(_userInGroup).toList();
    // всегда показываем себя в текущей группе
    final me = conn.me;
    if (me != null) {
      final meId = me.accountId ?? me.uuid;
      final hasMe = groupUsers.any(
        (u) =>
            u.uuid == me.uuid ||
            u.uuid == meId ||
            u.accountId == meId ||
            (me.accountId != null && u.accountId == me.accountId),
      );
      if (!hasMe) {
        groupUsers.insert(0, me);
      }
    }
    final usersPanel = _UsersSidebar(
      users: groupUsers,
      meUuid: conn.me?.accountId ?? conn.me?.uuid,
      onCall: _startCall,
      onCopyAccount: (aid, who) => _copyAccountId(aid, who: who),
      onRename: _renameUser,
    );

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('VENIAMIN'),
            const SizedBox(width: 12),
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: VColors.green,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                conn.currentGroup != null
                    ? _groupLabel(conn.currentGroup!)
                    : '…',
                style: const TextStyle(color: VColors.dim, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (conn.isAdmin) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  border: Border.all(color: VColors.purple),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: const Text('ADMIN',
                    style: TextStyle(color: VColors.purple, fontSize: 10)),
              ),
            ],
          ],
        ),
        actions: [
          if (isWide) ...[
            IconButton(
              icon: const Icon(Icons.photo_library_outlined, size: 20),
              tooltip: 'галерея',
              onPressed: _pickGallery,
            ),
            IconButton(
              icon: const Icon(Icons.attach_file, size: 20),
              tooltip: 'файл',
              onPressed: _pickFile,
            ),
            IconButton(
              icon: const Icon(Icons.badge_outlined, size: 20),
              tooltip: 'copy my account_id',
              onPressed: () {
                final aid = conn.me?.accountId ?? conn.me?.uuid ?? '';
                _copyAccountId(aid);
              },
            ),
            IconButton(
              icon: Icon(_showSidebar ? Icons.people_outline : Icons.people, size: 20),
              onPressed: () => setState(() => _showSidebar = !_showSidebar),
            ),
            if (conn.isAdmin)
              IconButton(
                icon: const Icon(Icons.admin_panel_settings_outlined, size: 20),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AdminPanel(connection: conn),
                    ),
                  );
                },
              ),
            IconButton(
              icon: const Icon(Icons.logout, size: 20, color: VColors.red),
              onPressed: () => conn.disconnect(),
            ),
          ] else
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: VColors.text),
              color: VColors.surface,
              onSelected: (v) {
                switch (v) {
                  case 'gallery':
                    _pickGallery();
                    break;
                  case 'file':
                    _pickFile();
                    break;
                  case 'users':
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: VColors.surface,
                      builder: (_) => SafeArea(
                        child: SizedBox(height: 320, child: usersPanel),
                      ),
                    );
                    break;
                  case 'account':
                    final aid = conn.me?.accountId ?? conn.me?.uuid ?? '';
                    _copyAccountId(aid);
                    break;
                  case 'admin':
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AdminPanel(connection: conn),
                      ),
                    );
                    break;
                  case 'logout':
                    conn.disconnect();
                    break;
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'gallery',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.photo_library_outlined,
                        size: 18, color: VColors.green),
                    title: Text('галерея', style: TextStyle(color: VColors.text)),
                  ),
                ),
                const PopupMenuItem(
                  value: 'file',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.attach_file, size: 18, color: VColors.dim),
                    title: Text('файл', style: TextStyle(color: VColors.text)),
                  ),
                ),
                const PopupMenuItem(
                  value: 'users',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.people_outline, size: 18, color: VColors.dim),
                    title: Text('участники', style: TextStyle(color: VColors.text)),
                  ),
                ),
                const PopupMenuItem(
                  value: 'account',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.badge_outlined, size: 18, color: VColors.dim),
                    title: Text('мой account_id', style: TextStyle(color: VColors.text)),
                  ),
                ),
                if (conn.isAdmin)
                  const PopupMenuItem(
                    value: 'admin',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.admin_panel_settings_outlined,
                          size: 18, color: VColors.purple),
                      title: Text('админ-панель',
                          style: TextStyle(color: VColors.text)),
                    ),
                  ),
                const PopupMenuItem(
                  value: 'logout',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.logout, size: 18, color: VColors.red),
                    title: Text('выйти', style: TextStyle(color: VColors.red)),
                  ),
                ),
              ],
            ),
        ],
      ),
      drawer: isWide
          ? null
          : Drawer(
              backgroundColor: VColors.surface,
              child: SafeArea(child: groupsPanel),
            ),
      body: Column(
        children: [
          if (conn.isIncomingCall && conn.callPeerUuid != null)
            _IncomingCallBanner(
              name: conn.callPeerName ?? 'Звонок',
              onAccept: () {
                final peer = conn.callPeerUuid!;
                final name = conn.callPeerName ?? '?';
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CallScreen(
                      connection: conn,
                      peerUuid: peer,
                      peerName: name,
                      isIncoming: true,
                    ),
                  ),
                );
              },
              onReject: () => conn.rejectCall(),
            ),
          Expanded(
            child: Row(
              children: [
                if (_showSidebar && isWide)
                  SizedBox(width: 160, child: groupsPanel),
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: ListView.builder(
                          controller: _scrollCtrl,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          itemCount: msgs.length,
                          itemBuilder: (_, i) {
                            final m = msgs[i];
                            final isMe = m.fromUuid == DeviceId.uuid ||
                                m.fromUuid == (conn.me?.uuid ?? '') ||
                                m.fromUuid == (conn.me?.accountId ?? '');
                            return KeyedSubtree(
                              key: _keyForMessage(m.id),
                              child: _MessageBubble(
                              msg: m,
                              isMe: isMe,
                              highlighted: _highlightId == m.id,
                              onDownload: (mid) =>
                                  _download(mid, m.filename),
                              loadMedia: (mid) => conn.downloadMedia(mid),
                              onDelete: (isMe || conn.isAdmin)
                                  ? () => _confirmDelete(m)
                                  : null,
                              onReply: () => _setReply(m),
                              onEdit: isMe && m.msgType == 'text'
                                  ? () => _editMessage(m)
                                  : null,
                              onTapReply: m.replyTo != null
                                  ? () => _jumpToMessage(m.replyTo!.id)
                                  : null,
                            ),
                            );
                          },
                        ),
                      ),
                      if (conn.typingUser != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 16, bottom: 4),
                          child: Text(
                            '${conn.typingUser} is typing…',
                            style: const TextStyle(
                                color: VColors.dim, fontSize: 11),
                          ),
                        ),
                      SafeArea(
                        top: false,
                        left: false,
                        right: false,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_replyTo != null)
                              Container(
                                width: double.infinity,
                                color: VColors.surface,
                                padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
                                child: Row(
                                  children: [
                                    const Icon(Icons.reply,
                                        size: 16, color: VColors.green),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Ответ для ${_replyTo!.fromName}',
                                            style: const TextStyle(
                                              color: VColors.green,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          Text(
                                            _replyTo!.msgType == 'text'
                                                ? (_replyTo!.text ?? '')
                                                : '📎 ${_replyTo!.filename ?? _replyTo!.msgType}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: VColors.dim,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close,
                                          size: 16, color: VColors.dim),
                                      onPressed: () =>
                                          setState(() => _replyTo = null),
                                    ),
                                  ],
                                ),
                              ),
                            _InputBar(
                              controller: _inputCtrl,
                              onSend: _send,
                              onTyping: (v) => conn.sendTyping(v),
                              onAttach: _showAttachSheet,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (_showSidebar && isWide)
                  SizedBox(width: 200, child: usersPanel),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _download(String? mediaId, String? filename) async {
    if (mediaId == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('скачивание…'),
        duration: Duration(seconds: 2),
        backgroundColor: VColors.surface,
      ),
    );
    final data = await conn.downloadMedia(mediaId);
    if (data == null || !mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('не удалось скачать'),
          backgroundColor: VColors.surface,
        ),
      );
      return;
    }
    final dir = await getDownloadsDirectory() ?? await getTemporaryDirectory();
    final name = filename ?? mediaId;
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(data);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('сохранено: ${file.path}'),
          backgroundColor: VColors.surface,
        ),
      );
    }
  }
}


class _IncomingCallBanner extends StatelessWidget {
  final String name;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _IncomingCallBanner({
    required this.name,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1B5E20),
      elevation: 6,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
              const Icon(Icons.call, color: Colors.white, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Входящий звонок',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // reject
              Material(
                color: const Color(0xFFB71C1C),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onReject,
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(Icons.call_end, color: Colors.white, size: 22),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // accept
              Material(
                color: const Color(0xFF2E7D32),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onAccept,
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(Icons.call, color: Colors.white, size: 22),
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage msg;
  final bool isMe;
  final bool highlighted;
  final void Function(String?) onDownload;
  final Future<Uint8List?> Function(String mediaId) loadMedia;
  final VoidCallback? onDelete;
  final VoidCallback? onReply;
  final VoidCallback? onEdit;
  final VoidCallback? onTapReply;
  const _MessageBubble({
    required this.msg,
    required this.isMe,
    this.highlighted = false,
    required this.onDownload,
    required this.loadMedia,
    this.onDelete,
    this.onReply,
    this.onEdit,
    this.onTapReply,
  });

  bool get _isImage {
    final m = (msg.mime ?? '').toLowerCase();
    final f = (msg.filename ?? '').toLowerCase();
    return m.startsWith('image/') ||
        f.endsWith('.jpg') ||
        f.endsWith('.jpeg') ||
        f.endsWith('.png') ||
        f.endsWith('.gif') ||
        f.endsWith('.webp') ||
        f.endsWith('.bmp');
  }

  bool get _isVideo {
    final m = (msg.mime ?? '').toLowerCase();
    final f = (msg.filename ?? '').toLowerCase();
    return m.startsWith('video/') ||
        f.endsWith('.mp4') ||
        f.endsWith('.mov') ||
        f.endsWith('.webm') ||
        f.endsWith('.mkv') ||
        f.endsWith('.avi');
  }

  bool get _isAudio {
    final m = (msg.mime ?? '').toLowerCase();
    final f = (msg.filename ?? '').toLowerCase();
    return m.startsWith('audio/') ||
        f.endsWith('.mp3') ||
        f.endsWith('.wav') ||
        f.endsWith('.ogg') ||
        f.endsWith('.m4a') ||
        f.endsWith('.aac') ||
        f.endsWith('.flac') ||
        f.endsWith('.opus');
  }

  String get _copyText {
    if (msg.msgType == 'text') return msg.text ?? '';
    if (msg.filename != null && msg.filename!.isNotEmpty) {
      return msg.filename!;
    }
    return msg.text ?? '';
  }

  Future<void> _openUrl(String raw) async {
    var s = raw.trim();
    // обрезать хвостовую пунктуацию
    while (s.isNotEmpty && '.,);]!?>»"\''.contains(s[s.length - 1])) {
      s = s.substring(0, s.length - 1);
    }
    if (s.startsWith('www.')) s = 'https://$s';
    final uri = Uri.tryParse(s);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  List<InlineSpan> _linkifiedText(String text, TextStyle base) {
    final re = RegExp(
      r'(https?:\/\/[^\s<>\[\]{}|\\^`]+|www\.[^\s<>\[\]{}|\\^`]+)',
      caseSensitive: false,
    );
    final spans = <InlineSpan>[];
    var start = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > start) {
        spans.add(TextSpan(text: text.substring(start, m.start), style: base));
      }
      final link = m.group(0)!;
      spans.add(
        TextSpan(
          text: link,
          style: base.copyWith(
            color: VColors.blue,
            decoration: TextDecoration.underline,
            decorationColor: VColors.blue,
          ),
          recognizer: TapGestureRecognizer()..onTap = () => _openUrl(link),
        ),
      );
      start = m.end;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: base));
    }
    if (spans.isEmpty) {
      spans.add(TextSpan(text: text, style: base));
    }
    return spans;
  }

  void _showMenu(BuildContext context) {
    final canCopy = _copyText.trim().isNotEmpty;
    showModalBottomSheet(
      context: context,
      backgroundColor: VColors.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onReply != null)
              ListTile(
                leading: const Icon(Icons.reply, color: VColors.green, size: 20),
                title: const Text('Ответить',
                    style: TextStyle(color: VColors.text)),
                onTap: () {
                  Navigator.pop(ctx);
                  onReply!();
                },
              ),
            if (onEdit != null)
              ListTile(
                leading: const Icon(Icons.edit, color: VColors.blue, size: 20),
                title: const Text('Изменить',
                    style: TextStyle(color: VColors.text)),
                onTap: () {
                  Navigator.pop(ctx);
                  onEdit!();
                },
              ),
            if (canCopy)
              ListTile(
                leading: const Icon(Icons.copy, color: VColors.green, size: 20),
                title: const Text('Копировать',
                    style: TextStyle(color: VColors.text)),
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: _copyText));
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('скопировано'),
                        backgroundColor: VColors.surface,
                        duration: Duration(seconds: 1),
                      ),
                    );
                  }
                },
              ),
            if (onDelete != null)
              ListTile(
                leading: const Icon(Icons.delete_outline,
                    color: VColors.red, size: 20),
                title: const Text('Удалить',
                    style: TextStyle(color: VColors.red)),
                onTap: () {
                  Navigator.pop(ctx);
                  onDelete!();
                },
              ),
            ListTile(
              leading: const Icon(Icons.close, color: VColors.dim, size: 20),
              title: const Text('Отмена', style: TextStyle(color: VColors.dim)),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('HH:mm').format(
      DateTime.fromMillisecondsSinceEpoch(msg.ts),
    );

    if (msg.msgType == 'system' || msg.msgType == 'date') {
      final raw = msg.text ?? '';
      final display = msg.msgType == 'date' || raw.startsWith('---')
          ? (raw.isEmpty ? '—' : raw)
          : '— $raw —';
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          display,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: VColors.system,
            fontSize: 12,
            letterSpacing: 0.5,
          ),
        ),
      );
    }

    final nameColor = isMe ? VColors.green : VColors.blue;
    final isFile = msg.msgType != 'text' && msg.mediaId != null;
    const baseStyle = TextStyle(
      fontFamily: 'JetBrains Mono',
      fontSize: 13,
      height: 1.45,
      color: VColors.text,
    );

    return GestureDetector(
      onLongPress: () => _showMenu(context),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        decoration: BoxDecoration(
          color: highlighted
              ? VColors.green.withOpacity(0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: highlighted
              ? Border.all(color: VColors.green.withOpacity(0.5))
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (msg.replyTo != null)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTapReply,
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    margin: const EdgeInsets.only(left: 4, bottom: 4),
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                    decoration: BoxDecoration(
                      border: const Border(
                        left: BorderSide(color: VColors.green, width: 3),
                      ),
                      color: const Color(0xFF252526),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          msg.replyTo!.fromName,
                          style: const TextStyle(
                            color: VColors.green,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          msg.replyTo!.msgType == 'text'
                              ? msg.replyTo!.text
                              : '📎 ${msg.replyTo!.text}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: VColors.dim,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: baseStyle,
                      children: [
                        TextSpan(
                          text: '[$time] ',
                          style: const TextStyle(
                              color: VColors.dim, fontSize: 11),
                        ),
                        TextSpan(
                          text:
                              '${LocalLabels.userNameFor(uuid: msg.fromUuid, fallback: msg.fromName)}: ',
                          style: TextStyle(
                              color: nameColor, fontWeight: FontWeight.w600),
                        ),
                        if (msg.msgType == 'text')
                          ..._linkifiedText(msg.text ?? '', baseStyle)
                        else
                          TextSpan(
                            text:
                                '📎 ${msg.filename ?? msg.msgType} (${_fmtSize(msg.size)})',
                            style: const TextStyle(color: VColors.yellow),
                          ),
                      ],
                    ),
                  ),
                ),
                if (msg.mediaId != null)
                  IconButton(
                    icon: const Icon(Icons.download,
                        size: 16, color: VColors.dim),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'сохранить',
                    onPressed: () => onDownload(msg.mediaId),
                  ),
              ],
            ),
            if (msg.edited)
              const Padding(
                padding: EdgeInsets.only(left: 8, top: 2),
                child: Text(
                  'изменено',
                  style: TextStyle(
                    color: VColors.dim,
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            if (isFile && (_isImage || _isVideo || _isAudio))
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 4, bottom: 4),
                child: _InlineMedia(
                  mediaId: msg.mediaId!,
                  filename: msg.filename ?? 'file',
                  mime: msg.mime ?? '',
                  isImage: _isImage,
                  isVideo: _isVideo,
                  isAudio: _isAudio,
                  loadMedia: loadMedia,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _fmtSize(int? s) {
    if (s == null) return '?';
    if (s < 1024) return '$s B';
    if (s < 1024 * 1024) return '${(s / 1024).toStringAsFixed(1)} KB';
    return '${(s / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _InlineMedia extends StatefulWidget {
  final String mediaId;
  final String filename;
  final String mime;
  final bool isImage;
  final bool isVideo;
  final bool isAudio;
  final Future<Uint8List?> Function(String mediaId) loadMedia;

  const _InlineMedia({
    required this.mediaId,
    required this.filename,
    required this.mime,
    required this.isImage,
    required this.isVideo,
    required this.isAudio,
    required this.loadMedia,
  });

  @override
  State<_InlineMedia> createState() => _InlineMediaState();
}

class _InlineMediaState extends State<_InlineMedia> {
  Uint8List? _bytes;
  bool _loading = true;
  String? _error;
  String? _tempPath;

  VideoPlayerController? _video;
  final AudioPlayer _audio = AudioPlayer();
  bool _audioPlaying = false;
  Duration _audioPos = Duration.zero;
  Duration _audioDur = Duration.zero;

  @override
  void initState() {
    super.initState();
    _load();
    _audio.onPositionChanged.listen((p) {
      if (mounted) setState(() => _audioPos = p);
    });
    _audio.onDurationChanged.listen((d) {
      if (mounted) setState(() => _audioDur = d);
    });
    _audio.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _audioPlaying = false);
    });
  }

  Future<void> _load() async {
    try {
      final data = await widget.loadMedia(widget.mediaId);
      if (!mounted) return;
      if (data == null) {
        setState(() {
          _loading = false;
          _error = 'не удалось загрузить';
        });
        return;
      }
      _bytes = data;
      final dir = await getTemporaryDirectory();
      final safe = widget.filename.replaceAll(RegExp(r'[^\w\.\-]'), '_');
      final path = '${dir.path}/v_${widget.mediaId}_$safe';
      final f = File(path);
      await f.writeAsBytes(data, flush: true);
      _tempPath = path;

      if (widget.isVideo) {
        _video = VideoPlayerController.file(File(path));
        await _video!.initialize();
        await _video!.setLooping(false);
        _video!.addListener(() {
          if (mounted) setState(() {});
        });
      }
      if (mounted) {
        setState(() => _loading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    _audio.dispose();
    super.dispose();
  }

  Future<void> _toggleAudio() async {
    if (_tempPath == null) return;
    if (_audioPlaying) {
      await _audio.pause();
      setState(() => _audioPlaying = false);
    } else {
      await _audio.play(DeviceFileSource(_tempPath!));
      setState(() => _audioPlaying = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 40,
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: VColors.green),
          ),
        ),
      );
    }
    if (_error != null) {
      return Text(_error!,
          style: const TextStyle(color: VColors.red, fontSize: 11));
    }

    if (widget.isImage && _bytes != null) {
      return GestureDetector(
        onTap: () {
          showDialog(
            context: context,
            builder: (_) => Dialog(
              backgroundColor: Colors.black,
              insetPadding: const EdgeInsets.all(12),
              child: InteractiveViewer(
                child: Image.memory(_bytes!, fit: BoxFit.contain),
              ),
            ),
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220, maxWidth: 320),
            child: Image.memory(_bytes!, fit: BoxFit.contain),
          ),
        ),
      );
    }

    if (widget.isVideo && _video != null && _video!.value.isInitialized) {
      final ar = _video!.value.aspectRatio == 0 ? 16 / 9 : _video!.value.aspectRatio;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240, maxWidth: 340),
              child: AspectRatio(
                aspectRatio: ar,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    VideoPlayer(_video!),
                    Material(
                      color: Colors.black38,
                      shape: const CircleBorder(),
                      child: IconButton(
                        icon: Icon(
                          _video!.value.isPlaying
                              ? Icons.pause
                              : Icons.play_arrow,
                          color: Colors.white,
                        ),
                        onPressed: () {
                          setState(() {
                            if (_video!.value.isPlaying) {
                              _video!.pause();
                            } else {
                              _video!.play();
                            }
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_video!.value.duration.inMilliseconds > 0)
            SizedBox(
              width: 340,
              child: VideoProgressIndicator(
                _video!,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: VColors.green,
                  bufferedColor: VColors.dim,
                  backgroundColor: VColors.border,
                ),
              ),
            ),
        ],
      );
    }

    if (widget.isAudio) {
      final total = _audioDur.inMilliseconds;
      final pos = _audioPos.inMilliseconds;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: VColors.surface,
          border: Border.all(color: VColors.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            IconButton(
              icon: Icon(
                _audioPlaying ? Icons.pause_circle : Icons.play_circle,
                color: VColors.green,
                size: 28,
              ),
              onPressed: _toggleAudio,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.filename,
                    style: const TextStyle(fontSize: 12, color: VColors.text),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: total > 0 ? (pos / total).clamp(0.0, 1.0) : 0,
                    backgroundColor: VColors.border,
                    color: VColors.green,
                    minHeight: 3,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_fmtDur(_audioPos)} / ${_fmtDur(_audioDur)}',
                    style:
                        const TextStyle(fontSize: 10, color: VColors.dim),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  String _fmtDur(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final ValueChanged<bool> onTyping;
  final VoidCallback onAttach;
  const _InputBar({
    required this.controller,
    required this.onSend,
    required this.onTyping,
    required this.onAttach,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: VColors.border)),
        color: VColors.surface,
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.attach_file, size: 18, color: VColors.dim),
            onPressed: onAttach,
          ),
          const Text(
            '> ',
            style: TextStyle(color: VColors.green, fontWeight: FontWeight.bold),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'message…',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
              ),
              maxLines: 4,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onChanged: (v) => onTyping(v.isNotEmpty),
              onSubmitted: (_) => onSend(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send, size: 20, color: VColors.green),
            onPressed: onSend,
          ),
        ],
      ),
    );
  }
}

class _UsersSidebar extends StatelessWidget {
  final List<UserInfo> users;
  final String? meUuid;
  final void Function(UserInfo) onCall;
  final void Function(String aid, String who) onCopyAccount;
  final void Function(UserInfo)? onRename;
  const _UsersSidebar({
    required this.users,
    required this.meUuid,
    required this.onCall,
    required this.onCopyAccount,
    this.onRename,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'USERS',
            style: TextStyle(
              color: VColors.dim,
              fontSize: 11,
              letterSpacing: 1.5,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: users.length,
            itemBuilder: (_, i) {
              final u = users[i];
              final isMe = (u.accountId ?? u.uuid) == meUuid || u.uuid == meUuid;
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onLongPress: () {
                    if (onRename != null) {
                      onRename!(u);
                    } else {
                      final aid = u.accountId ?? u.uuid;
                      onCopyAccount(aid, u.displayName);
                    }
                  },
                  child: ListTile(
                    // больше зона нажатия
                    dense: false,
                    minVerticalPadding: 12,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    leading: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: u.online ? VColors.green : VColors.dim,
                        shape: BoxShape.circle,
                      ),
                    ),
                    title: Text(
                      LocalLabels.userNameFor(
                            uuid: u.uuid,
                            accountId: u.accountId,
                            fallback: u.displayName,
                          ) +
                          (isMe ? ' (you)' : ''),
                      style: TextStyle(
                        fontSize: 13,
                        color: isMe ? VColors.green : VColors.text,
                      ),
                    ),
                    subtitle: Row(
                      children: [
                        if (u.role == 'admin')
                          const Text('admin ',
                              style: TextStyle(
                                  color: VColors.purple, fontSize: 10)),
                        ...u.platforms.map((p) {
                          final pl = p.toLowerCase();
                          IconData icon = Icons.devices;
                          if (pl.contains('android') || pl.contains('ios')) {
                            icon = Icons.phone_android;
                          } else if (pl.contains('windows') ||
                              pl.contains('linux') ||
                              pl.contains('mac')) {
                            icon = Icons.computer;
                          }
                          return Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(icon, size: 12, color: VColors.dim),
                          );
                        }),
                      ],
                    ),
                    trailing: !isMe && u.online
                        ? IconButton(
                            icon: const Icon(Icons.call,
                                size: 16, color: VColors.blue),
                            onPressed: () => onCall(u),
                          )
                        : null,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _GroupManageSheet extends StatelessWidget {
  final ConnectionService conn;
  final GroupInfo group;
  const _GroupManageSheet({required this.conn, required this.group});

  @override
  Widget build(BuildContext context) {
    bool _isMember(UserInfo u) {
      final ids = <String>{u.uuid};
      if (u.accountId != null && u.accountId!.isNotEmpty) {
        ids.add(u.accountId!);
      }
      for (final id in ids) {
        if (group.members.contains(id)) return true;
      }
      return false;
    }

    UserInfo _resolveMember(String id) {
      try {
        return conn.users.firstWhere(
          (u) =>
              u.uuid == id ||
              u.accountId == id ||
              u.deviceUuids.contains(id),
        );
      } catch (_) {
        final short = id.length > 8 ? id.substring(0, 8) : id;
        return UserInfo(uuid: id, displayName: short, role: '');
      }
    }

    final members = group.members.map(_resolveMember).toList();
    final nonMembers = conn.users.where((u) => !_isMember(u)).toList();

    final maxH = MediaQuery.of(context).size.height * 0.75;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: SingleChildScrollView(
            child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(group.name,
                style: const TextStyle(
                    fontSize: 16, color: VColors.green, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text('⋯ управление группой',
                style: TextStyle(color: VColors.dim, fontSize: 11)),
            const SizedBox(height: 12),
            const Text('Участники', style: TextStyle(color: VColors.dim, fontSize: 11)),
            ...members.map((u) => ListTile(
                  dense: true,
                  title: Text(u.displayName, style: const TextStyle(fontSize: 13)),
                  trailing: u.role != 'admin' &&
                          (u.accountId ?? u.uuid) !=
                              (conn.me?.accountId ?? conn.me?.uuid)
                      ? TextButton(
                          onPressed: () {
                            conn.removeFromGroup(group.id, u.uuid);
                            Navigator.pop(context);
                          },
                          child: const Text('удалить',
                              style: TextStyle(color: VColors.red, fontSize: 12)),
                        )
                      : null,
                )),
            if (nonMembers.isNotEmpty) ...[
              const Divider(color: VColors.border),
              const Text('Добавить', style: TextStyle(color: VColors.dim, fontSize: 11)),
              ...nonMembers.map((u) => ListTile(
                    dense: true,
                    title: Text(
                      LocalLabels.userNameFor(
                        uuid: u.uuid,
                        accountId: u.accountId,
                        fallback: u.displayName,
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                    trailing: TextButton(
                      onPressed: () {
                        final id = (u.accountId != null && u.accountId!.isNotEmpty)
                            ? u.accountId!
                            : u.uuid;
                        conn.addToGroup(group.id, id);
                        Navigator.pop(context);
                      },
                      child: const Text('+',
                          style: TextStyle(color: VColors.green, fontSize: 16)),
                    ),
                  )),
            ],
            if (group.id != 'global')
              TextButton(
                onPressed: () {
                  conn.leaveGroup(group.id);
                  Navigator.pop(context);
                },
                child: const Text('покинуть группу',
                    style: TextStyle(color: VColors.red)),
              ),
          ],
            ),
          ),
        ),
      ),
    );
  }
}
