// DateField, DateStyle, formatLocalDate and the two pickers now live in
// zugvogel_ui (eiermann-d2a.9). The label and placeholder were always the
// caller's, so nothing had to be injected.
//
// formatLocalDate stays the only place a DateTime becomes a date string, and
// the sweep that enforces it moved with it: `rawDateFormattingOffenders` in
// `package:zugvogel_ui/testing.dart` runs over each app's own `lib/`, because
// the defect it catches — a UTC calendar day rendered a day early near
// midnight — is invisible on a UTC-clocked machine and only reaches real users.
export 'package:zugvogel_ui/zugvogel_ui.dart'
    show DateField, DateStyle, formatLocalDate, pickDate, pickDateTime;
