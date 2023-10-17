import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'channel_id.dart';
import 'web_socket/web_socket_interface.dart';

typedef _OnChannelSubscribedFunction = void Function();
typedef _OnChannelDisconnectedFunction = void Function();
typedef _OnChannelMessageFunction = void Function(Map message);

class ActionCable {
  DateTime? _lastPing;
  late Timer _timer;
  Duration? timeoutAfter;
  Duration? healthCheckDuration;
  late WebSocketChannel _socketChannel;
  late StreamSubscription _listener;
  void Function()? onConnected;
  void Function(dynamic error)? onCannotConnect;
  void Function()? onConnectionLost;
  final Map<String, _OnChannelSubscribedFunction?>
      _onChannelSubscribedCallbacks = {};
  final Map<String, _OnChannelDisconnectedFunction?>
      _onChannelDisconnectedCallbacks = {};
  final Map<String, _OnChannelMessageFunction?> _onChannelMessageCallbacks = {};

  final IWebSocket _webSocket = IWebSocket();

  ActionCable.connect(
    String url, {
    Map<String, String> headers = const {},
    this.onConnected,
    this.onConnectionLost,
    this.onCannotConnect,
  }) {
    // rails gets a ping every 3 seconds
    _socketChannel = _webSocket.connect(
      url,
      headers: headers,
      pingInterval: const Duration(seconds: 3),
    );
    _listener = _socketChannel.stream.listen(
      _onData,
      onError: (error) {
        disconnect(); // close a socket and the timer
        onCannotConnect?.call(error);
      },
    );
    _timer = Timer.periodic(
      healthCheckDuration ?? const Duration(seconds: 3),
      healthCheck,
    );
  }

  void disconnect() {
    _timer.cancel();
    _socketChannel.sink.close();
    _listener.cancel();
  }

  // check if there is no ping for 3 seconds and signal a [onConnectionLost] if
  // there is no ping for more than 6 seconds
  void healthCheck(_) {
    if (_lastPing == null) {
      return;
    }
    if (DateTime.now().difference(_lastPing!) >
        (timeoutAfter ?? const Duration(seconds: 6))) {
      disconnect();
      onConnectionLost?.call();
    }
  }

  // channelName being 'Chat' will be considered as 'ChatChannel',
  // 'Chat', { id: 1 } => { channel: 'ChatChannel', id: 1 }
  void subscribe(
    String channelName, {
    Map? channelParams,
    _OnChannelSubscribedFunction? onSubscribed,
    _OnChannelDisconnectedFunction? onDisconnected,
    _OnChannelMessageFunction? onMessage,
  }) {
    final channelId = encodeChannelId(channelName, channelParams);

    _onChannelSubscribedCallbacks[channelId] = onSubscribed;
    _onChannelDisconnectedCallbacks[channelId] = onDisconnected;
    _onChannelMessageCallbacks[channelId] = onMessage;

    _send({'identifier': channelId, 'command': 'subscribe'});
  }

  void unsubscribe(String channelName, {Map? channelParams}) {
    final channelId = encodeChannelId(channelName, channelParams);

    _onChannelSubscribedCallbacks[channelId] = null;
    _onChannelDisconnectedCallbacks[channelId] = null;
    _onChannelMessageCallbacks[channelId] = null;

    _socketChannel.sink
        .add(jsonEncode({'identifier': channelId, 'command': 'unsubscribe'}));
  }

  void performAction(
    String channelName, {
    String? action,
    Map? channelParams,
    Map? actionParams,
  }) {
    final channelId = encodeChannelId(channelName, channelParams);

    actionParams ??= {};
    actionParams['action'] = action;

    _send({
      'identifier': channelId,
      'command': 'message',
      'data': jsonEncode(actionParams)
    });
  }

  void _onData(dynamic jsonPayload) {
    final payload = jsonDecode(jsonPayload);

    if (payload['type'] != null) {
      _handleProtocolMessage(payload);
    } else {
      _handleDataMessage(payload);
    }
  }

  void _handleProtocolMessage(Map payload) {
    switch (payload['type']) {
      case 'ping':
        // rails sends epoch as seconds not miliseconds
        _lastPing =
            DateTime.fromMillisecondsSinceEpoch(payload['message'] * 1000);
        break;
      case 'welcome':
        if (onConnected != null) {
          onConnected?.call();
        }
        break;
      case 'disconnect':
        final identifier = payload['identifier'];
        if (identifier != null) {
          final channelId = parseChannelId(payload['identifier']);
          final onDisconnected = _onChannelDisconnectedCallbacks[channelId];
          if (onDisconnected != null) {
            onDisconnected();
          }
        } else {
          final reason = payload['reason'];
          if (reason != null) {
            onCannotConnect?.call(reason);
          }
        }
        break;
      case 'confirm_subscription':
        final channelId = parseChannelId(payload['identifier']);
        final onSubscribed = _onChannelSubscribedCallbacks[channelId];
        if (onSubscribed != null) {
          onSubscribed();
        }
        break;
      case 'reject_subscription':
        // throw 'Unimplemented';
        break;
      default:
        throw 'InvalidMessage';
    }
  }

  void _handleDataMessage(Map payload) {
    final channelId = parseChannelId(payload['identifier']);
    final onMessage = _onChannelMessageCallbacks[channelId];
    if (onMessage != null) {
      onMessage(payload['message']);
    }
  }

  void _send(Map payload) {
    _socketChannel.sink.add(jsonEncode(payload));
  }
}
