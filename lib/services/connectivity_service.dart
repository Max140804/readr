import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  final _controller = StreamController<bool>.broadcast();
  
  bool _isConnected = true;
  Timer? _poorConnectionTimer;
  
  Stream<bool> get connectivityStream => _controller.stream;
  bool get isConnected => _isConnected;

  void init() {
    _connectivity.onConnectivityChanged.listen(_handleConnectivityChange);
    // Initial check
    checkRealCurrentStatus();
    
    // Periodic check every 30 seconds to ensure we aren't in a "fake connected" state
    Timer.periodic(const Duration(seconds: 30), (_) => checkRealCurrentStatus());
  }

  Future<void> checkRealCurrentStatus() async {
    final results = await _connectivity.checkConnectivity();
    await _handleConnectivityChange(results);
  }

  Future<void> _handleConnectivityChange(List<ConnectivityResult> results) async {
    bool hasInterface = results.any((result) => result != ConnectivityResult.none);
    
    if (!hasInterface) {
      _setConnected(false);
      return;
    }

    // If we have an interface, verify real internet access
    final bool hasInternet = await _hasInternetAccess();
    
    if (hasInternet) {
      _poorConnectionTimer?.cancel();
      _poorConnectionTimer = null;
      _setConnected(true);
    } else {
      // If no internet but has interface, wait 15 seconds before declaring "offline"
      if (_poorConnectionTimer == null) {
        _poorConnectionTimer = Timer(const Duration(seconds: 15), () {
          _setConnected(false);
        });
      }
    }
  }

  Future<bool> _hasInternetAccess() async {
    try {
      // Try to look up a reliable host
      final result = await InternetAddress.lookup('google.com').timeout(const Duration(seconds: 5));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  void _setConnected(bool value) {
    if (_isConnected != value) {
      _isConnected = value;
      _controller.add(_isConnected);
      debugPrint("Connectivity Status Changed: ${value ? 'Online' : 'Offline'}");
    }
  }

  void dispose() {
    _poorConnectionTimer?.cancel();
    _controller.close();
  }
}
