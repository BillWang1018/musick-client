import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/socket_service.dart';

class CreateCommunityPostPage extends StatefulWidget {
  final SocketService socketService;
  final String userId;
  final String? userName;

  const CreateCommunityPostPage({
    super.key,
    required this.socketService,
    required this.userId,
    this.userName,
  });

  @override
  State<CreateCommunityPostPage> createState() => _CreateCommunityPostPageState();
}

class _CreateCommunityPostPageState extends State<CreateCommunityPostPage> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _logger = Logger();
  final List<_PendingAttachment> _attachments = [];
  bool _submitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickAttachment() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const [
        'png',
        'jpg',
        'jpeg',
        'gif',
        'webp',
        'bmp',
        'heic',
        'mp3',
        'm4a',
        'wav',
        'flac',
        'aac',
        'ogg',
        'opus',
      ],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;

    for (final file in result.files) {
      final added = await _addAttachmentFromFile(file);
      if (!added) {
        _showSnack('Unsupported or unreadable file: ${file.name}');
      }
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<bool> _addAttachmentFromFile(PlatformFile file) async {
    try {
      Uint8List? bytes = file.bytes;
      if (bytes == null && file.path != null) {
        final f = File(file.path!);
        bytes = await f.readAsBytes();
      }

      if (bytes == null || bytes.isEmpty) {
        return false;
      }

      final ext = (file.extension ?? '').toLowerCase();
      final mime = _extToMime(ext);
      final fileType = _inferFileType(mime);
      if (fileType == null) {
        return false;
      }

      _attachments.add(
        _PendingAttachment(
          name: file.name,
          bytes: bytes,
          mimeType: mime,
          fileType: fileType,
        ),
      );
      return true;
    } catch (e) {
      _logger.w('Failed to read file ${file.name}: $e');
      return false;
    }
  }

  String _extToMime(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'bmp':
        return 'image/bmp';
      case 'heic':
        return 'image/heic';
      case 'mp3':
        return 'audio/mpeg';
      case 'm4a':
        return 'audio/mp4';
      case 'wav':
        return 'audio/wav';
      case 'flac':
        return 'audio/flac';
      case 'aac':
        return 'audio/aac';
      case 'ogg':
      case 'opus':
        return 'audio/ogg';
      default:
        return 'application/octet-stream';
    }
  }

  String? _inferFileType(String mime) {
    if (mime.startsWith('image/')) return 'image';
    if (mime.startsWith('audio/')) return 'audio';
    return null;
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();

    if (title.isEmpty || body.isEmpty) {
      _showSnack('Please provide a title and body.');
      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      final postId = await _createPost(title, body);
      if (postId == null) {
        _showSnack('Failed to create post.');
        return;
      }

      if (_attachments.isNotEmpty) {
        final uploaded = await _uploadAllAttachments(postId);
        if (!uploaded) {
          _showSnack('Post saved, but some attachments failed to upload.');
          return;
        }
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  Future<String?> _createPost(String title, String body) async {
    final payload = jsonEncode({
      'user_id': widget.userId,
      'title': title,
      'body': body,
    });

    _logger.i('Creating post (route 701): $payload');
    widget.socketService.sendToRoute(701, payload);

    final raw = await _waitForCreatePostResponse(timeout: const Duration(seconds: 12));
    if (raw == null) {
      return null;
    }

    final parsed = _tryParseCreatePostResponse(raw);
    if (parsed == null || !parsed.success) {
      return null;
    }

    final postId = parsed.postId;
    if (postId.isEmpty) {
      _logger.w('Create post response missing post id.');
    }
    return postId;
  }

  Future<String?> _waitForCreatePostResponse({required Duration timeout}) async {
    try {
      return await widget.socketService.messages
          .where((m) => m.isNotEmpty)
          .where((m) => !m.startsWith('Error:'))
          .where((m) => m != 'Disconnected')
          .where(_looksLikeCreatePostJson)
          .first
          .timeout(timeout);
    } catch (e) {
      _logger.w('Timed out waiting for create-post response: $e');
      return null;
    }
  }

  bool _looksLikeCreatePostJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return false;
      if (!decoded.containsKey('success')) return false;
      if (decoded.containsKey('posts')) return false;
      return decoded.containsKey('post') || decoded.containsKey('message');
    } catch (_) {
      return false;
    }
  }

  _CreatePostParsed? _tryParseCreatePostResponse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;

      final success = decoded['success'];
      if (success is! bool) return null;

      String postId = '';
      final postMap = decoded['post'];
      if (postMap is Map && postMap['id'] is String) {
        postId = postMap['id'] as String;
      }

      return _CreatePostParsed(success: success, postId: postId);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _uploadAllAttachments(String postId) async {
    for (final att in _attachments) {
      final ok = await _uploadAttachment(postId, att);
      if (!ok) {
        return false;
      }
    }
    return true;
  }

  Future<bool> _uploadAttachment(String postId, _PendingAttachment att) async {
    const bucket = 'community-attachments';
    final client = Supabase.instance.client;
    final uniqueName = '${DateTime.now().millisecondsSinceEpoch}-${att.name}';
    final objectPath = '${widget.userId}/$uniqueName';
    final filePath = '$bucket/$objectPath';

    try {
      await client.storage.from(bucket).uploadBinary(
            objectPath,
            att.bytes,
            fileOptions: FileOptions(contentType: att.mimeType),
          );
    } catch (e) {
      _logger.e('Upload failed for ${att.name}: $e');
      return false;
    }

    try {
      await client.from('community_post_attachments').insert({
        'post_id': postId,
        'file_path': filePath,
        'file_type': att.fileType,
        'mime_type': att.mimeType,
      });
    } catch (e) {
      _logger.e('Failed to insert attachment row for ${att.name}: $e');
      return false;
    }

    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Post'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _bodyController,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Body',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _submitting ? null : _pickAttachment,
                      icon: const Icon(Icons.attach_file),
                      label: const Text('Add attachment (image/audio)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_attachments.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Attachments', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: _attachments.map((att) {
                        return Chip(
                          avatar: Icon(
                            att.fileType == 'image' ? Icons.image : Icons.audiotrack,
                            size: 16,
                          ),
                          label: Text(att.name),
                          onDeleted: _submitting
                              ? null
                              : () {
                                  setState(() {
                                    _attachments.remove(att);
                                  });
                                },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: Text(_submitting ? 'Posting...' : 'Post'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PendingAttachment {
  final String name;
  final Uint8List bytes;
  final String mimeType;
  final String fileType; // image or audio

  const _PendingAttachment({
    required this.name,
    required this.bytes,
    required this.mimeType,
    required this.fileType,
  });
}

class _CreatePostParsed {
  final bool success;
  final String postId;

  const _CreatePostParsed({
    required this.success,
    required this.postId,
  });
}
