// The version check now lives in zugvogel_pb_client (eiermann-d2a.4), still
// failing OPEN in every uncertain case — a false positive locks the user out of
// the app entirely, which is far worse than letting a genuinely incompatible
// pair through to a clearer runtime error.
export 'package:zugvogel_pb_client/zugvogel_pb_client.dart'
    show
        ServerCompatibility,
        checkServerCompatibility,
        serverCompatibilityProvider;
