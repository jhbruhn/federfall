// The online/offline signal now lives in zugvogel_pb_client (eiermann-d2a.4),
// still de-flapping across two probes so a transient blip right after resume
// does not latch a spurious offline banner (federfall-vcm).
export 'package:zugvogel_pb_client/zugvogel_pb_client.dart'
    show OnlineStatus, confirmStatus, onlineStatusProvider;
