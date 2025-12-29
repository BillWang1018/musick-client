import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'community_create_page.dart';
import '../services/socket_service.dart';

class CommunityPage extends StatefulWidget {
  final SocketService socketService;
  final String userId;
  final String? userName;

  const CommunityPage({
    super.key,
    required this.socketService,
    required this.userId,
    this.userName,
  });

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  final Logger _logger = Logger();
  final List<CommunityPostItem> _posts = [];
  bool _loading = false;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _fetchPosts();
  }

  Future<void> _fetchPosts() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
    });

    final payload = jsonEncode({
      'user_id': widget.userId,
      'before_id': '',
      'limit': 20,
      'include_attachment': true,
    });

    _logger.i('Requesting community posts (route 710): $payload');
    widget.socketService.sendToRoute(710, payload);

    final raw = await _waitForListPostsResponse(timeout: const Duration(seconds: 10));
    if (!mounted) return;

    if (raw == null) {
      setState(() {
        _loading = false;
      });
      _showSnack('No posts response received.');
      return;
    }

    final resp = _tryParseListPostsResponse(raw);
    if (resp == null) {
      setState(() {
        _loading = false;
      });
      _showSnack('Invalid posts response.');
      return;
    }

    if (!resp.success) {
      setState(() {
        _loading = false;
      });
      _showSnack(resp.message.isNotEmpty ? resp.message : 'Failed to load posts.');
      return;
    }

    final resolvedPosts = await _resolveAttachmentUrls(resp.posts);
    if (!mounted) return;

    setState(() {
      _posts
        ..clear()
        ..addAll(resolvedPosts);
      _loading = false;
    });
  }

  Future<List<CommunityPostItem>> _resolveAttachmentUrls(List<CommunityPostItem> posts) async {
    final client = Supabase.instance.client.storage;
    final List<CommunityPostItem> resolved = [];

    for (final post in posts) {
      final updatedAttachments = <CommunityAttachmentItem>[];
      for (final att in post.attachments) {
        final downloadUrl = await _toSignedUrl(client, att.filePath);
        updatedAttachments.add(att.copyWith(downloadUrl: downloadUrl ?? att.downloadUrl));
      }
      resolved.add(post.copyWith(attachments: updatedAttachments));
    }

    return resolved;
  }

  Future<String?> _toSignedUrl(SupabaseStorageClient client, String filePath) async {
    try {
      final segments = filePath.split('/');
      if (segments.length < 2) return null;
      final bucket = segments.first;
      final objectPath = segments.sublist(1).join('/');
      return await client.from(bucket).createSignedUrl(objectPath, 60 * 60);
    } catch (e) {
      _logger.w('Failed to create signed URL for $filePath: $e');
      return null;
    }
  }

  Future<String?> _waitForListPostsResponse({required Duration timeout}) async {
    try {
      return await widget.socketService.messages
          .where((m) => m.isNotEmpty)
          .where((m) => !m.startsWith('Error:'))
          .where((m) => m != 'Disconnected')
          .where(_looksLikeListPostsJson)
          .first
          .timeout(timeout);
    } catch (e) {
      _logger.w('Timed out waiting for list-posts response: $e');
      return null;
    }
  }

  bool _looksLikeListPostsJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return false;
      if (!decoded.containsKey('success')) return false;
      if (!decoded.containsKey('posts')) return false;
      final posts = decoded['posts'];
      return posts == null || posts is List;
    } catch (_) {
      return false;
    }
  }

  _ListPostsResponse? _tryParseListPostsResponse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;

      final success = decoded['success'];
      if (success is! bool) return null;

      final message = decoded['message'];
      final postsRaw = decoded['posts'];
      final hasMore = decoded['has_more'];
      final nextBefore = decoded['next_before'];

      final posts = <CommunityPostItem>[];
      if (postsRaw is List) {
        for (final entry in postsRaw) {
          if (entry is Map) {
            final parsed = CommunityPostItem.fromJson(Map<String, dynamic>.from(entry));
            posts.add(parsed);
          }
        }
      }

      return _ListPostsResponse(
        success: success,
        message: message is String ? message : '',
        posts: posts,
        hasMore: hasMore is bool ? hasMore : false,
        nextBefore: nextBefore is String ? nextBefore : '',
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _handleCreatePressed() async {
    setState(() {
      _creating = true;
    });

    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateCommunityPostPage(
          socketService: widget.socketService,
          userId: widget.userId,
          userName: widget.userName,
        ),
      ),
    );

    if (!mounted) return;

    setState(() {
      _creating = false;
    });

    if (created == true) {
      await _fetchPosts();
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Community'),
        actions: [
          IconButton(
            tooltip: 'Refresh posts',
            onPressed: _fetchPosts,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _creating ? null : _handleCreatePressed,
                    icon: const Icon(Icons.create),
                    label: Text(_creating ? 'Opening...' : 'Create new post'),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _fetchPosts,
              child: _buildPostsList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostsList() {
    if (_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
        ],
      );
    }

    if (_posts.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 200, child: Center(child: Text('No posts yet.'))),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _posts.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final post = _posts[index];
        return _buildPostCard(post);
      },
    );
  }

  Widget _buildPostCard(CommunityPostItem post) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _showPostDialog(post),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                post.title.isNotEmpty ? post.title : 'Untitled post',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                post.authorName.isNotEmpty ? post.authorName : post.authorId,
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 8),
              Text(
                post.body,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              _buildAttachments(post.attachments),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAttachments(List<CommunityAttachmentItem> attachments) {
    if (attachments.isEmpty) {
      return const Text('No attachments');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Attachments',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: attachments.map((att) {
            final label = att.filePath.isNotEmpty
                ? att.filePath
                : (att.fileType.isNotEmpty ? att.fileType : att.mimeType);
            return Chip(
              label: Text(label.isNotEmpty ? label : 'Attachment'),
              avatar: const Icon(Icons.attach_file, size: 16),
            );
          }).toList(),
        ),
      ],
    );
  }

  void _showPostDialog(CommunityPostItem post) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 600),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            post.title.isNotEmpty ? post.title : 'Untitled post',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      post.authorName.isNotEmpty ? post.authorName : post.authorId,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      post.body,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 16),
                    if (post.attachments.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Attachments',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          ...post.attachments.map((att) => _AttachmentPreview(att: att)),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AttachmentPreview extends StatelessWidget {
  final CommunityAttachmentItem att;

  const _AttachmentPreview({required this.att});

  bool get _isImage {
    final ft = att.fileType.toLowerCase();
    if (ft == 'image') return true;
    final mt = att.mimeType.toLowerCase();
    if (mt.startsWith('image/')) return true;
    final path = att.filePath.toLowerCase();
    return path.endsWith('.png') ||
        path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.gif') ||
        path.endsWith('.webp') ||
        path.endsWith('.bmp') ||
        path.endsWith('.heic');
  }

  bool get _isAudio {
    final ft = att.fileType.toLowerCase();
    if (ft == 'audio') return true;
    final mt = att.mimeType.toLowerCase();
    if (mt.startsWith('audio/')) return true;
    final path = att.filePath.toLowerCase();
    return path.endsWith('.mp3') ||
        path.endsWith('.m4a') ||
        path.endsWith('.wav') ||
        path.endsWith('.flac') ||
        path.endsWith('.aac') ||
        path.endsWith('.ogg') ||
        path.endsWith('.opus');
  }

  @override
  Widget build(BuildContext context) {
    final resolvedUrl = att.downloadUrl.isNotEmpty ? att.downloadUrl : att.filePath;
    if (_isImage) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            resolvedUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _AttachmentError(label: resolvedUrl),
          ),
        ),
      );
    }

    if (_isAudio) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _AudioAttachmentTile(url: resolvedUrl, label: resolvedUrl),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          const Icon(Icons.insert_drive_file, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              att.filePath.isNotEmpty ? att.filePath : 'Attachment',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _AudioAttachmentTile extends StatefulWidget {
  final String url;
  final String label;

  const _AudioAttachmentTile({required this.url, required this.label});

  @override
  State<_AudioAttachmentTile> createState() => _AudioAttachmentTileState();
}

class _AudioAttachmentTileState extends State<_AudioAttachmentTile> {
  final AudioPlayer _player = AudioPlayer();
  bool _loading = false;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() => _playing = false);
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      if (_playing) {
        await _player.pause();
        if (!mounted) return;
        setState(() => _playing = false);
      } else {
        await _player.play(UrlSource(widget.url));
        if (!mounted) return;
        setState(() => _playing = true);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to play audio.')),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          IconButton(
            icon: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(_playing ? Icons.pause_circle : Icons.play_circle),
            onPressed: _toggle,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentError extends StatelessWidget {
  final String label;

  const _AttachmentError({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey.shade200,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Icon(Icons.broken_image, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label.isNotEmpty ? label : 'Preview unavailable',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class CommunityPostItem {
  final String id;
  final String authorId;
  final String authorName;
  final String title;
  final String body;
  final String createdAt;
  final String updatedAt;
  final List<CommunityAttachmentItem> attachments;

  const CommunityPostItem({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    required this.attachments,
  });

  CommunityPostItem copyWith({List<CommunityAttachmentItem>? attachments}) {
    return CommunityPostItem(
      id: id,
      authorId: authorId,
      authorName: authorName,
      title: title,
      body: body,
      createdAt: createdAt,
      updatedAt: updatedAt,
      attachments: attachments ?? this.attachments,
    );
  }

  factory CommunityPostItem.fromJson(Map<String, dynamic> json) {
    final attachments = <CommunityAttachmentItem>[];
    final attachmentsRaw = json['attachments'] ?? json['community_post_attachments'];
    if (attachmentsRaw is List) {
      for (final entry in attachmentsRaw) {
        if (entry is Map) {
          attachments.add(
            CommunityAttachmentItem.fromJson(Map<String, dynamic>.from(entry)),
          );
        }
      }
    }

    return CommunityPostItem(
      id: json['id'] is String ? json['id'] as String : '',
      authorId: json['author_id'] is String ? json['author_id'] as String : '',
      authorName: json['author_name'] is String ? json['author_name'] as String : '',
      title: json['title'] is String ? json['title'] as String : '',
      body: json['body'] is String ? json['body'] as String : '',
      createdAt: json['created_at'] is String ? json['created_at'] as String : '',
      updatedAt: json['updated_at'] is String ? json['updated_at'] as String : '',
      attachments: attachments,
    );
  }
}

class CommunityAttachmentItem {
  final String id;
  final String postId;
  final String filePath;
  final String fileType;
  final String mimeType;
  final String createdAt;
  final String downloadUrl;

  const CommunityAttachmentItem({
    required this.id,
    required this.postId,
    required this.filePath,
    required this.fileType,
    required this.mimeType,
    required this.createdAt,
    this.downloadUrl = '',
  });

  CommunityAttachmentItem copyWith({String? downloadUrl}) {
    return CommunityAttachmentItem(
      id: id,
      postId: postId,
      filePath: filePath,
      fileType: fileType,
      mimeType: mimeType,
      createdAt: createdAt,
      downloadUrl: downloadUrl ?? this.downloadUrl,
    );
  }

  factory CommunityAttachmentItem.fromJson(Map<String, dynamic> json) {
    return CommunityAttachmentItem(
      id: json['id'] is String ? json['id'] as String : '',
      postId: json['post_id'] is String ? json['post_id'] as String : '',
      filePath: json['file_path'] is String ? json['file_path'] as String : '',
      fileType: json['file_type'] is String ? json['file_type'] as String : '',
      mimeType: json['mime_type'] is String ? json['mime_type'] as String : '',
      createdAt: json['created_at'] is String ? json['created_at'] as String : '',
      downloadUrl: '',
    );
  }
}

class _ListPostsResponse {
  final bool success;
  final String message;
  final List<CommunityPostItem> posts;
  final bool hasMore;
  final String nextBefore;

  const _ListPostsResponse({
    required this.success,
    required this.message,
    required this.posts,
    required this.hasMore,
    required this.nextBefore,
  });
}
