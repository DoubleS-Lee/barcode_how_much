import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/intl.dart';
import 'package:kakao_flutter_sdk_share/kakao_flutter_sdk_share.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme.dart';
import '../../shared/api/posts_api.dart';
import '../../shared/utils/device_id.dart';
import '../../shared/widgets/app_bottom_nav.dart';

// ── 프로바이더 ────────────────────────────────────────────

final _postsProvider = FutureProvider.autoDispose
    .family<List<PostModel>, String>((ref, search) async {
  final deviceUuid = await DeviceId.get();
  return PostsApi.fetchPosts(search: search.isEmpty ? null : search, deviceUuid: deviceUuid);
});

final _deviceUuidProvider = FutureProvider<String>((ref) => DeviceId.get());

// ── 메인 화면 ─────────────────────────────────────────────

class CommunityScreen extends ConsumerStatefulWidget {
  const CommunityScreen({super.key});

  @override
  ConsumerState<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends ConsumerState<CommunityScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String v) {
    setState(() => _searchQuery = v.trim());
  }

  @override
  Widget build(BuildContext context) {
    final postsAsync = ref.watch(_postsProvider(_searchQuery));

    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          '공유 게시판',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: kPrimaryDark,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: kPrimary),
            onPressed: () => ref.invalidate(_postsProvider(_searchQuery)),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── 검색바 ──
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: '제목 또는 내용으로 검색',
                hintStyle: GoogleFonts.inter(fontSize: 13, color: kOnSurfaceVariant),
                prefixIcon: const Icon(Icons.search, color: kOnSurfaceVariant, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18, color: kOnSurfaceVariant),
                        onPressed: () {
                          _searchCtrl.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: kBackground,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              style: GoogleFonts.inter(fontSize: 13),
            ),
          ),
          // ── 배너 광고 ──
          if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS))
            const _BannerAdWidget(),

          // ── 게시글 목록 ──
          Expanded(
            child: postsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ErrorView(
                  onRetry: () => ref.invalidate(_postsProvider(_searchQuery))),
              data: (posts) => posts.isEmpty
                  ? _EmptyView(isSearch: _searchQuery.isNotEmpty)
                  : RefreshIndicator(
                      onRefresh: () async =>
                          ref.invalidate(_postsProvider(_searchQuery)),
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                        itemCount: posts.length,
                        itemBuilder: (_, i) => _PostCard(
                          post: posts[i],
                          onRefresh: () =>
                              ref.invalidate(_postsProvider(_searchQuery)),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: kPrimary,
        icon: const Icon(Icons.edit_outlined, color: Colors.white),
        label: Text('글쓰기',
            style: GoogleFonts.plusJakartaSans(
                color: Colors.white, fontWeight: FontWeight.w700)),
        onPressed: () => _showPostDialog(context),
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 2),
    );
  }

  void _showPostDialog(BuildContext context, {PostModel? editing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PostFormSheet(
        editing: editing,
        onSaved: () => ref.invalidate(_postsProvider(_searchQuery)),
      ),
    );
  }
}

// ── 게시글 카드 ───────────────────────────────────────────

class _PostCard extends ConsumerStatefulWidget {
  final PostModel post;
  final VoidCallback onRefresh;
  const _PostCard({required this.post, required this.onRefresh});

  @override
  ConsumerState<_PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<_PostCard> {
  late PostModel _post;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
  }

  @override
  void didUpdateWidget(_PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _post = widget.post;
  }

  Future<void> _toggleLike() async {
    final uuid = await DeviceId.get();
    // Optimistic update
    setState(() {
      _post = _post.copyWith(
        liked: !_post.liked,
        likeCount: _post.liked ? _post.likeCount - 1 : _post.likeCount + 1,
      );
    });
    try {
      final result = await PostsApi.likePost(id: _post.id, deviceUuid: uuid);
      setState(() {
        _post = _post.copyWith(
          liked: result['liked'] as bool,
          likeCount: result['like_count'] as int,
        );
      });
    } catch (_) {
      // Revert on failure
      setState(() {
        _post = widget.post;
      });
    }
  }

  Future<void> _report(BuildContext context) async {
    if (_post.reported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이미 신고한 글입니다')),
      );
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('신고', style: GoogleFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.w700)),
        content: Text('이 게시글을 신고하시겠어요?\n허위 신고 시 서비스 이용이 제한될 수 있습니다.',
            style: GoogleFonts.inter(fontSize: 14, height: 1.5)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text('취소', style: GoogleFonts.inter(color: kOnSurfaceVariant))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: Text('신고', style: GoogleFonts.inter(color: kError, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      final uuid = await DeviceId.get();
      final result = await PostsApi.reportPost(id: _post.id, deviceUuid: uuid);
      if (mounted) {
        setState(() {
          _post = _post.copyWith(
            reported: true,
            reportCount: result['report_count'] as int,
          );
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('신고가 접수되었습니다')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('신고 처리 중 오류가 발생했습니다')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final deviceAsync = ref.watch(_deviceUuidProvider);
    final myUuid = deviceAsync.valueOrNull;
    final isOwner = myUuid != null && myUuid.startsWith(_post.authorId);

    // 20회 이상 신고된 글은 차단
    if (_post.reportCount >= 20) {
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(children: [
          Icon(Icons.block, size: 16, color: Colors.grey.shade400),
          const SizedBox(width: 8),
          Text('신고로 제재된 글입니다',
              style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade500)),
        ]),
      );
    }

    return GestureDetector(
      onTap: () => _showDetail(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (_post.imageUrl != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                _post.imageUrl!,
                width: double.infinity,
                height: 140,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Row(children: [
            Expanded(
              child: Text(
                _post.title,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: kOnSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isOwner)
              Row(children: [
                _SmallButton(
                  icon: Icons.edit_outlined,
                  color: kPrimary,
                  onTap: () => _showEdit(context),
                ),
                const SizedBox(width: 4),
                _SmallButton(
                  icon: Icons.delete_outline,
                  color: kError,
                  onTap: () => _confirmDelete(context),
                ),
              ]),
          ]),
          const SizedBox(height: 6),
          const SizedBox(height: 4),
          Text(
            '${NumberFormat('#,###').format(_post.price)}원',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 16, fontWeight: FontWeight.w800, color: kPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            _post.content,
            style:
                GoogleFonts.inter(fontSize: 13, color: kOnSurfaceVariant, height: 1.5),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          Row(children: [
            // 작성자
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: kPrimary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_post.authorId}...',
                style: GoogleFonts.inter(
                    fontSize: 10, fontWeight: FontWeight.w600, color: kPrimary),
              ),
            ),
            if (_post.shareLocation) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF16A34A).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(children: [
                  const Icon(Icons.place_outlined,
                      size: 10, color: Color(0xFF16A34A)),
                  const SizedBox(width: 3),
                  Text(
                    _post.locationHint ?? '위치 공개',
                    style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF16A34A)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ]),
              ),
            ],
            const Spacer(),
            // 조회수
            Icon(Icons.visibility_outlined,
                size: 12, color: kOnSurfaceVariant.withValues(alpha: 0.7)),
            const SizedBox(width: 2),
            Text(
              '${_post.viewCount}',
              style: GoogleFonts.inter(fontSize: 10, color: kOnSurfaceVariant),
            ),
            const SizedBox(width: 8),
            // 좋아요 수 (탭 불가 — 상세에서만 가능)
            Icon(Icons.favorite_border, size: 12,
                color: kOnSurfaceVariant.withValues(alpha: 0.7)),
            const SizedBox(width: 2),
            Text(
              '${_post.likeCount}',
              style: GoogleFonts.inter(fontSize: 10, color: kOnSurfaceVariant),
            ),
            const SizedBox(width: 8),
            // 댓글수
            Icon(Icons.chat_bubble_outline,
                size: 12, color: kOnSurfaceVariant.withValues(alpha: 0.7)),
            const SizedBox(width: 2),
            Text(
              '${_post.commentCount}',
              style: GoogleFonts.inter(fontSize: 10, color: kOnSurfaceVariant),
            ),
            const SizedBox(width: 8),
            Text(
              DateFormat('MM.dd HH:mm').format(_post.createdAt.toLocal()),
              style: GoogleFonts.inter(fontSize: 11, color: kOnSurfaceVariant),
            ),
          ]),
        ]),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PostDetailSheet(post: _post, onLikeChanged: (updated) {
        setState(() => _post = updated);
      }),
    );
  }

  void _showEdit(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PostFormSheet(editing: _post, onSaved: widget.onRefresh),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('게시글 삭제',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 17, fontWeight: FontWeight.w700)),
        content: Text('게시글을 삭제할까요?',
            style: GoogleFonts.inter(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('취소',
                style: GoogleFonts.inter(color: kOnSurfaceVariant)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final uuid = await DeviceId.get();
              await PostsApi.deletePost(id: _post.id, deviceUuid: uuid);
              widget.onRefresh();
            },
            child: Text('삭제',
                style: GoogleFonts.inter(
                    color: kError, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

// ── 게시글 상세 바텀시트 ──────────────────────────────────

class _PostDetailSheet extends StatefulWidget {
  final PostModel post;
  final void Function(PostModel updated)? onLikeChanged;
  const _PostDetailSheet({required this.post, this.onLikeChanged});

  @override
  State<_PostDetailSheet> createState() => _PostDetailSheetState();
}

class _PostDetailSheetState extends State<_PostDetailSheet> {
  late PostModel _post;
  List<PostCommentModel>? _comments;
  bool _commentsLoading = false;
  bool _commentSubmitting = false;
  final TextEditingController _commentCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    _loadComments();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    setState(() => _commentsLoading = true);
    try {
      final uuid = await DeviceId.get();
      final comments = await PostsApi.fetchComments(id: _post.id, deviceUuid: uuid);
      if (mounted) setState(() => _comments = comments);
    } catch (_) {
      if (mounted) setState(() => _comments = []);
    } finally {
      if (mounted) setState(() => _commentsLoading = false);
    }
  }

  Future<void> _toggleLike() async {
    final uuid = await DeviceId.get();
    final wasLiked = _post.liked;
    setState(() {
      _post = _post.copyWith(
        liked: !wasLiked,
        likeCount: wasLiked ? _post.likeCount - 1 : _post.likeCount + 1,
      );
    });
    try {
      final result = await PostsApi.likePost(id: _post.id, deviceUuid: uuid);
      if (mounted) {
        setState(() {
          _post = _post.copyWith(
            liked: result['liked'] as bool,
            likeCount: result['like_count'] as int,
          );
        });
        widget.onLikeChanged?.call(_post);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _post = _post.copyWith(liked: wasLiked,
              likeCount: wasLiked ? _post.likeCount + 1 : _post.likeCount - 1);
        });
      }
    }
  }

  Future<void> _report() async {
    if (_post.reported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이미 신고한 글입니다')),
      );
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('신고', style: GoogleFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.w700)),
        content: Text('이 게시글을 신고하시겠어요?\n허위 신고 시 서비스 이용이 제한될 수 있습니다.',
            style: GoogleFonts.inter(fontSize: 14, height: 1.5)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text('취소', style: GoogleFonts.inter(color: kOnSurfaceVariant))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: Text('신고', style: GoogleFonts.inter(color: kError, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      final uuid = await DeviceId.get();
      final result = await PostsApi.reportPost(id: _post.id, deviceUuid: uuid);
      if (mounted) {
        final updated = _post.copyWith(reported: true, reportCount: result['report_count'] as int);
        setState(() => _post = updated);
        widget.onLikeChanged?.call(updated);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('신고가 접수되었습니다')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('신고 처리 중 오류가 발생했습니다')),
      );
    }
  }

  void _showShareSheet() {
    final postUrl = 'https://eolmaeossjeo.com/posts/${_post.id}';
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 20),
            Text('공유하기', style: GoogleFonts.plusJakartaSans(
                fontSize: 18, fontWeight: FontWeight.w800, color: kOnSurface)),
            const SizedBox(height: 20),
            // 링크 복사
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: postUrl));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('링크가 복사되었습니다')),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: kBackground,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: kPrimary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.link, color: kPrimary, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('링크 복사', style: GoogleFonts.inter(
                        fontSize: 15, fontWeight: FontWeight.w600, color: kOnSurface)),
                    Text('게시글 링크를 클립보드에 복사합니다',
                        style: GoogleFonts.inter(fontSize: 12, color: kOnSurfaceVariant)),
                  ]),
                ]),
              ),
            ),
            const SizedBox(height: 10),
            // 카카오톡 공유
            GestureDetector(
              onTap: () async {
                Navigator.pop(context);
                await _shareToKakao();
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE500).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFEE500)),
                ),
                child: Row(children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE500),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text('K', style: GoogleFonts.plusJakartaSans(
                          fontSize: 18, fontWeight: FontWeight.w900,
                          color: const Color(0xFF3A1D1D))),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('카카오톡으로 공유', style: GoogleFonts.inter(
                        fontSize: 15, fontWeight: FontWeight.w600, color: kOnSurface)),
                    Text('카카오톡 친구에게 게시글을 공유합니다',
                        style: GoogleFonts.inter(fontSize: 12, color: kOnSurfaceVariant)),
                  ]),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareToKakao() async {
    try {
      final template = FeedTemplate(
        content: Content(
          title: _post.title,
          description: '${NumberFormat('#,###').format(_post.price)}원 · ${_post.content.length > 50 ? '${_post.content.substring(0, 50)}...' : _post.content}',
          imageUrl: Uri.parse('https://eolmaeossjeo.com/og-image.png'),
          link: Link(
            webUrl: Uri.parse('https://eolmaeossjeo.com/posts/${_post.id}'),
            mobileWebUrl: Uri.parse('https://eolmaeossjeo.com/posts/${_post.id}'),
          ),
        ),
      );
      if (await ShareClient.instance.isKakaoTalkSharingAvailable()) {
        final uri = await ShareClient.instance.shareDefault(template: template);
        await ShareClient.instance.launchKakaoTalk(uri);
      } else {
        final uri = await WebSharerClient.instance.makeDefaultUrl(template: template);
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('카카오톡 공유 실패: $e')),
        );
      }
    }
  }

  Future<void> _submitComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _commentSubmitting = true);
    try {
      final uuid = await DeviceId.get();
      final comment =
          await PostsApi.addComment(id: _post.id, deviceUuid: uuid, content: text);
      _commentCtrl.clear();
      if (mounted) setState(() => _comments = [...(_comments ?? []), comment]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('댓글 등록 실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _commentSubmitting = false);
    }
  }

  Future<void> _deleteComment(PostCommentModel comment) async {
    try {
      final uuid = await DeviceId.get();
      await PostsApi.deleteComment(
          postId: _post.id, commentId: comment.id, deviceUuid: uuid);
      if (mounted) {
        setState(() =>
            _comments = _comments?.where((c) => c.id != comment.id).toList());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('댓글 삭제에 실패했어요')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 드래그 핸들
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 48,
                height: 4,
                decoration: BoxDecoration(
                    color: kOutlineVariant,
                    borderRadius: BorderRadius.circular(2)),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 작성자 + 날짜
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: kPrimary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${_post.authorId}...',
                            style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: kPrimary),
                          ),
                        ),
                        const Spacer(),
                        Icon(Icons.visibility_outlined,
                            size: 13,
                            color: kOnSurfaceVariant.withValues(alpha: 0.7)),
                        const SizedBox(width: 3),
                        Text('${_post.viewCount}',
                            style: GoogleFonts.inter(
                                fontSize: 12, color: kOnSurfaceVariant)),
                        const SizedBox(width: 12),
                        Text(
                          DateFormat('yyyy.MM.dd HH:mm')
                              .format(_post.createdAt.toLocal()),
                          style: GoogleFonts.inter(
                              fontSize: 12, color: kOnSurfaceVariant),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      // 제목
                      Text(
                        _post.title,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: kOnSurface),
                      ),
                      const SizedBox(height: 8),
                      // 가격
                      Text(
                        '${NumberFormat('#,###').format(_post.price)}원',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: kPrimary),
                      ),
                      if (_post.shareLocation) ...[
                        const SizedBox(height: 6),
                        Row(children: [
                          const Icon(Icons.place_outlined,
                              size: 14, color: Color(0xFF16A34A)),
                          const SizedBox(width: 4),
                          Text(
                            _post.locationHint ?? '위치 공개',
                            style: GoogleFonts.inter(
                                fontSize: 12,
                                color: const Color(0xFF16A34A),
                                fontWeight: FontWeight.w600),
                          ),
                        ]),
                      ],
                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 12),
                      // 본문
                      Text(
                        _post.content,
                        style: GoogleFonts.inter(
                            fontSize: 14, color: kOnSurface, height: 1.7),
                      ),
                      if (_post.imageUrl != null) ...[
                        const SizedBox(height: 16),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            _post.imageUrl!,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),

                      // ── 가격 조회 섹션 ──
                      if (_post.priceLookups.isNotEmpty) ...[
                        const Divider(),
                        const SizedBox(height: 12),
                        Text('온라인 최저가',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: kOnSurface)),
                        const SizedBox(height: 8),
                        ..._post.priceLookups.map((pl) => _PriceLookupRow(pl: pl)),
                        const SizedBox(height: 12),
                      ],

                      // ── 좋아요 / 공유 / 신고 버튼 ──
                      Row(children: [
                        // 좋아요
                        GestureDetector(
                          onTap: _toggleLike,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: _post.liked
                                  ? const Color(0xFFEF4444).withValues(alpha: 0.1)
                                  : kBackground,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _post.liked
                                    ? const Color(0xFFEF4444)
                                    : kOutlineVariant,
                              ),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(
                                _post.liked ? Icons.favorite : Icons.favorite_border,
                                size: 18,
                                color: _post.liked
                                    ? const Color(0xFFEF4444)
                                    : kOnSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${_post.likeCount}',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: _post.liked
                                      ? const Color(0xFFEF4444)
                                      : kOnSurfaceVariant,
                                ),
                              ),
                            ]),
                          ),
                        ),
                        const Spacer(),
                        // 공유
                        GestureDetector(
                          onTap: _showShareSheet,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: kBackground,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: kOutlineVariant),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.share_outlined, size: 18, color: kPrimary),
                              const SizedBox(width: 6),
                              Text('공유', style: GoogleFonts.plusJakartaSans(
                                  fontSize: 14, fontWeight: FontWeight.w600, color: kPrimary)),
                            ]),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 신고
                        GestureDetector(
                          onTap: _report,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: _post.reported
                                  ? kError.withValues(alpha: 0.08)
                                  : kBackground,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _post.reported ? kError : kOutlineVariant,
                              ),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(
                                _post.reported ? Icons.thumb_down : Icons.thumb_down_outlined,
                                size: 18,
                                color: _post.reported ? kError : kOnSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                              Text('신고', style: GoogleFonts.plusJakartaSans(
                                  fontSize: 14, fontWeight: FontWeight.w600,
                                  color: _post.reported ? kError : kOnSurfaceVariant)),
                            ]),
                          ),
                        ),
                      ]),

                      // ── 댓글 섹션 ──
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 12),
                      Text(
                        '댓글 ${_comments?.length ?? 0}',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: kOnSurface),
                      ),
                      const SizedBox(height: 8),
                      if (_commentsLoading)
                        const Center(
                            child: Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ))
                      else if (_comments == null || _comments!.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text('아직 댓글이 없어요. 첫 댓글을 남겨보세요!',
                              style: GoogleFonts.inter(
                                  fontSize: 13, color: kOnSurfaceVariant)),
                        )
                      else
                        Column(
                          children: _comments!
                              .map((c) => _CommentRow(
                                    comment: c,
                                    onDelete: () => _deleteComment(c),
                                  ))
                              .toList(),
                        ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
              // ── 댓글 입력창 ──
              Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                decoration: BoxDecoration(
                  color: kSurface,
                  border: Border(top: BorderSide(color: kOutlineVariant)),
                ),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _commentCtrl,
                      decoration: InputDecoration(
                        hintText: '댓글을 입력하세요',
                        hintStyle: GoogleFonts.inter(
                            fontSize: 13, color: kOnSurfaceVariant),
                        filled: true,
                        fillColor: kBackground,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      style: GoogleFonts.inter(fontSize: 13),
                      maxLength: 500,
                      maxLines: null,
                      buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _commentSubmitting
                      ? const SizedBox(
                          width: 40,
                          height: 40,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : IconButton(
                          onPressed: _submitComment,
                          icon: const Icon(Icons.send_rounded, color: kPrimary),
                          style: IconButton.styleFrom(
                            backgroundColor: kPrimary.withValues(alpha: 0.1),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 가격 조회 행 ──────────────────────────────────────────

class _PriceLookupRow extends StatelessWidget {
  final PriceLookupModel pl;
  const _PriceLookupRow({required this.pl});

  String get _platformLabel => switch (pl.platform) {
    'naver' => '네이버쇼핑',
    'coupang' => '쿠팡',
    _ => pl.platform,
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: kOnSurfaceVariant.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(_platformLabel,
              style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: kOnSurface)),
        ),
        const SizedBox(width: 10),
        if (pl.price != null)
          Text(
            '${NumberFormat('#,###').format(pl.price)}원',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 14, fontWeight: FontWeight.w700, color: kPrimary),
          )
        else
          Text('정보 없음',
              style: GoogleFonts.inter(
                  fontSize: 13, color: kOnSurfaceVariant)),
        if (pl.productName != null) ...[
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              pl.productName!,
              style: GoogleFonts.inter(fontSize: 11, color: kOnSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ] else
          const Spacer(),
        if (pl.productUrl != null) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () async {
              final uri = Uri.tryParse(pl.productUrl!);
              if (uri != null && await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: kPrimary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kPrimary.withValues(alpha: 0.2)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.open_in_new, size: 11, color: kPrimary),
                const SizedBox(width: 3),
                Text(
                  '상품 보기',
                  style: GoogleFonts.inter(
                      fontSize: 11, fontWeight: FontWeight.w600, color: kPrimary),
                ),
              ]),
            ),
          ),
        ],
      ]),
    );
  }
}

// ── 댓글 행 ──────────────────────────────────────────────

class _CommentRow extends StatelessWidget {
  final PostCommentModel comment;
  final VoidCallback onDelete;
  const _CommentRow({required this.comment, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: kPrimary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              comment.authorId.isNotEmpty ? comment.authorId[0].toUpperCase() : '?',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, fontWeight: FontWeight.w700, color: kPrimary),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(
                '${comment.authorId}...',
                style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: kPrimary),
              ),
              const SizedBox(width: 6),
              Text(
                DateFormat('MM.dd HH:mm').format(comment.createdAt.toLocal()),
                style: GoogleFonts.inter(
                    fontSize: 10, color: kOnSurfaceVariant),
              ),
              const Spacer(),
              if (comment.isOwner)
                GestureDetector(
                  onTap: onDelete,
                  child: Icon(Icons.close,
                      size: 14,
                      color: kOnSurfaceVariant.withValues(alpha: 0.6)),
                ),
            ]),
            const SizedBox(height: 2),
            Text(
              comment.content,
              style: GoogleFonts.inter(
                  fontSize: 13, color: kOnSurface, height: 1.5),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ── 게시글 작성/수정 바텀시트 ────────────────────────────


class _PostFormSheet extends ConsumerStatefulWidget {
  final PostModel? editing;
  final VoidCallback onSaved;
  const _PostFormSheet({this.editing, required this.onSaved});

  @override
  ConsumerState<_PostFormSheet> createState() => _PostFormSheetState();
}

class _PostFormSheetState extends ConsumerState<_PostFormSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _contentCtrl;
  late final TextEditingController _priceCtrl;
  final TextEditingController _locationHintCtrl = TextEditingController();

  File? _imageFile;
  String? _existingImageUrl; // 수정 시 기존 이미지
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.editing?.title ?? '');
    _contentCtrl = TextEditingController(text: widget.editing?.content ?? '');
    _priceCtrl = TextEditingController(
      text: widget.editing != null && widget.editing!.price > 0
          ? widget.editing!.price.toString()
          : '',
    );
    _existingImageUrl = widget.editing?.imageUrl;
    if (widget.editing != null && widget.editing!.shareLocation &&
        widget.editing!.locationHint != null) {
      _locationHintCtrl.text = widget.editing!.locationHint!;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    _priceCtrl.dispose();
    _locationHintCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 80, maxWidth: 1280);
    if (picked != null && mounted) {
      setState(() {
        _imageFile = File(picked.path);
        _existingImageUrl = null; // 새 이미지로 교체
      });
    }
  }

  void _showImagePickerSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined, color: kPrimary),
              title: Text('카메라로 촬영', style: GoogleFonts.inter(fontSize: 15)),
              onTap: () { Navigator.pop(context); _pickImage(ImageSource.camera); },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: kPrimary),
              title: Text('갤러리에서 선택', style: GoogleFonts.inter(fontSize: 15)),
              onTap: () { Navigator.pop(context); _pickImage(ImageSource.gallery); },
            ),
            if (_imageFile != null || _existingImageUrl != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: kError),
                title: Text('사진 제거', style: GoogleFonts.inter(fontSize: 15, color: kError)),
                onTap: () {
                  setState(() { _imageFile = null; _existingImageUrl = null; });
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    final content = _contentCtrl.text.trim();
    final price =
        int.tryParse(_priceCtrl.text.replaceAll(',', '').trim()) ?? 0;
    if (title.isEmpty || content.isEmpty || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('제목, 내용, 금액은 필수 항목입니다')),
      );
      return;
    }

    setState(() => _loading = true);
    final locationHint = _locationHintCtrl.text.trim().isEmpty
        ? null
        : _locationHintCtrl.text.trim();
    final bool shareLocation = locationHint != null;

    try {
      final uuid = await DeviceId.get();
      const String? barcode = null;

      // 새 이미지가 있으면 업로드
      String? imageUrl = _existingImageUrl;
      if (_imageFile != null) {
        imageUrl = await PostsApi.uploadImage(_imageFile!);
      }

      if (widget.editing != null) {
        await PostsApi.updatePost(
          id: widget.editing!.id,
          deviceUuid: uuid,
          title: title,
          content: content,
          price: price,
          barcode: barcode,
          imageUrl: imageUrl,
          shareLocation: shareLocation,
          latitude: null,
          longitude: null,
          locationHint: locationHint,
        );
      } else {
        await PostsApi.createPost(
          deviceUuid: uuid,
          title: title,
          content: content,
          price: price,
          barcode: barcode,
          imageUrl: imageUrl,
          shareLocation: shareLocation,
          latitude: null,
          longitude: null,
          locationHint: locationHint,
        );
      }
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        String msg = e.toString();
        if (e is DioException && e.response?.data != null) {
          msg = e.response!.data.toString();
        }
        debugPrint('[Post] Error: $msg');
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('오류: $msg'), duration: const Duration(seconds: 6)));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.editing != null;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 48,
                  height: 4,
                  decoration: BoxDecoration(
                      color: kOutlineVariant,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Text(
                isEditing ? '게시글 수정' : '할인 정보 공유',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: kOnSurface),
              ),
              const SizedBox(height: 16),

              // ── 제목 ──
              TextField(
                controller: _titleCtrl,
                decoration: InputDecoration(
                  labelText: '제목 *',
                  hintText: '예: 이마트 콜라 1.5L 반값 할인 중!',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
                style: GoogleFonts.inter(fontSize: 14),
                maxLength: 200,
              ),
              const SizedBox(height: 4),

              // ── 위치 ──
              TextField(
                controller: _locationHintCtrl,
                decoration: InputDecoration(
                  labelText: '장소명 (선택사항)',
                  hintText: '예: 이마트 왕십리점',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  prefixIcon: const Icon(Icons.place_outlined, size: 18),
                ),
                style: GoogleFonts.inter(fontSize: 14),
              ),
              const SizedBox(height: 12),

              // ── 금액 ──
              TextField(
                controller: _priceCtrl,
                decoration: InputDecoration(
                  labelText: '금액 *',
                  hintText: '예: 4900',
                  suffixText: '원',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
                style: GoogleFonts.inter(fontSize: 14),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              const SizedBox(height: 12),

              // ── 내용 ──
              TextField(
                controller: _contentCtrl,
                decoration: InputDecoration(
                  labelText: '내용 *',
                  hintText: '할인 정보, 매장, 기간 등 자세히 적어주세요',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
                style: GoogleFonts.inter(fontSize: 14),
                maxLines: 3,
                maxLength: 1000,
              ),
              const SizedBox(height: 12),

              // ── 사진 첨부 ──
              GestureDetector(
                onTap: _showImagePickerSheet,
                child: _imageFile != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Stack(
                          children: [
                            Image.file(
                              _imageFile!,
                              width: double.infinity,
                              height: 180,
                              fit: BoxFit.cover,
                            ),
                            Positioned(
                              top: 8, right: 8,
                              child: GestureDetector(
                                onTap: () => setState(() { _imageFile = null; _existingImageUrl = null; }),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Icon(Icons.close, color: Colors.white, size: 16),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : _existingImageUrl != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Stack(
                              children: [
                                Image.network(
                                  _existingImageUrl!,
                                  width: double.infinity,
                                  height: 180,
                                  fit: BoxFit.cover,
                                ),
                                Positioned(
                                  top: 8, right: 8,
                                  child: GestureDetector(
                                    onTap: () => setState(() { _existingImageUrl = null; }),
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: const Icon(Icons.close, color: Colors.white, size: 16),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Container(
                            width: double.infinity,
                            height: 80,
                            decoration: BoxDecoration(
                              color: kBackground,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: kOutlineVariant, style: BorderStyle.solid),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.add_photo_alternate_outlined, color: kOnSurfaceVariant, size: 22),
                                const SizedBox(width: 8),
                                Text('사진 첨부 (선택사항)',
                                    style: GoogleFonts.inter(fontSize: 13, color: kOnSurfaceVariant)),
                              ],
                            ),
                          ),
              ),
              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _loading
                      ? const CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2)
                      : Text(
                          isEditing ? '수정하기' : '게시하기',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

}

// ── 보조 위젯 ─────────────────────────────────────────────

class _SmallButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _SmallButton(
      {required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final bool isSearch;
  const _EmptyView({this.isSearch = false});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(
          isSearch ? Icons.search_off : Icons.campaign_outlined,
          size: 64,
          color: kOnSurfaceVariant.withValues(alpha: 0.3),
        ),
        const SizedBox(height: 16),
        Text(
          isSearch ? '검색 결과가 없어요' : '아직 게시글이 없어요',
          style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: kOnSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Text(
          isSearch ? '다른 검색어로 시도해보세요' : '첫 번째로 할인 정보를 공유해보세요!',
          style: GoogleFonts.inter(fontSize: 13, color: kOnSurfaceVariant),
        ),
      ]),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.wifi_off,
            size: 48, color: kOnSurfaceVariant.withValues(alpha: 0.3)),
        const SizedBox(height: 16),
        Text('불러오기 실패',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: kOnSurfaceVariant)),
        const SizedBox(height: 12),
        TextButton(onPressed: onRetry, child: const Text('다시 시도')),
      ]),
    );
  }
}

// ── 배너 광고 위젯 ─────────────────────────────────────────

class _BannerAdWidget extends StatefulWidget {
  const _BannerAdWidget();

  @override
  State<_BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<_BannerAdWidget> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  void _loadAd() {
    // 실제 배포 시 ca-app-pub-XXXXX/YYYYY 형태의 실제 광고 ID로 교체하세요.
    final adUnitId = Platform.isAndroid
        ? 'ca-app-pub-3940256099942544/6300978111' // Google 테스트 ID
        : 'ca-app-pub-3940256099942544/2934735716'; // Google 테스트 ID (iOS)
    _ad = BannerAd(
      adUnitId: adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          _ad = null;
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _ad == null) return const SizedBox.shrink();
    return Container(
      alignment: Alignment.center,
      width: _ad!.size.width.toDouble(),
      height: _ad!.size.height.toDouble(),
      child: AdWidget(ad: _ad!),
    );
  }
}
