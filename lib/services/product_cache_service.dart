import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'local_storage_service.dart';

class ProductCacheService {
  static const int _batchSize = 200; // Fetch 100 products at a time

  // ✅ Fetch and cache ALL products from Odoo
  static Future<int> cacheAllProducts() async {
    try {
      print("📥 Starting product cache...");
      int totalCached = 0;
      int offset = 0;
      bool hasMore = true;

      while (hasMore) {
        // Fetch products in batches
        final response = await http.post(
          Uri.parse('${ApiConfig.baseUrl}/counting/cache-products'),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            'offset': offset,
            'limit': _batchSize,
          }),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final products = data['products'] as List? ?? [];

          if (products.isEmpty) {
            hasMore = false;
          } else {
            // Cache each product
            for (final product in products) {
              // Extract barcode from product
              final barcode = product['barcode'] ?? product['default_code'] ?? '';
              if (barcode.isNotEmpty) {
                await LocalStorageService.cacheProduct(barcode, {
                  'id': product['id'],
                  'name': product['name'],
                  'tracking': product['tracking'] ?? 'none',
                  'barcode': barcode,
                  'default_code': product['default_code'] ?? '',
                });
                totalCached++;
              }
            }

            offset += products.length;
            print("📥 Cached ${products.length} products (Total: $totalCached)");

            // If less than batch size, we're done
            if (products.length < _batchSize) {
              hasMore = false;
            }
          }
        } else {
          print("❌ Failed to fetch products: ${response.statusCode}");
          hasMore = false;
        }
      }

      print("✅ Product cache complete: $totalCached products cached");
      return totalCached;
    } catch (e) {
      print("❌ Product cache error: $e");
      return 0;
    }
  }

  // ✅ Cache products by barcode list (for specific products)
  static Future<void> cacheProductsByBarcodes(List<String> barcodes) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/counting/cache-products-by-barcode'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({'barcodes': barcodes}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final products = data['products'] as List? ?? [];

        for (final product in products) {
          final barcode = product['barcode'] ?? product['default_code'] ?? '';
          if (barcode.isNotEmpty) {
            await LocalStorageService.cacheProduct(barcode, {
              'id': product['id'],
              'name': product['name'],
              'tracking': product['tracking'] ?? 'none',
              'barcode': barcode,
              'default_code': product['default_code'] ?? '',
            });
          }
        }
        print("✅ Cached ${products.length} products by barcodes");
      }
    } catch (e) {
      print("❌ Cache products by barcodes error: $e");
    }
  }

  // ✅ Get cached products count
  static Future<int> getCachedCount() async {
    return await LocalStorageService.getCachedProductsCount();
  }
}