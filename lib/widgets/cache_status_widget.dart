import 'package:flutter/material.dart';
import '../services/local_storage_service.dart';

class CacheStatusWidget extends StatefulWidget {
  const CacheStatusWidget({Key? key}) : super(key: key);

  @override
  State<CacheStatusWidget> createState() => _CacheStatusWidgetState();
}

class _CacheStatusWidgetState extends State<CacheStatusWidget> {
  int _cachedCount = 0;

  @override
  void initState() {
    super.initState();
    _loadCacheCount();
  }

  Future<void> _loadCacheCount() async {
    final count = await LocalStorageService.getCachedProductsCount();
    setState(() {
      _cachedCount = count;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _cachedCount > 0 ? Colors.green[100] : Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _cachedCount > 0 ? Icons.check_circle : Icons.cloud_off,
            size: 14,
            color: _cachedCount > 0 ? Colors.green : Colors.grey,
          ),
          const SizedBox(width: 4),
          Text(
            _cachedCount > 0 ? '$_cachedCount produits en cache' : 'Mode hors ligne prêt',
            style: TextStyle(
              fontSize: 10,
              color: _cachedCount > 0 ? Colors.green[800] : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
}