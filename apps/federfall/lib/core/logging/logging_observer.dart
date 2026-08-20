// LoggingProviderObserver now lives in zugvogel_pb_client (eiermann-d2a.4),
// which is where Zugvogel's shared riverpod plumbing lives — zugvogel_core
// stays pure Dart with no Flutter dependency.
export 'package:zugvogel_pb_client/zugvogel_pb_client.dart'
    show LoggingProviderObserver;
