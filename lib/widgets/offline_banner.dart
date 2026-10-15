import 'package:flutter/material.dart';
import '../services/sync_service.dart';
import '../utils/constants.dart';

// Bar above every screen while the server can't be reached, with the
// number of batches waiting to be sent. Wraps the whole navigator
// (MaterialApp.builder): the widget tree keeps the same shape online and
// offline so the navigation stack is never rebuilt.
class OfflineBanner extends StatelessWidget {
  final Widget child;

  const OfflineBanner({Key? key, required this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SyncService.online,
      builder: (context, online, _) {
        return Column(
          children: [
            if (!online)
              Material(
                color: AppColors.warningColor,
                child: InkWell(
                  // The app never polls the server: the user asks for a
                  // new connection test here.
                  onTap: () async {
                    final back = await SyncService.checkConnection();
                    if (!back) {
                      SyncService.messengerKey.currentState?.showSnackBar(
                        const SnackBar(content: Text('Toujours hors ligne')),
                      );
                    }
                  },
                  child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.cloud_off, size: 16, color: Colors.white),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ValueListenableBuilder<int>(
                            valueListenable: SyncService.pendingBatches,
                            builder: (context, pending, _) => Text(
                              pending > 0
                                  ? 'Hors ligne · $pending lot(s) en attente d\'envoi'
                                  : 'Hors ligne · les scans sont gardés sur le téléphone',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const Icon(Icons.refresh, size: 16, color: Colors.white),
                        const SizedBox(width: 4),
                        const Text(
                          'Réessayer',
                          style: TextStyle(color: Colors.white, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
                ),
              ),
            Expanded(
              // Keyed so the navigator keeps its state when the banner
              // appears or disappears above it.
              key: const ValueKey('app'),
              // The banner already covers the status bar.
              child: MediaQuery.removePadding(
                context: context,
                removeTop: !online,
                child: child,
              ),
            ),
          ],
        );
      },
    );
  }
}
