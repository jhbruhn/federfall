# Self-hosting Federfall

Federfall runs as a single Docker container.
One version-pinned PocketBase image serves the API, the admin dashboard and the Flutter web app, all on the same port.
There is no separate database server and no web server to wire up — you run one container, put a reverse proxy in front of it for HTTPS, and that is the whole stack.

This guide walks through a production deployment on your own machine.

## What you need

- A host with Docker and the Compose plugin.
- A domain name pointing at that host, if you want HTTPS (you do).
- A reverse proxy to terminate TLS. The stack speaks plain HTTP on a host port; it deliberately does not handle certificates itself, so you can use whatever proxy you already run. Caddy is the least effort and is used in the examples below.

## Getting it running

Clone the repository and start the stack from its root:

```bash
git clone https://github.com/jhbruhn/federfall.git
cd federfall
docker compose -f docker-compose.yml up -d --build
```

The `-f docker-compose.yml` matters: it runs the production file explicitly and skips `docker-compose.override.yml`, which only exists for local development.
The first build compiles the Flutter web app and takes a few minutes.
Once it is up, the app answers on `http://<host>:8090`.

That port is HTTP only. Don't expose it to the internet directly — put a proxy in front of it (see [HTTPS](#https) below).

## Configuration

All configuration is done with environment variables, set directly in `docker-compose.yml` under the `app` service.
There is no `.env` file to copy; you edit the compose file and the values live there.
Secrets you would rather not keep in that file (SMTP passwords, for instance) can be set in your shell or your orchestrator instead — Compose reads them from the environment if you leave them unquoted there.

The variables are grouped by what they do. None of them are required to *start* the container, but a few are required for it to be useful.

### App URL

```yaml
FEDERFALL_APP_URL: "https://federfall.yourdomain.tld"
```

This is your instance's public address.
It is used in the links inside outgoing emails, so password-reset and invite mails point at the right place.
Set it to the same URL your users will open.

### Mail

Invites and password resets are sent by email, so without SMTP a freshly invited user never receives their link.
The stack leaves mail off until you give it a host:

```yaml
FEDERFALL_SMTP_HOST: "smtp.yourprovider.tld"
FEDERFALL_SMTP_PORT: "587"            # 465 for implicit TLS
FEDERFALL_SMTP_USERNAME: "..."
FEDERFALL_SMTP_PASSWORD: "..."
FEDERFALL_SMTP_TLS: "false"           # "true" for implicit TLS (port 465)
FEDERFALL_SMTP_SENDER_ADDRESS: "noreply@yourdomain.tld"
FEDERFALL_SMTP_SENDER_NAME: "Federfall"
```

These are applied on every start, so changing them means editing the file and recreating the container.

### Geocoding and maps

Address search goes through the backend, which forwards to a Nominatim-compatible geocoder:

```yaml
FEDERFALL_NOMINATIM_URL: "https://nominatim.yourdomain.tld"
FEDERFALL_USER_AGENT: "Federfall/1.0 (you@yourdomain.tld)"
FEDERFALL_GEOCODER_KEY: ""            # only for keyed mirrors
```

A word of warning: the default is the public OpenStreetMap Nominatim, and that server blocks most server-to-server traffic.
Address search will likely fail against it.
For real use, run your own Nominatim instance or use a mirror that permits backend traffic, and set a real contact address in the user agent.

Successful lookups are cached server-side, and the geocode routes are rate-limited per client IP so no single user can relay bulk queries to the upstream geocoder.
The default budget — 30 requests per 60 seconds — comfortably covers interactive address searches while capping sustained extraction.
Tune it if your upstream allows more (or less):

```yaml
FEDERFALL_GEOCODE_RATE_MAX: "30"      # requests per window per client IP; "0" disables
FEDERFALL_GEOCODE_RATE_WINDOW: "60"   # window length in seconds
```

Map *tiles* are a separate matter. They are baked into the web build, not read from the environment, and default to the public OpenStreetMap tile server.
To change them you edit `apps/federfall/dart_defines/production.json` (`MAP_TILE_URL`, `MAP_ATTRIBUTION`) and rebuild the image.

### Time zone

```yaml
TZ: "Europe/Berlin"
```

Set this to your local zone so timestamps in logs read sensibly.

## HTTPS

The container does not do TLS. Point a reverse proxy at `localhost:8090` and let it handle certificates.

With Caddy, the whole configuration is two lines:

```caddyfile
federfall.yourdomain.tld {
    reverse_proxy localhost:8090
}
```

Caddy obtains and renews the certificate on its own, streams the realtime updates the app relies on, and does not cap upload sizes — so photo uploads and live updates work without further tuning.

If you prefer nginx, two settings matter: raise `client_max_body_size` (photos can be a few megabytes) and turn off proxy buffering for `/api/realtime` so server-sent events are not held back.

## First login

Registration is invite-only, and every invite is sent by an existing supervisor.
That leaves the first supervisor as a chicken-and-egg problem, so the stack can create one for you on first start.
Set both of these before bringing the container up:

```yaml
FEDERFALL_SUPERVISOR_EMAIL: "you@yourdomain.tld"
FEDERFALL_SUPERVISOR_PASSWORD: "a-strong-password"
FEDERFALL_SUPERVISOR_NAME: "Your Name"
```

A supervisor is created the next time the container starts, but only while no active supervisor exists.
That makes it safe to leave in place — it does nothing once a supervisor is present — and it also gives you a way back in if you ever lock yourself out.
Once you have logged in, you can remove the two variables.

From there you invite the rest of your team from inside the app.

The mobile apps ask for your server's address on first launch, so give your users the same URL you set in `FEDERFALL_APP_URL`.

## The admin dashboard

PocketBase ships an admin dashboard at `/_/`. You do not need it for normal operation: the database schema is fixed by the image and the settings above are applied from the environment.

It is there if you want it — to browse data, read logs or make a manual fix.
A dashboard login (a PocketBase *superuser*, which is not the same as an app supervisor) is created on demand:

```bash
docker compose exec app pocketbase superuser upsert you@yourdomain.tld <password>
```

If you never use the dashboard, you can block `/_/` at your reverse proxy and forget about it.

## Updating

Pull the latest code and rebuild:

```bash
git pull
docker compose -f docker-compose.yml up -d --build
```

Database migrations are applied automatically when the new container starts.
To move to a newer PocketBase, bump `PB_VERSION` in the root `Dockerfile` and the image tag in `docker-compose.yml`, then run the same command.

## Sign-in options

Two extra sign-in features are available beyond email and password.

**Two-factor authentication** is opt-in per user. Anyone can turn it on from their profile in the app; once on, signing in asks for a one-time code sent to their email after the password. It needs SMTP (see [Mail](#mail)) — without it the code can't be delivered. Nothing to configure on the server side; it is on offer to every user out of the box.

**OAuth2** lets people sign in through an external provider instead of a password. The capability is enabled, but no providers are registered by default — that part is yours to set up.

List the providers you want in `FEDERFALL_OAUTH2_PROVIDERS` (comma-separated), then give each one its credentials. The variable names are `FEDERFALL_OAUTH2_<NAME>_…`, where `<NAME>` is the provider name upper-cased. For a well-known provider — `google`, `github`, `microsoft`, `apple`, `gitlab`, `discord` and the like — the client id and secret are all that's needed; PocketBase already knows that provider's endpoints:

```yaml
FEDERFALL_OAUTH2_PROVIDERS: "google"
FEDERFALL_OAUTH2_GOOGLE_CLIENT_ID: "..."
FEDERFALL_OAUTH2_GOOGLE_CLIENT_SECRET: "..."
```

For a self-hosted identity provider — Authentik, Keycloak, Authelia, Zitadel and so on — use the generic OIDC provider name `oidc` (or `oidc2`, `oidc3` for a second and third) and give it the endpoints as well:

```yaml
FEDERFALL_OAUTH2_PROVIDERS: "oidc"
FEDERFALL_OAUTH2_OIDC_CLIENT_ID: "..."
FEDERFALL_OAUTH2_OIDC_CLIENT_SECRET: "..."
FEDERFALL_OAUTH2_OIDC_DISPLAY_NAME: "Single sign-on"           # the button label
FEDERFALL_OAUTH2_OIDC_AUTH_URL: "https://id.yourdomain.tld/application/o/authorize/"
FEDERFALL_OAUTH2_OIDC_TOKEN_URL: "https://id.yourdomain.tld/application/o/token/"
FEDERFALL_OAUTH2_OIDC_USERINFO_URL: "https://id.yourdomain.tld/application/o/userinfo/"
FEDERFALL_OAUTH2_OIDC_PKCE: "true"                             # most OIDC providers want this
```

The full set of per-provider variables:

| Variable | Required | Notes |
| --- | --- | --- |
| `FEDERFALL_OAUTH2_<NAME>_CLIENT_ID` | yes | OAuth2 client id from the provider |
| `FEDERFALL_OAUTH2_<NAME>_CLIENT_SECRET` | yes | OAuth2 client secret |
| `FEDERFALL_OAUTH2_<NAME>_DISPLAY_NAME` | OIDC | Label shown on the sign-in button |
| `FEDERFALL_OAUTH2_<NAME>_AUTH_URL` | OIDC | Authorization endpoint; setting it marks the provider as a custom OIDC |
| `FEDERFALL_OAUTH2_<NAME>_TOKEN_URL` | OIDC | Token endpoint |
| `FEDERFALL_OAUTH2_<NAME>_USERINFO_URL` | OIDC | Userinfo endpoint |
| `FEDERFALL_OAUTH2_<NAME>_PKCE` | OIDC | `"true"` or `"false"` |

The one URL to register with your provider is the redirect/callback `<your app URL>/api/oauth2-redirect`. You don't need to register anything app-specific beyond that: when someone taps a provider button the app opens the provider in a browser, and after the user approves, the provider returns to that callback on your own server, which hands the result back to the waiting app over its realtime connection. The app then lands signed in on its own — on web in the same tab, on mobile back in the app — with no custom URL scheme or deep-link setup on your side. If the provider also asks for allowed origins, add your app URL there too.

When `FEDERFALL_OAUTH2_PROVIDERS` is set, the environment is the source of truth and is re-applied on every start. If you would rather not keep the credentials in the compose file, leave it unset and register providers in the admin dashboard instead, under the `users` collection's auth settings. Either way, once a provider is registered it becomes a sign-in option.

### OAuth2 as the only sign-in method

If you want everyone to sign in through your provider and not with a password at all, turn password auth off:

```yaml
FEDERFALL_PASSWORD_AUTH: "false"
```

The server then advertises that password login is disabled and the app hides the password form, showing only the provider buttons. Configure at least one OAuth2 provider first, or no one will be able to sign in.

### Who may register, and as what

With OAuth2, people can sign in without being invited first. By default a new sign-in creates a walled-off **guest** account: they are signed in but can't see or do anything until a supervisor grants them a real role. This also sidesteps the invite chicken-and-egg — the very first person to sign in, while no supervisor exists yet, is made a supervisor automatically, so you can bootstrap the instance just by signing in.

That convenience is also a race: if you expose the server publicly with an OAuth2 provider configured **before** anyone has signed in, whoever signs in first becomes the supervisor. Claim the instance yourself before opening it up — sign in once, seed a supervisor via `FEDERFALL_SUPERVISOR_EMAIL`/`_PASSWORD`, or restrict registration with `FEDERFALL_OIDC_ALLOWED_GROUPS` (below) from the start.

A related trust question is the email address. The account's email is only marked *verified* when the provider says it verified it (the `email_verified` claim); otherwise the person still signs in fine but wears an "invite pending" badge in the team roster until a supervisor confirms them. If your IdP is a private, vetted directory that simply never sends `email_verified`, you can opt into trusting its email claim:

```yaml
FEDERFALL_OIDC_TRUST_EMAIL: "true"    # treat the IdP's email claim as verified
```

Leave it unset for public or social providers — with those, an unverified claim can be any address the user typed.

If your identity provider sends group memberships, you can do better than guest-by-default — map groups to roles, and optionally restrict who may register at all:

```yaml
FEDERFALL_OIDC_GROUPS_CLAIM: "groups"                 # the claim that holds the groups
FEDERFALL_OIDC_SUPERVISOR_GROUP: "federfall-admins"
FEDERFALL_OIDC_COORDINATOR_GROUP: "federfall-coordinators"
FEDERFALL_OIDC_CARER_GROUP: "federfall-carers"
FEDERFALL_OIDC_ALLOWED_GROUPS: ""                     # if set, only members of these may register at all
```

With a supervisor group configured, putting yourself in it at the provider is the cleanest bootstrap: your first sign-in lands you straight in as a supervisor. Anyone matching no group becomes a guest for a supervisor to promote. Plain social logins (Google, GitHub) don't carry groups, so there everyone falls back to guest.

## Finder data retention

A finder — the person who brought a bird in — is stored with their contact details so a carer can follow up.
Once their cases are closed there is no longer a reason to keep that personal data, so a daily job anonymises finders whose cases all ended longer ago than a retention window.
It clears the identifying fields (name, organisation, phone, email and the free-text notes) and keeps the rest, including the location, so you still know where birds tend to come from without holding anyone's personal data.

The window defaults to two years.
You can change it per organisation by setting `finder_retention_years` in the organisation's settings.

## Backups

All persistent state — the SQLite database and uploaded photos — lives in the `pb_data` Docker volume.
Backing that volume up is enough to capture everything.

PocketBase also has its own backup feature in the admin dashboard, which can produce and restore snapshots and can be put on a schedule.
Whichever you use, restore a backup into a throwaway instance at least once.
A backup you have never restored is a guess, not a backup.
