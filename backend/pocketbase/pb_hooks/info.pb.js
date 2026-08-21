/// <reference path="../pb_data/types.d.ts" />

// GET /api/federfall/info — what a client is allowed to know before it has an
// account, and the contract it checks before trusting a server at all.
//
// zv_info.js builds the payload and holds the reasoning: why the version comes
// from the RUNNING IMAGE rather than a source file, why `passwordReset` is
// `password && smtpEnabled` (offering a reset link that cannot send mail is
// worse than not offering one), why the map configuration is all-or-nothing
// (a half-applied override names the wrong provider, which is a licensing
// problem), and why the response carries the service name twice — as `service`
// and as a boolean keyed on it — so a client can refuse a server belonging to
// the other app rather than half-working against the wrong schema.
//
// `selfSignup: false`: registration here is invite-only, and every invite is
// sent BY a supervisor.

routerAdd("GET", "/api/federfall/info", (e) =>
  require(`${__hooks}/zv_info.js`).respond(e, {
    service: "federfall",
    envPrefix: "FEDERFALL",
    defaultName: "Federfall",
    selfSignup: false,
  }),
);
