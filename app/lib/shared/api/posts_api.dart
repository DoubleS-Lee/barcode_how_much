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
  final String content;
  final bool isOwner;
  final DateTime createdAt;

  PostCommentModel({
    required this.id,
    required this.authorId,
    required this.content,
    required this.isOwner,
    required this.createdAt,
  });

  factory PostCommentModel.fromJson(Map<String, dynamic> j) => PostCommentModel(
    id: j['id'].toString(),
    authorId: j['author_id'] ?? '',
    content: j['content'] ?? '',
    isOwner: j['is_owner'] as bool? ?? false,
    createdAt: DateTime.parse(j['created_at']),
  );
}

// ── 게시글 모델 ───────────────────────────────────────────

class PostModel {
  final String id;
  final String authorId;
  final String title;
  final String content;
  final int price;
  final String? barcode;
  final bool shareLocation;
  final double? latitude;
  final double? longitude;
  final String? locationHint;
  final int viewCount;
  final int likeCount;
  final int commentCount;
  final bool liked;
  final List<PriceLookupModel> priceLookups;
  final DateTime createdAt;
  final DateTime updatedAt;

  PostModel({
    required this.id,
    required this.authorId,
    required this.title,
    required this.content,
    required this.price,
    this.barcode,
    required this.shareLocation,
    this.latitude,
    this.longitude,
    this.locationHint,
    this.viewCount = 0,
    this.likeCount = 0,
    this.commentCount = 0,
    this.liked = false,
    this.priceLookups = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  factory PostModel.fromJson(Map<String, dynamic> j) => PostModel(
    id: j['id'].toString(),
    authorId: j['author_id'] ?? '',
    title: j['title'] ?? '',
    content: j['content'] ?? '',
    price: j['price'] as int? ?? 0,
    barcode: j['barcode'] as String?,
    shareLocation: j['share_location'] as bool? ?? false,
    latitude: (j['latitude'] as num?)?.toDouble(),
    longitude: (j['longitude'] as num?)?.toDouble(),
    locationHint: j['location_hint'] as String?,
    viewCount: j['view_count'] as int? ?? 0,
    likeCount: j['like_count'] as int? ?? 0,
    commentCount: j['comment_count'] as int? ?? 0,
    liked: j['liked'] as bool? ?? false,
    priceLookups: (j['price_lookups'] as List? ?? [])
        .map((e) => PriceLookupModel.fromJson(e as Map<String, dynamic>))
        .toList(),
    createdAt: DateTime.parse(j['created_at']),
    updatedAt: DateTime.parse(j['updated_at']),
  );

  PostModel copyWith({bool? liked, int? likeCount}) => PostModel(
    id: id,
    authorId: authorId,
    title: title,
    content: content,
    price: price,
    barcode: barcode,
    shareLocation: shareLocation,
    latitude: latitude,
    longitude: longitude,
    locationHint: locationHint,
    viewCount: viewCount,
    likeCount: likeCount ?? this.likeCount,
    commentCount: commentCount,
    liked: liked ?? this.liked,
    priceLookups: priceLookups,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

// ── API 클래스 ────────────────────────────────────────────

class PostsApi {
  static final _dio = client.dio;

  static Future<List<PostModel>> fetchPosts({int page = 1, String? search, String? deviceUuid}) async {
    final res = await _dio.get('/posts', queryParameters: {
      'page': page,
      'limit': 20,
      if (search != null && search.isNotEmpty) 'search': search,
      if (deviceUuid != null) 'device_uuid': deviceUuid,
    });
    final list = res.data['posts'] as List;
    return list.map((e) => PostModel.fromJson(e)).toList();
  }

  static Future<PostModel> createPost({
    required String deviceUuid,
    required String title,
    required String content,
    required int price,
    String? barcode,
    bool shareLocation = false,
    double? latitude,
    double? longitude,
    String? locationHint,
  }) async {
    final res = await _dio.post('/posts', data: {
      'device_uuid': deviceUuid,
      'title': title,
      'content': content,
      'price': price,
      if (barcode != null) 'barcode': barcode,
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
    bool shareLocation = false,
    double? latitude,
    double? longitude,
    String? locationHint,
  }) async {
    final res = await _dio.put('/posts/$id', data: {
      'device_uuid': deviceUuid,
      'title': title,
      'content': content,
      'price': price,
      'barcode': barcode,
      'share_location': shareLocation,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      'location_hint': locationHint,
    });
    return PostModel.fromJson(res.data);
  }

  static Future<void> deletePost({
    required String id,
    required String deviceUuid,
  }) async {
    await _dio.delete('/posts/$id', data: {'device_uuid': deviceUuid});
  }

  static Future<Map<String, dynamic>> likePost({
    required String id,
    required String deviceUuid,
  }) async {
    final res = await _dio.post('/posts/$id/like', data: {'device_uuid': deviceUuid});
    return res.data as Map<String, dynamic>;
  }

  static Future<List<PostCommentModel>> fetchComments({
    required String id,
    String? deviceUuid,
  }) async {
    final res = await _dio.get('/posts/$id/comments', queryParameters: {
      if (deviceUuid != null) 'device_uuid': deviceUuid,
    });
    return (res.data as List).map((e) => PostCommentModel.fromJson(e)).toList();
  }

  static Future<PostCommentModel> addComment({
    required String id,
    required String deviceUuid,
    required String content,
  }) async {
    final res = await _dio.post('/posts/$id/comments', data: {
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
    await _dio.delete('/posts/$postId/comments/$commentId', data: {'device_uuid': deviceUuid});
  }
}
