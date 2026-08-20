// newIdempotencyKey now lives in zugvogel_data (eiermann-d2a.2): 128 bits of
// secure randomness as 32 hex chars, one key per logical operation, reused for
// every retry of it.
export 'package:zugvogel_data/zugvogel_data.dart' show newIdempotencyKey;
