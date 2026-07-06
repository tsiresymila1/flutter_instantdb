part of 'sync_engine.dart';

/// Private connection-lifecycle handlers for [SyncEngine].
///
/// Moved verbatim from `sync_engine.dart` into a `part of` extension. As an
/// extension in the same library it retains access to the engine's private
/// fields and methods. No logic was changed — only relocated. (Methods that
/// reference the class's private *static* loggers were intentionally left in
/// the main class body, since extensions cannot reference static members
/// unqualified without editing the moved code.)
extension _SyncConnect on SyncEngine {
  void _handleAuthError(dynamic error) {
    InstantDBLogging.root.severe('Authentication error: $error');
    batch(() {
      _connectionStatus.value = false;
    });
    // Could implement retry logic or user notification here
  }

  void _handleWebSocketError(Object error) {
    InstantDBLogging.root.severe('WebSocket error: $error');
    batch(() {
      _connectionStatus.value = false;
      _status.value = ConnectionStatus.errored;
    });
    _scheduleReconnect();
  }

  void _handleWebSocketClose() {
    InstantDBLogging.root.info('WebSocket connection closed');
    batch(() {
      _connectionStatus.value = false;
      _status.value = ConnectionStatus.closed;
    });
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(config.reconnectDelay, () {
      if (!_connectionStatus.value) {
        _connectWebSocket();
      }
    });
  }

  void _handleAuthChange(AuthUser? user) {
    // InstantDB authenticates the connection via the `init` handshake, which
    // carries the refresh-token. A mid-connection auth message does not
    // re-authenticate the session, so reconnect instead: closing triggers the
    // reconnect path, which re-runs `init` with the new (or cleared) token.
    // This is what makes authed writes (owner-scoped entities, trials, files)
    // actually sync to the server after login.
    // Only when a socket is already open; if none is up yet, the pending/next
    // connect will carry the current token (avoids a double-connect race with
    // the initial auth-state emission at startup).
    if (_webSocket != null && _webSocket.isOpen) {
      _webSocket.close(); // → _handleWebSocketClose → reconnect → init w/ token
    }
  }

  void _handleLocalChange(TripleChange change) {
    // Local changes are handled by the transaction system
    // This is mainly for logging/debugging
  }
}
