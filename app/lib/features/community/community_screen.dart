import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme.dart';
import '../../shared/api/posts_api.dart';
import '../../shared/api/scan_api.dart';
import '../../shared/utils/device_id.dart';
import '../../shared/widgets/app_bottom_nav.dart';

// ── 프로바이더 ────────────────────────────────────────────

final _postsProvider = FutureProvider.autoDispose
    .family<List<PostModel>, String>((ref, search) async {
  final deviceUuid = await DeviceId.get();
  return PostsApi.fetchPosts(search: search.isEmpty ? null : search, deviceUuid: deviceUuid);
});

final _deviceUuidProvider = FutureProvider<String>((ref) => DeviceId.get());

// ── 위치 옵션 열거형 ──────────────────────────────────────

enum _LocationOption { none, fromProduct, current, manual }

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

  @override
  Widget build(BuildContext context) {
    final deviceAsync = ref.watch(_deviceUuidProvider);
    final myUuid = deviceAsync.valueOrNull;
    final isOwner = myUuid != null && myUuid.startsWith(_post.authorId);

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
            // 좋아요
            GestureDetector(
              onTap: _toggleLike,
              child: Row(children: [
                Icon(
                  _post.liked ? Icons.favorite : Icons.favorite_border,
                  size: 14,
                  color: _post.liked ? const Color(0xFFEF4444) : kOnSurfaceVariant,
                ),
                const SizedBox(width: 2),
                Text(
                  '${_post.likeCount}',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: _post.liked ? const Color(0xFFEF4444) : kOnSurfaceVariant,
                  ),
                ),
              ]),
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

                      // ── 좋아요 버튼 ──
                      Row(children: [
                        const Spacer(),
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
                                _post.liked
                                    ? Icons.favorite
                                    : Icons.favorite_border,
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

class _ScannedProduct {
  final String barcode;
  final String name;
  final String? imageUrl;
  final double? latitude;
  final double? longitude;
  _ScannedProduct({
    required this.barcode,
    required this.name,
    this.imageUrl,
    this.latitude,
    this.longitude,
  });
}

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
  final TextEditingController _manualBarcodeCtrl = TextEditingController();
  final TextEditingController _locationHintCtrl = TextEditingController();

  // null = 선택 안함, '__MANUAL__' = 직접 입력, else = barcode
  String? _dropdownBarcode;
  _LocationOption _locationOption = _LocationOption.none;

  bool _loading = false;
  bool _loadingProducts = true;
  List<_ScannedProduct> _products = [];

  String? get _effectiveBarcode {
    if (_dropdownBarcode == null) return null;
    if (_dropdownBarcode == '__MANUAL__') {
      final t = _manualBarcodeCtrl.text.trim();
      return t.isEmpty ? null : t;
    }
    return _dropdownBarcode;
  }

  _ScannedProduct? get _selectedProduct {
    if (_dropdownBarcode == null || _dropdownBarcode == '__MANUAL__') return null;
    try {
      return _products.firstWhere((p) => p.barcode == _dropdownBarcode);
    } catch (_) {
      return null;
    }
  }

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
    if (widget.editing?.barcode != null) {
      _dropdownBarcode = widget.editing!.barcode!;
    }
    if (widget.editing != null && widget.editing!.shareLocation) {
      if (widget.editing!.locationHint != null) {
        _locationOption = _LocationOption.manual;
        _locationHintCtrl.text = widget.editing!.locationHint!;
      } else if (widget.editing!.latitude != null) {
        _locationOption = _LocationOption.current;
      }
    }
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    try {
      final uuid = await DeviceId.get();
      final history = await ScanApi.getHistory(uuid);
      final items = history['items'] as List? ?? [];
      final seen = <String>{};
      final products = <_ScannedProduct>[];
      for (final item in items) {
        if (item['scan_type'] != 'product') continue;
        final product = item['product'] as Map<String, dynamic>?;
        final barcode = product?['barcode'] as String?;
        final name = product?['name'] as String?;
        if (barcode == null || name == null || seen.contains(barcode)) continue;
        seen.add(barcode);
        products.add(_ScannedProduct(
          barcode: barcode,
          name: name,
          imageUrl: product?['image_url'] as String?,
          latitude: (item['latitude'] as num?)?.toDouble(),
          longitude: (item['longitude'] as num?)?.toDouble(),
        ));
      }
      if (mounted) {
        setState(() {
          _products = products;
          _loadingProducts = false;
          if (_dropdownBarcode != null && _dropdownBarcode != '__MANUAL__') {
            final exists = products.any((p) => p.barcode == _dropdownBarcode);
            if (!exists) {
              _manualBarcodeCtrl.text = _dropdownBarcode!;
              _dropdownBarcode = '__MANUAL__';
            }
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingProducts = false);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    _priceCtrl.dispose();
    _manualBarcodeCtrl.dispose();
    _locationHintCtrl.dispose();
    super.dispose();
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
    double? lat, lng;
    String? locationHint;
    bool shareLocation = _locationOption != _LocationOption.none;

    try {
      switch (_locationOption) {
        case _LocationOption.none:
          break;
        case _LocationOption.fromProduct:
          final p = _selectedProduct;
          if (p?.latitude != null && p?.longitude != null) {
            lat = p!.latitude;
            lng = p.longitude;
          } else {
            shareLocation = false;
          }
        case _LocationOption.current:
          final pos = await Geolocator.getCurrentPosition();
          lat = pos.latitude;
          lng = pos.longitude;
        case _LocationOption.manual:
          final hint = _locationHintCtrl.text.trim();
          locationHint = hint.isNotEmpty ? hint : null;
          if (locationHint == null) shareLocation = false;
      }

      final uuid = await DeviceId.get();
      final barcode = _effectiveBarcode;

      if (widget.editing != null) {
        await PostsApi.updatePost(
          id: widget.editing!.id,
          deviceUuid: uuid,
          title: title,
          content: content,
          price: price,
          barcode: barcode,
          shareLocation: shareLocation,
          latitude: lat,
          longitude: lng,
          locationHint: locationHint,
        );
      } else {
        await PostsApi.createPost(
          deviceUuid: uuid,
          title: title,
          content: content,
          price: price,
          barcode: barcode,
          shareLocation: shareLocation,
          latitude: lat,
          longitude: lng,
          locationHint: locationHint,
        );
      }
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('오류: $e')));
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

              // ── 관련 상품 ──
              if (_loadingProducts)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(),
                )
              else
                DropdownButtonFormField<String?>(
                  value: _dropdownBarcode,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: '관련 상품 (선택사항)',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                  style: GoogleFonts.inter(fontSize: 14, color: kOnSurface),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text('선택 안함',
                          style: GoogleFonts.inter(
                              fontSize: 14, color: kOnSurfaceVariant)),
                    ),
                    ..._products.map((p) => DropdownMenuItem<String?>(
                          value: p.barcode,
                          child: Text(p.name,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(fontSize: 14)),
                        )),
                    DropdownMenuItem<String?>(
                      value: '__MANUAL__',
                      child: Text('직접 입력...',
                          style: GoogleFonts.inter(
                              fontSize: 14, color: kPrimary)),
                    ),
                  ],
                  onChanged: (v) => setState(() {
                    _dropdownBarcode = v;
                    if (_locationOption == _LocationOption.fromProduct &&
                        v == null) {
                      _locationOption = _LocationOption.none;
                    }
                  }),
                ),
              if (_dropdownBarcode == '__MANUAL__') ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _manualBarcodeCtrl,
                  decoration: InputDecoration(
                    labelText: '상품명 직접 입력',
                    hintText: '상품명을 입력하세요',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                  style: GoogleFonts.inter(fontSize: 14),
                  onChanged: (_) => setState(() {}),
                ),
              ],
              const SizedBox(height: 12),

              // ── 위치 ──
              _buildLocationDropdown(),
              if (_locationOption == _LocationOption.fromProduct &&
                  _selectedProduct?.latitude == null) ...[
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 14),
                  child: Text(
                    '위치 정보가 있는 상품을 선택하면 자동으로 입력됩니다',
                    style: GoogleFonts.inter(
                        fontSize: 11, color: kOnSurfaceVariant),
                  ),
                ),
              ],
              if (_locationOption == _LocationOption.manual) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _locationHintCtrl,
                  decoration: InputDecoration(
                    labelText: '장소명 입력',
                    hintText: '예: 이마트 왕십리점',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    prefixIcon:
                        const Icon(Icons.place_outlined, size: 18),
                  ),
                  style: GoogleFonts.inter(fontSize: 14),
                ),
              ],
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
              const SizedBox(height: 8),

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

  Widget _buildLocationDropdown() {
    final hasProductLocation = _selectedProduct?.latitude != null;
    return DropdownButtonFormField<_LocationOption>(
      value: _locationOption,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: '위치 (선택사항)',
        border:
            OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      style: GoogleFonts.inter(fontSize: 14, color: kOnSurface),
      items: [
        DropdownMenuItem(
          value: _LocationOption.none,
          child: Row(children: [
            const Icon(Icons.location_off_outlined,
                size: 16, color: kOnSurfaceVariant),
            const SizedBox(width: 8),
            Text('없음',
                style: GoogleFonts.inter(
                    fontSize: 14, color: kOnSurfaceVariant)),
          ]),
        ),
        DropdownMenuItem(
          value: _LocationOption.fromProduct,
          enabled: hasProductLocation,
          child: Row(children: [
            Icon(Icons.qr_code_scanner,
                size: 16,
                color:
                    hasProductLocation ? kOnSurface : kOnSurfaceVariant),
            const SizedBox(width: 8),
            Text('상품 위치 자동입력',
                style: GoogleFonts.inter(
                    fontSize: 14,
                    color: hasProductLocation
                        ? kOnSurface
                        : kOnSurfaceVariant)),
          ]),
        ),
        DropdownMenuItem(
          value: _LocationOption.current,
          child: Row(children: [
            const Icon(Icons.my_location_outlined, size: 16),
            const SizedBox(width: 8),
            Text('현재 위치', style: GoogleFonts.inter(fontSize: 14)),
          ]),
        ),
        DropdownMenuItem(
          value: _LocationOption.manual,
          child: Row(children: [
            const Icon(Icons.edit_location_outlined, size: 16),
            const SizedBox(width: 8),
            Text('직접 입력', style: GoogleFonts.inter(fontSize: 14)),
          ]),
        ),
      ],
      onChanged: (v) =>
          setState(() => _locationOption = v ?? _LocationOption.none),
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
