import 'dart:html';

import 'package:web_socket_channel/html.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../web_socket_interface.dart';

class WebSocketWeb implements IWebSocket {
  @override
  WebSocketChannel connect(
    String url, {
    Iterable<String>? protocols,
    Map<String, dynamic>? headers,
    Duration? pingInterval,
  }) {
    final webSocket = WebSocket(url, protocols);
    return HtmlWebSocketChannel(webSocket);
  }
}

IWebSocket getWebSocket() => WebSocketWeb();
