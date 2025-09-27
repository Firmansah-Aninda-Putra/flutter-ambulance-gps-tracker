// frontend/lib/services/socket_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:socket_io_client/socket_io_client.dart' as socket_io;
import 'package:flutter/material.dart';
import '../config/api_config.dart';
import '../models/chat_message.dart';
import '../models/call_history_item.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  socket_io.Socket? _socket;
  int? _currentUserId;
  bool _isConnected = false;
  bool _isConnecting = false;

  // Stream controllers untuk berbagai events
  final StreamController<ChatMessage> _messageStreamController =
      StreamController<ChatMessage>.broadcast();
  final StreamController<Map<String, dynamic>> _messageDeletedStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>>
      _ambulanceLocationStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<CallHistoryItem> _newCallStreamController =
      StreamController<CallHistoryItem>.broadcast();
  final StreamController<Map<String, dynamic>> _callDeletedStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _trackingStatusStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _allCallsClearedController =
      StreamController<Map<String, dynamic>>.broadcast();

  // Public streams
  Stream<ChatMessage> get messageStream => _messageStreamController.stream;
  Stream<Map<String, dynamic>> get messageDeletedStream =>
      _messageDeletedStreamController.stream;
  Stream<Map<String, dynamic>> get ambulanceLocationStream =>
      _ambulanceLocationStreamController.stream;
  Stream<CallHistoryItem> get newCallStream => _newCallStreamController.stream;
  Stream<Map<String, dynamic>> get callDeletedStream =>
      _callDeletedStreamController.stream;
  Stream<Map<String, dynamic>> get trackingStatusStream =>
      _trackingStatusStreamController.stream;
  Stream<Map<String, dynamic>> get allCallsClearedStream =>
      _allCallsClearedController.stream;

  // Getters
  bool get isConnected => _isConnected;
  int? get currentUserId => _currentUserId;

  /// Initialize socket connection with user ID
  Future<void> initialize(int userId) async {
    if (_isConnecting) {
      debugPrint('SocketService: Already connecting, waiting...');
      // Wait for current connection attempt to complete
      int attempts = 0;
      while (_isConnecting && attempts < 50) {
        await Future.delayed(const Duration(milliseconds: 100));
        attempts++;
      }
      return;
    }

    if (_currentUserId == userId && _isConnected) {
      debugPrint('SocketService: Already connected for user $userId');
      return;
    }

    _currentUserId = userId;
    await _connect();
  }

  /// Connect to socket server
  Future<void> _connect() async {
    if (_isConnecting) return;

    _isConnecting = true;

    try {
      // Disconnect existing socket if any
      await _disconnect();

      debugPrint('SocketService: Connecting to ${ApiConfig.socketUrl}...');

      _socket = socket_io.io(
        ApiConfig.socketUrl,
        socket_io.OptionBuilder()
            .setTransports(['websocket'])
            .enableForceNewConnection()
            .setReconnectionDelay(1000)
            .setReconnectionDelayMax(5000)
            .setReconnectionAttempts(5)
            .setTimeout(10000)
            .build(),
      );

      _setupEventHandlers();
      _socket!.connect();

      // Wait for connection with timeout
      await _waitForConnection();
    } catch (e) {
      debugPrint('SocketService: Connection error: $e');
      _isConnected = false;
    } finally {
      _isConnecting = false;
    }
  }

  /// Wait for socket connection with timeout
  Future<void> _waitForConnection() async {
    final completer = Completer<void>();
    Timer? timeoutTimer;

    void onConnect() {
      if (!completer.isCompleted) {
        timeoutTimer?.cancel();
        completer.complete();
      }
    }

    void onError() {
      if (!completer.isCompleted) {
        timeoutTimer?.cancel();
        completer.completeError('Connection failed');
      }
    }

    _socket!.onConnect((_) => onConnect());
    _socket!.onConnectError((error) => onError());
    _socket!.onError((error) => onError());

    // 10 second timeout
    timeoutTimer = Timer(const Duration(seconds: 10), () {
      if (!completer.isCompleted) {
        completer.completeError('Connection timeout');
      }
    });

    await completer.future;
  }

  /// Setup all socket event handlers
  void _setupEventHandlers() {
    if (_socket == null) return;

    _socket!.onConnect((_) {
      debugPrint('SocketService: Connected with ID: ${_socket!.id}');
      _isConnected = true;
      _joinUserRoom();
    });

    _socket!.onReconnect((_) {
      debugPrint('SocketService: Reconnected');
      _isConnected = true;
      _joinUserRoom();
    });

    _socket!.onDisconnect((_) {
      debugPrint('SocketService: Disconnected');
      _isConnected = false;
    });

    _socket!.onConnectError((error) {
      debugPrint('SocketService: Connection error: $error');
      _isConnected = false;
    });

    _socket!.onError((error) {
      debugPrint('SocketService: Socket error: $error');
    });

    // Chat message events
    _socket!.on('newMessage', _handleNewMessage);
    _socket!.on('messageDeleted', _handleMessageDeleted);

    // Ambulance events
    _socket!.on('ambulanceLocationUpdated', _handleAmbulanceLocationUpdated);
    _socket!.on('ambulanceTrackingEnabled', _handleTrackingStatus);
    _socket!.on('ambulanceTrackingDisabled', _handleTrackingStatus);
    _socket!.on('trackingStatus', _handleTrackingStatus);
    _socket!.on('trackingToggleConfirm', _handleTrackingStatus);

    // Call events
    _socket!.on('newCall', _handleNewCall);
    _socket!.on('callDeleted', _handleCallDeleted);

    // ✅ TAMBAHAN: Event untuk hapus semua riwayat panggilan
    _socket!.on('allCallsCleared', _handleAllCallsCleared);
  }

  /// Join user room for receiving messages
  void _joinUserRoom() {
    if (_socket != null && _isConnected && _currentUserId != null) {
      debugPrint('SocketService: Joining room for user $_currentUserId');
      _socket!.emit('join', _currentUserId.toString());
    }
  }

  /// Handle new message event
  void _handleNewMessage(dynamic data) {
    try {
      Map<String, dynamic> map;
      if (data is Map<String, dynamic>) {
        map = data;
      } else if (data is Map) {
        map = Map<String, dynamic>.from(data);
      } else {
        final decoded = jsonDecode(data.toString());
        if (decoded is Map) {
          map = Map<String, dynamic>.from(decoded);
        } else {
          throw Exception('Unexpected newMessage format');
        }
      }

      final message = ChatMessage.fromJson(map);
      debugPrint('SocketService: New message received: ${message.id}');
      _messageStreamController.add(message);
    } catch (e) {
      debugPrint('SocketService: Error parsing newMessage: $e');
    }
  }

  /// Handle message deleted event
  void _handleMessageDeleted(dynamic data) {
    try {
      Map<String, dynamic> map;
      if (data is Map<String, dynamic>) {
        map = data;
      } else if (data is Map) {
        map = Map<String, dynamic>.from(data);
      } else {
        map = {'id': data};
      }

      debugPrint('SocketService: Message deleted: ${map['id']}');
      _messageDeletedStreamController.add(map);
    } catch (e) {
      debugPrint('SocketService: Error parsing messageDeleted: $e');
    }
  }

  /// Handle ambulance location updated event
  void _handleAmbulanceLocationUpdated(dynamic data) {
    try {
      Map<String, dynamic> map;
      if (data is Map<String, dynamic>) {
        map = data;
      } else if (data is Map) {
        map = Map<String, dynamic>.from(data);
      } else {
        return;
      }

      debugPrint('SocketService: Ambulance location updated');
      _ambulanceLocationStreamController.add(map);
    } catch (e) {
      debugPrint('SocketService: Error parsing ambulanceLocationUpdated: $e');
    }
  }

  /// Handle tracking status events
  void _handleTrackingStatus(dynamic data) {
    try {
      Map<String, dynamic> map;
      if (data is Map<String, dynamic>) {
        map = data;
      } else if (data is Map) {
        map = Map<String, dynamic>.from(data);
      } else {
        map = {};
      }

      debugPrint('SocketService: Tracking status updated');
      _trackingStatusStreamController.add(map);
    } catch (e) {
      debugPrint('SocketService: Error parsing tracking status: $e');
    }
  }

  /// Handle new call event
  void _handleNewCall(dynamic data) {
    try {
      Map<String, dynamic> map;
      if (data is Map<String, dynamic>) {
        map = data;
      } else if (data is Map) {
        map = Map<String, dynamic>.from(data);
      } else {
        return;
      }

      final call = CallHistoryItem.fromJson(map);
      debugPrint('SocketService: New call received: ${call.id}');
      _newCallStreamController.add(call);
    } catch (e) {
      debugPrint('SocketService: Error parsing newCall: $e');
    }
  }

  /// Handle call deleted event
  void _handleCallDeleted(dynamic data) {
    try {
      Map<String, dynamic> map;
      if (data is Map<String, dynamic>) {
        map = data;
      } else if (data is Map) {
        map = Map<String, dynamic>.from(data);
      } else {
        map = {'id': data};
      }

      debugPrint('SocketService: Call deleted: ${map['id']}');
      _callDeletedStreamController.add(map);
    } catch (e) {
      debugPrint('SocketService: Error parsing callDeleted: $e');
    }
  }

  /// ✅ TAMBAHAN: Handle all calls cleared event
  void _handleAllCallsCleared(dynamic data) {
    try {
      Map<String, dynamic> map;
      if (data is Map<String, dynamic>) {
        map = data;
      } else if (data is Map) {
        map = Map<String, dynamic>.from(data);
      } else {
        map = {
          'success': true,
          'timestamp': DateTime.now().toIso8601String(),
          'clearedCount': 0
        };
      }

      debugPrint(
          'SocketService: All calls cleared: ${map['clearedCount']} items');
      _allCallsClearedController.add(map);
    } catch (e) {
      debugPrint('SocketService: Error parsing allCallsCleared: $e');
    }
  }

  /// Emit event to server
  void emit(String event, dynamic data) {
    if (_socket != null && _isConnected) {
      _socket!.emit(event, data);
      debugPrint('SocketService: Emitted $event');
    } else {
      debugPrint('SocketService: Cannot emit $event - not connected');
    }
  }

  /// Reconnect if disconnected
  Future<void> ensureConnected() async {
    if (!_isConnected && _currentUserId != null) {
      debugPrint('SocketService: Reconnecting...');
      await _connect();
    }
  }

  /// Disconnect from socket
  Future<void> _disconnect() async {
    if (_socket != null) {
      debugPrint('SocketService: Disconnecting...');
      _socket!.disconnect();
      _socket!.destroy();
      _socket = null;
      _isConnected = false;
    }
  }

  /// Dispose all resources
  Future<void> dispose() async {
    debugPrint('SocketService: Disposing...');
    await _disconnect();

    await _messageStreamController.close();
    await _messageDeletedStreamController.close();
    await _ambulanceLocationStreamController.close();
    await _newCallStreamController.close();
    await _callDeletedStreamController.close();
    await _trackingStatusStreamController.close();
    await _allCallsClearedController.close(); // ✅ TAMBAHAN

    _currentUserId = null;
  }

  /// Handle app lifecycle changes
  void handleAppLifecycleChange(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        debugPrint('SocketService: App resumed');
        if (_currentUserId != null) {
          ensureConnected();
        }
        break;
      case AppLifecycleState.paused:
        debugPrint('SocketService: App paused');
        // Keep connection alive but don't disconnect
        break;
      case AppLifecycleState.detached:
        debugPrint('SocketService: App detached');
        _disconnect();
        break;
      default:
        break;
    }
  }
}
