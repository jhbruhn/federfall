# Self-hosting Federfall

Federfall runs as a single Docker container.
One version-pinned PocketBase image serves the API, the admin dashboard and the Flutter web app on the same port, and renders the PDF case reports itself.
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

### Geocoding

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

How long a cached lookup stays good is tunable too, though the defaults are sensible and most instances never touch these.
Addresses do not move, so successful lookups are held for a month; a lookup that found nothing is retried sooner, in case the upstream data improves:

```yaml
FEDERFALL_GEOCODE_CACHE_TTL_DAYS: "30"       # how long a successful lookup is reused
FEDERFALL_GEOCODE_CACHE_NEG_TTL_HOURS: "24"  # how long an empty result is remembered
FEDERFALL_GEOCODE_CACHE_DISABLED: "1"        # bypass the cache entirely (debugging)
```

### Maps

Map *tiles* are a separate matter from geocoding.
The server tells the app which tile source to use, so you point the maps wherever you like from the environment — no image rebuild, and no APK rebuild.
Both the web app and the Android app pick it up; the Android app follows whichever server it is signed in to.

The shipped `docker-compose.yml` sets OpenStreetMap's public raster tiles:

```yaml
FEDERFALL_MAP_MODE: "raster"
FEDERFALL_MAP_TILE_URL: "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
FEDERFALL_MAP_ATTRIBUTION: "© OpenStreetMap contributors"
FEDERFALL_MAP_ATTRIBUTION_URL: "https://www.openstreetmap.org/copyright"   # optional
```

> **Repoint `FEDERFALL_MAP_TILE_URL` before you grow.**
> The [OSM Tile Usage Policy](https://operations.osmfoundation.org/policies/tiles) does not cover using their public tiles as an application backend — it is fine while a couple of carers occasionally look at find-locations, and not fine as your permanent map layer.
> Federfall holds up its own end of that policy (caches tiles on disk, never bulk-prefetches, and identifies itself — in the user agent on Android, and on web via the `Referer`, since browsers forbid a script from setting a user agent), but the traffic decision is yours.
> A self-hosted tile server or a commercial provider is the same one variable.
>
> That web identification is why the container sends `Referrer-Policy: strict-origin-when-cross-origin`.
> If you override it with something stricter (`same-origin`, `no-referrer`) at a reverse proxy, OSM sees anonymous tile requests and answers **403** — a map that stays blank on the web app while Android works is this.
> Only the bare origin is ever sent cross-origin, never a case URL.

Vector tiles instead — a self-hosted [OpenFreeMap](https://openfreemap.org)/OpenMapTiles stack is considerably cheaper to serve than a raster one:

```yaml
FEDERFALL_MAP_MODE: "vector"
FEDERFALL_MAP_STYLE_URL: "https://tiles.yourdomain.tld/styles/liberty"
FEDERFALL_MAP_ATTRIBUTION: "© OpenMapTiles © OpenStreetMap contributors"
```

Expect worse rendering than raster if you do: the vector path draws tiles on the Dart canvas with no GPU acceleration, which costs frame rate and label quality. It is supported, just not the default.

A commercial provider that keys its tiles takes one more variable:

```yaml
FEDERFALL_MAP_API_KEY: "your-provider-key"
```

The app substitutes it for a `{key}` token anywhere in the URL — and in vector mode also inside the style's own tile, sprite and glyph URLs, which is the part you cannot do by hand from here.
For a raster provider you can equally just write the key straight into `FEDERFALL_MAP_TILE_URL` as a query parameter; both work.

Be aware that **this key is public**: `/api/federfall/info` is unauthenticated, so anyone who can reach your server can read it.
That is not really a step down from the alternative — a web app hands its map key to every browser's devtools, and the release APK is a public download — but it does reduce extraction to a single request.
Restrict the key to your domain at the provider if they support it, and prefer a provider whose free tier needs no key at all.

The mode, the URL for that mode, and the attribution are **all three required together**.
Set an incomplete combination and the whole thing is ignored — the container logs a warning saying so, and the app keeps its built-in default.
That is deliberate: nearly every tile provider requires you to display a specific credit, and a map that quietly renders your new provider's tiles under the built-in OpenFreeMap credit is a licensing problem rather than a cosmetic one.
The attribution *link* is the one optional part; without it the credit shows as plain text instead of linking a copyright page that describes some other provider.

You do **not** need to touch the Content-Security-Policy for this.
The policy the container sends derives its allowed origins from the URLs above, so a tile server you configure is a tile server the browser is allowed to load.

The exception is a vector style whose sprites, glyphs or tiles live on a *different* host than the style JSON itself — nothing can infer those from the URL, so list them:

```yaml
FEDERFALL_MAP_TILE_ORIGINS: "https://sprites.yourdomain.tld"
```

That is a comma-separated list of origins added to both `img-src` and `connect-src`, and it is the only part of the policy you should normally need to touch.
Setting it also *replaces* the two default origins (OpenFreeMap and OpenStreetMap) that are otherwise allowed — the origins derived from your `FEDERFALL_MAP_*` URLs are always added on top either way.
If your maps come up blank on the web app, this is the first thing to check: the browser console will name the origin it blocked.

The whole policy can be replaced if you need something the above cannot express — self-hosted fonts, say:

```yaml
FEDERFALL_CSP: "default-src 'self'; …"   # replaces the entire policy
```

Setting `FEDERFALL_CSP` ignores `FEDERFALL_MAP_TILE_ORIGINS`, so a replacement policy has to allow your tile origins itself.
The value `"off"` sends no policy at all; that removes a real layer of defence and is worth doing only to prove a CSP is what is breaking something.

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

Whichever proxy you use, also tell PocketBase which header carries the real client address:

```yaml
FEDERFALL_TRUSTED_PROXY_HEADERS: "X-Forwarded-For"
```

Behind a proxy, every request otherwise appears to come from the proxy itself, so the per-client rate limit on the geocoding endpoint would be one shared budget for all of your users instead of one per user. Caddy and nginx set `X-Forwarded-For` by default. Only list a header your own proxy overwrites on the way in — a header passed through from the client would let anyone dodge the rate limit. If you chain several proxies, set `FEDERFALL_TRUSTED_PROXY_USE_LEFTMOST_IP: "true"` and make the outermost one strip the header from incoming requests.

### Access logs

Protected file downloads (`/api/files/...`) carry a short-lived (~2 minute) access token as a `?token=...` query parameter. Your reverse proxy's access log records the full request URL by default, so it will capture that token alongside every file request. It expires quickly and is scoped to one file, but treat proxy access logs as sensitive and scrub or redact the `token` query parameter if you ship them anywhere (log aggregation, long-term storage). With Caddy, a custom `log_format` that strips the query string (or just the `token` param) avoids storing it in the first place.

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
To move to a newer PocketBase, bump `PB_VERSION` in the root `Dockerfile` (and its
per-arch `PB_SHA256` checksums) and in `docker-compose.yml`, then run the same command.

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
FEDERFALL_OAUTH2_OIDC_PKCE: "true"                             # the default; leave it on
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
| `FEDERFALL_OAUTH2_<NAME>_PKCE` | OIDC | `"true"` or `"false"`. Omit it to keep PocketBase's default, which is **on** for OIDC. Only set `"false"` for a provider that genuinely cannot do PKCE: the mobile apps sign in through the `federfall://oauth-callback` custom scheme below, and PKCE is what stops another app on the device from claiming that scheme and redeeming the intercepted authorization code as the user. |

Register **two** redirect/callback URIs with your provider — both, so the flow works from every client:

| Redirect URI | Used by | Why |
| --- | --- | --- |
| `<your app URL>/api/oauth2-redirect` | Web | The provider returns to this callback on your own server, which hands the result back to the waiting browser tab over its realtime connection. |
| `federfall://oauth-callback` | Android & iOS | The mobile apps use a deep link instead: the provider redirects straight back into the app. |

The mobile app needs the second one because it can't rely on the server-relay-over-realtime path the web app uses — while the user is on the provider's page the phone backgrounds the app and drops that connection, so the redirect would be lost (it surfaced as "Auth failed", usually on the first attempt). The deep link sidesteps that: the OS hands the result to the app directly. `federfall://oauth-callback` is a fixed value baked into the app — enter it verbatim; there is nothing to configure on your server for it, only in the provider's allowed-redirect-URI list. Providers word this field differently ("Redirect URIs", "Sign-in redirect URIs", "Valid redirect URIs", "Callback URLs") and most accept a custom scheme like this directly; a strict few only allow `https`, in which case host an `https` page that 302-redirects to `federfall://oauth-callback` and register that instead.

If the provider also asks for allowed origins, add your app URL there too.

When `FEDERFALL_OAUTH2_PROVIDERS` is set, the environment is the source of truth and is re-applied on every start. If you would rather not keep the credentials in the compose file, leave it unset and register providers in the admin dashboard instead, under the `users` collection's auth settings. Either way, once a provider is registered it becomes a sign-in option.

### About OAuth2 scopes

There is nothing to configure here, but it is worth knowing what happens, because it explains a class of "my groups aren't working" confusion.

PocketBase asks every OIDC provider for a fixed, minimal set of scopes — `openid`, `email`, `profile` — and offers no server-side setting to widen it. That is deliberate upstream: the scopes live in the authorization URL, which the *client* opens, so [PocketBase treats them as the client's business](https://github.com/pocketbase/pocketbase/discussions/7114). Putting a `?scope=` on `FEDERFALL_OAUTH2_<NAME>_AUTH_URL` does not work either — PocketBase appends its own `scope` afterwards and the duplicate wins.

That matters because most identity providers only release a claim if the matching scope was requested. Group memberships are the usual case: without the `groups` scope the claim is simply absent, and the [group-to-role mapping](#who-may-register-and-as-what) has nothing to match on, so everyone lands as a guest.

So when you configure a group mapping, the server tells the app to request the groups scope alongside the defaults, and the app asks for it on the next sign-in. It applies only to generic OIDC providers; a social provider like Google would reject the whole authorization request over a scope it doesn't know, and doesn't do group mapping anyway. The scope is named after `FEDERFALL_OIDC_GROUPS_CLAIM` (`groups` by default), since providers name the two alike.

Two consequences worth knowing:

- **The app has to be new enough.** The scope list is published on `/api/federfall/info`; a client from before this existed ignores it and keeps requesting only the defaults, so group mapping won't work for that client until it updates.
- **The provider must allow the scope.** If it answers `invalid_scope`, grant it to this client on the provider side.

#### Nextcloud

Nextcloud's OIDC provider app only emits `groups` when the `groups` scope is requested, which the above handles. Two of its own knobs matter as well:

```bash
# GIDs (the default) or display names in the claim — must match what you put
# in FEDERFALL_OIDC_*_GROUP below
occ config:app:set oidc group_claim_type --value "displayname"
```

Nextcloud also reports `email_verified: false` until the user confirms their address in their personal settings, which is why fresh SSO accounts show up as "invite pending" — see `FEDERFALL_OIDC_TRUST_EMAIL` above.

If your app is older than the scope support and you can't update it yet, there is a server-only alternative: attach a custom claim to a scope PocketBase already requests.

```bash
occ oidc:create-claim groups profile <CLIENT_ID> getUserGroupsDisplayName
occ oidc:list-claim
```

Use `getUserGroups` instead for GIDs. Avoid the `...String` variants — they return one comma-joined string, which is read as a single oddly-named group.

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

Setting any of these makes the app request the groups scope from a generic OIDC provider, which is what gets the claim sent at all — see [About OAuth2 scopes](#about-oauth2-scopes). The group names must match what the claim actually carries, which for several providers is an internal id rather than the display name you see in their admin UI.

With a supervisor group configured, putting yourself in it at the provider is the cleanest bootstrap: your first sign-in lands you straight in as a supervisor. Anyone matching no group becomes a guest for a supervisor to promote. Plain social logins (Google, GitHub) don't carry groups, so there everyone falls back to guest.

The mapping is applied when the account is first created, not on every sign-in. Changing someone's groups at the provider afterwards does not change their Federfall role — a supervisor changes it in the app (or deletes the account so the next sign-in re-provisions it).

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
