// The PocketBase field converters now live in zugvogel_core (eiermann-d2a.3).
//
// This file stays as the import path every mapper in this package already uses,
// so the move is invisible to them. It re-exports by NAME rather than the whole
// library on purpose: zugvogel_core also exports Result, AppLogger and the
// parallel-wait extensions, and this app has its own Result and AppLogger —
// a blanket re-export would make both ambiguous wherever the two are imported
// together.
export 'package:zugvogel_core/zugvogel_core.dart'
    show
        pbBool,
        pbCount,
        pbDate,
        pbDouble,
        pbEnum,
        pbEnumList,
        pbInt,
        pbQuantity,
        pbString,
        pbStringList;
