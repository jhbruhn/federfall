// The /info reader now lives in zugvogel_pb_client (eiermann-d2a.4). Still
// fails OPEN: an unreachable or unparseable /info yields null and the login
// screen falls back to its default options rather than blocking.
export 'package:zugvogel_pb_client/zugvogel_pb_client.dart'
    show serverInfoProvider;
