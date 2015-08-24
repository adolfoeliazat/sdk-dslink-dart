part of dslink.requester;

abstract class RequestUpdater {
  void onUpdate(String status, List updates, List columns, Map meta, DSError error);
  void onDisconnect();
  void onReconnect();
}

class RequesterUpdate {
  final String streamStatus;

  RequesterUpdate(this.streamStatus);
}

class Requester extends ConnectionHandler {
  Map<int, Request> _requests = new Map<int, Request>();

  /// caching of nodes
  final RemoteNodeCache nodeCache;

  SubscribeRequest _subsciption;

  Requester([RemoteNodeCache cache])
      : nodeCache = cache != null ? cache : new RemoteNodeCache() {
    _subsciption = new SubscribeRequest(this, 0);
    _requests[0] = _subsciption;
  }

  void onData(List list) {
    for (Object resp in list) {
      if (resp is Map) {
        _onReceiveUpdate(resp);
      }
    }
  }

  void _onReceiveUpdate(Map m) {
    if (m['rid'] is int && _requests.containsKey(m['rid'])) {
      _requests[m['rid']]._update(m);
    }
  }

  int nextRid = 1;
  int nextSid = 1;

  // TODO need a new design for short polling and long polling
  int lastSentId = 0;

  ProcessorResult getSendingData(int currentTime, int waitingAckId) {
    ProcessorResult rslt = super.getSendingData(currentTime, waitingAckId);
    lastSentId = nextRid - 1;
    return rslt;
  }

  Request _sendRequest(Map m, RequestUpdater updater) {
    m['rid'] = nextRid;
    Request req;
    if (updater != null) {
      req = new Request(this, nextRid, updater, m);
      _requests[nextRid] = req;
    }
    addToSendList(m);
    ++nextRid;
    return req;
  }

  bool isNodeCached(String path) {
    return nodeCache.isNodeCached(path);
  }

  ReqSubscribeListener subscribe(String path, callback(ValueUpdate update),
      [int qos = 0]) {
    RemoteNode node = nodeCache.getRemoteNode(path);
    node._subscribe(this, callback, qos);
    return new ReqSubscribeListener(this, path, callback);
  }

  Stream<ValueUpdate> onValueChange(String path, [int qos = 0]) {
    ReqSubscribeListener listener;
    StreamController<ValueUpdate> controller;
    int subs = 0;
    controller = new StreamController<ValueUpdate>.broadcast(onListen: () {
      subs++;
      if (listener == null) {
        listener = subscribe(path, (ValueUpdate update) {
          controller.add(update);
        }, qos);
      }
    }, onCancel: () {
      subs--;
      if (subs == 0) {
        listener.cancel();
        listener = null;
      }
    });
    return controller.stream;
  }

  Future<ValueUpdate> getNodeValue(String path) {
    var c = new Completer<ValueUpdate>();
    ReqSubscribeListener listener;
    listener = subscribe(path, (ValueUpdate update) {
      c.complete(update);
      if (listener != null) {
        listener.cancel();
      }
    });
    return c.future;
  }

  Future<RemoteNode> getRemoteNode(String path) {
    var c = new Completer<RemoteNode>();
    StreamSubscription sub;
    sub = list(path).listen((update) {
      c.complete(update.node);
      if (sub != null) {
        sub.cancel();
      }
    }, onError: (e, stack) {
      c.completeError(e, stack);
    }, cancelOnError: true);
    return c.future;
  }

  void unsubscribe(String path, callback(ValueUpdate update)) {
    RemoteNode node = nodeCache.getRemoteNode(path);
    node._unsubscribe(this, callback);
  }

  Stream<RequesterListUpdate> list(String path) {
    RemoteNode node = nodeCache.getRemoteNode(path);
    return node._list(this);
  }

  Stream<RequesterInvokeUpdate> invoke(String path, Map params,
      [int maxPermission = Permission.CONFIG]) {
    RemoteNode node = nodeCache.getRemoteNode(path);
    return node._invoke(params, this, maxPermission);
  }

  Future<RequesterUpdate> set(String path, Object value,
      [int maxPermission = Permission.CONFIG]) {
    return new SetController(this, path, value, maxPermission).future;
  }

  Future<RequesterUpdate> remove(String path) {
    return new RemoveController(this, path).future;
  }

  /// close the request from requester side and notify responder
  void closeRequest(Request request) {
    if (_requests.containsKey(request.rid)) {
      if (request.streamStatus != StreamStatus.closed) {
        addToSendList({'method': 'close', 'rid': request.rid});
      }
      _requests.remove(request.rid);
      request._close();
    }
  }

  bool _connected = false;

  void onDisconnected() {
    if (!_connected) return;
    _connected = false;

    var newRequests = new Map<int, Request>();
    ;
    newRequests[0] = _subsciption;
    _requests.forEach((n, req) {
      if (req.rid <= lastSentId && req.updater is! ListController) {
        req._close(DSError.DISCONNECTED);
      } else {
        newRequests[req.rid] = req;
        req.updater.onDisconnect();
      }
    });
    _requests = newRequests;
  }

  void onReconnected() {
    if (_connected) return;
    _connected = true;

    super.onReconnected();

    _requests.forEach((n, req) {
      req.updater.onReconnect();
      req.resend();
    });
  }
}
