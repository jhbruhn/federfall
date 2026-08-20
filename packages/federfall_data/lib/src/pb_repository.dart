// The generic PocketBase repository layer now lives in zugvogel_data
// (eiermann-d2a.2). This file stays as the import path every typed repository
// in this package already uses.
//
// Re-exported by NAME, not as a whole library: zugvogel_data also exports
// newIdempotencyKey and RepositoryException, which have their own paths here,
// and a blanket re-export would give each of them two.
//
// What moved, unchanged: filterExpr (so a raw filter string stays a compile
// error), keyset page() with its cursor, the auto-paginated list, server-side
// count, firstWhere, createWithFiles/updateWithFiles, fileUrl, and guard()'s
// write flag — the one that reports a timed-out WRITE as unknownOutcome rather
// than as a network error, so the UI never says "not reached, retry" over a
// change that may have landed.
export 'package:zugvogel_data/zugvogel_data.dart'
    show
        PbCursor,
        PbFilter,
        PbPage,
        PbReadOnlyRepository,
        PbRepository,
        PbSortKey,
        ReadOnlyRepository,
        Repository;
