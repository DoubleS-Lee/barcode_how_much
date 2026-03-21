import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/api/recommend_api.dart';

class RecommendArgs {
  final String barcode;
  final String productName;
  const RecommendArgs({required this.barcode, required this.productName});

  @override
  bool operator ==(Object other) =>
      other is RecommendArgs &&
      other.barcode == barcode &&
      other.productName == productName;

  @override
  int get hashCode => Object.hash(barcode, productName);
}

final recommendProvider =
    FutureProvider.family<Map<String, dynamic>, RecommendArgs>((ref, args) {
  return RecommendApi.getRecommendations(
    barcode: args.barcode,
    productName: args.productName,
  );
});
