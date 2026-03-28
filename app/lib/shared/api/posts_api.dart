import 'dart:io';
import 'package:dio/dio.dart';
import 'api_client.dart' as client;

// ── 가격 조회 결과 모델 ────────────────────────────────────

class PriceLookupModel {
  final String platform;
  final int? price;
  final String? productName;
  final String? productUrl;

  PriceLookupModel({required this.platform, this.price, this.productName, this.productUrl});

  factory PriceLookupModel.fromJson(Map<String, dynamic> j) => PriceLookupModel(
    platform: j['platform'] as String,
    price: j['price'] as int?,
    productName: j['product_name'] as String?,
    productUrl: j['product_url'] as String?,
  );
}

// ── 댓글 모델 ─────────────────────────────────────────────

class PostCommentModel {
  final String id;
  final String authorId;
  final String? nickname;
  final String content;
  final bool isOwner;
  final DateTime createdAt;

  PostCommentModel({
    required this.id,
    required this.authorId,
    this.nickname,
    required this.content,
    required this.isOwner,
    required this.createdAt,
  });

  factory PostCommentModel.fromJson(Map<String, dynamic> j) => PostCommentModel(
    id: j['id'].toString(),
    authorId: j['author_id'] ?? '',
    nickname: j['nickname'] as String?,
    content: j['content'] ?? '',
    isOwner: j['is_owner'] as bool? ?? false,
    createdAt: DateTime.parse(j['created_at']),
  );
}

// ── 게시글 모델 ───────────────────────────────────────────

class PostModel {
  final String id;
  final String authorId;
  final String? nickname;
  final String title;
  final String content;
  final int price;
  final String? barcode;
  final String? imageUrl;
  final bool shareLocation;
  final double? latitude;
  final double? longitude;
  final String? locationHint;
  final int viewCount;
  final int likeCount;
  final int reportCount;
  final int commentCount;
  final bool liked;
  final bool reported;
  final bool isOwner;
  final List<PriceLookupModel> priceLookups;
  final DateTime createdAt;
  final DateTime updatedAt;

  PostModel({
    required this.id,
    required this.authorId,
    this.nickname,
    required this.title,
    required this.content,
    required this.price,
    this.barcode,
    this.imageUrl,
    required this.shareLocation,
    this.latitude,
    this.longitude,
    this.locationHint,
    this.viewCount = 0,
    this.likeCount = 0,
    this.reportCount = 0,
    this.commentCount = 0,
    this.liked = false,
    this.reported = false,
    this.isOwner = false,
    this.priceLookups = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  factory PostModel.fromJson(Map<String, dynamic> j) => PostModel(
    id: j['id'].toString(),
    authorId: j['author_id'] ?? '',
    nickname: j['nickname'] as String?,
    title: j['title'] ?? '',
    content: j['content'] ?? '',
    price: j['price'] as int? ?? 0,
    barcode: j['barcode'] as String?,
    imageUrl: j['image_url'] as String?,
    shareLocation: j['share_location'] as bool? ?? false,
    latitude: (j['latitude'] as num?)?.toDouble(),
    longitude: (j['longitude'] as num?)?.toDouble(),
    locationHint: j['location_hint'] as String?,
    viewCount: j['view_count'] as int? ?? 0,
    likeCount: j['like_count'] as int? ?? 0,
    reportCount: j['report_count'] as int? ?? 0,
    commentCount: j['comment_count'] as int? ?? 0,
    liked: j['liked'] as bool? ?? false,
    reported: j['reported'] as bool? ?? false,
    isOwner: j['is_owner'] as bool? ?? false,
    priceLookups: (j['price_lookups'] as List? ?? [])
        .map((e) => PriceLookupModel.fromJson(e as Map<String, dynamic>))
        .toList(),
    createdAt: DateTime.parse(j['created_at']),
    updatedAt: DateTime.parse(j['updated_at']),
  );

  PostModel copyWith({bool? liked, int? likeCount, bool? reported, int? reportCount, bool? isOwner}) => PostModel(
    id: id,
    authorId: authorId,
    nickname: nickname,
    title: title,
    content: content,
    price: price,
    barcode: barcode,
    imageUrl: imageUrl,
    shareLocation: shareLocation,
    latitude: latitude,
    longitude: longitude,
    locationHint: locationHint,
    viewCount: viewCount,
    likeCount: likeCount ?? this.likeCount,
    reportCount: reportCount ?? this.reportCount,
    commentCount: commentCount,
    liked: liked ?? this.liked,
    reported: reported ?? this.reported,
    isOwner: isOwner ?? this.isOwner,
    priceLookups: priceLookups,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

// ── 페이지 결과 모델 ──────────────────────────────────────

class PostsPageResult {
  final List<PostModel> posts;
  final int total;
  final int page;
  final int limit;

  PostsPageResult({required this.posts, required this.total, required this.page, required this.limit});

  bool get hasMore => page * limit < total;
}

// ── API 클래스 ────────────────────────────────────────────

class PostsApi {
  static final _dio = client.dio;

  static Future<String> uploadImage(File imageFile) async {
    final formData = FormData.fromMap({
      'image': await MultipartFile.fromFile(
        imageFile.path,
        filename: imageFile.path.split('/').last,
      ),
    });
    final res = await _dio.post('/api/v1/posts/upload-image', data: formData);
    return res.data['image_url'] as String;
  }

  static Future<PostsPageResult> fetchPosts({int page = 1, String? search, String? sort, String? deviceUuid}) async {
    final res = await _dio.get('/api/v1/posts', queryParameters: {
      'page': page,
      'limit': 20,
      if (search != null && search.isNotEmpty) 'search': search,
      if (sort != null) 'sort': sort,
      if (deviceUuid != null) 'device_uuid': deviceUuid,
    });
    final list = res.data['posts'] as List;
    return PostsPageResult(
      posts: list.map((e) => PostModel.fromJson(e as Map<String, dynamic>)).toList(),
      total: res.data['total'] as int,
      page: res.data['page'] as int,
      limit: res.data['limit'] as int,
    );
  }

  static Future<PostModel> fetchPost({required String id, String? deviceUuid}) async {
    final res = await _dio.get('/api/v1/posts/$id', queryParameters: {
      if (deviceUuid != null) 'device_uuid': deviceUuid,
    });
    return PostModel.fromJson(res.data as Map<String, dynamic>);
  }

  static Future<PostModel> createPost({
    required String deviceUuid,
    required String title,
    required String content,
    required int price,
    String? barcode,
    String? imageUrl,
    bool shareLocation = false,
    double? latitude,
    double? longitude,
    String? locationHint,
  }) async {
    final res = await _dio.post('/api/v1/posts', data: {
      'device_uuid': deviceUuid,
      'title': title,
      'content': content,
      'price': price,
      if (barcode != null) 'barcode': barcode,
      if (imageUrl != null) 'image_url': imageUrl,
      'share_location': shareLocation,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (locationHint != null) 'location_hint': locationHint,
    });
    return PostModel.fromJson(res.data);
  }

  static Future<PostModel> updatePost({
    required String id,
    required String deviceUuid,
    required String title,
    required String content,
    required int price,
    String? barcode,
    String? imageUrl,
    bool shareLocation = false,
    double? latitude,
    double? longitude,
    String? locationHint,
  }) async {
    final res = await _dio.put('/api/v1/posts/$id', data: {
      'device_uuid': deviceUuid,
      'title': title,
      'content': content,
      'price': price,
      if (barcode != null) 'barcode': barcode,
      if (imageUrl != null) 'image_url': imageUrl,
      'share_location': shareLocation,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (locationHint != null) 'location_hint': locationHint,
    });
    return PostModel.fromJson(res.data);
  }

  static Future<void> deletePost({
    required String id,
    required String deviceUuid,
  }) async {
    await _dio.delete('/api/v1/posts/$id', data: {'device_uuid': deviceUuid});
  }

  static Future<Map<String, dynamic>> reportPost({
    required String id,
    required String deviceUuid,
  }) async {
    final res = await _dio.post('/api/v1/posts/$id/report', data: {'device_uuid': deviceUuid});
    return res.data as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> likePost({
    required String id,
    required String deviceUuid,
  }) async {
    final res = await _dio.post('/api/v1/posts/$id/like', data: {'device_uuid': deviceUuid});
    return res.data as Map<String, dynamic>;
  }

  static Future<List<PostCommentModel>> fetchComments({
    required String id,
    String? deviceUuid,
  }) async {
    final res = await _dio.get('/api/v1/posts/$id/comments', queryParameters: {
      if (deviceUuid != null) 'device_uuid': deviceUuid,
    });
    return (res.data as List).map((e) => PostCommentModel.fromJson(e)).toList();
  }

  static Future<PostCommentModel> addComment({
    required String id,
    required String deviceUuid,
    required String content,
  }) async {
    final res = await _dio.post('/api/v1/posts/$id/comments', data: {
      'device_uuid': deviceUuid,
      'content': content,
    });
    return PostCommentModel.fromJson(res.data);
  }

  static Future<void> deleteComment({
    required String postId,
    required String commentId,
    required String deviceUuid,
  }) async {
    await _dio.delete('/api/v1/posts/$postId/comments/$commentId', data: {'device_uuid': deviceUuid});
  }
}
