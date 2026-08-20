// waitUnwrapped now lives in zugvogel_core (eiermann-d2a.3).
//
// Still the reason it exists: `dart:async`'s record `.wait` reports ANY failure
// as a ParallelWaitError, so error mapping that switches on the concrete type
// falls through to a generic message AND takes the content already on screen
// with it (federfall-s5mm).
export 'package:zugvogel_core/zugvogel_core.dart'
    show FutureRecord2, FutureRecord3, FutureRecord4, FutureRecord5,
        FutureRecord7;
