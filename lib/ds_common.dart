library dslink.common;

import 'dart:async';
import 'ds_requester.dart';
import 'ds_responder.dart';

part 'src/common/node.dart';
part 'src/common/connection_handler.dart';

abstract class DsConnection {
  DsConnectionChannel get requesterChannel;
  DsConnectionChannel get responderChannel;
  /// 
  

  /// close the connection
  void close();
}
abstract class DsConnectionChannel {
  /// raw connection need to handle error and resending of data, so it can only send one map at a time
  /// a new getData function will always overwrite the previous one;
  /// requester and responder should handle the merging of methods
  void sendWhenReady(List getData());
  /// receive data from method stream
  Stream<List> get onReceive;
  
  /// whether the connection is ready to send and receive data
  bool get isReady;
  
  Future<DsConnectionChannel> get onDisconnected;
}

abstract class DsSession {
  DsRequester get requester;
  DsResponder get responder;
}

class DsStreamStatus {
  static const String initialize = 'initialize';
  static const String open = 'open';
  static const String closed = 'closed';
}

class DsErrorPhase {
  static const String request = 'request';
  static const String response = 'response';
}

class DsError {
  /// type of error
  String type;
  String detail;
  String msg;
  String path;
  String phase;
  
  DsError(this.msg, {this.detail, this.type, this.path, this.phase: DsErrorPhase.response});
  
  Map serialize() {
    Map rslt = {
      'msg': msg
    };
    if (type != null) {
      rslt['type'] = type;
    }
    if (path != null) {
      rslt['path'] = path;
    }
    if (phase == DsErrorPhase.request) {
      rslt['phase'] = DsErrorPhase.request;
    }
    if (detail != null) {
      rslt['detail'] = detail;
    }
    return rslt;
  }
}
