# Changelog

## [0.7.0](https://github.com/jhbruhn/federfall/compare/v0.6.2...v0.7.0) (2026-07-22)


### Features

* **exams:** add recognition hints for hydration and mucous membranes ([1e5bf76](https://github.com/jhbruhn/federfall/commit/1e5bf765de7f6ee5656513bb0c8a83802c5ab42e))


### Bug Fixes

* **cases:** render Overview intake dates in local time ([75b3db6](https://github.com/jhbruhn/federfall/commit/75b3db6863b6c1ffae0c7a88894046c6093ddfef))

## [0.6.2](https://github.com/jhbruhn/federfall/compare/v0.6.1...v0.6.2) (2026-07-22)


### Bug Fixes

* **auth:** pre-open OAuth2 window on web so iOS Safari doesn't block it ([c09e340](https://github.com/jhbruhn/federfall/commit/c09e3401a6525148683d244062f71a38974f6de0))

## [0.6.1](https://github.com/jhbruhn/federfall/compare/v0.6.0...v0.6.1) (2026-07-22)


### Bug Fixes

* **auth:** use deep-link code-exchange for mobile OAuth2 sign-in ([58bf624](https://github.com/jhbruhn/federfall/commit/58bf624ea6c50de369d8f82e1ede93031427ff9b))

## [0.6.0](https://github.com/jhbruhn/federfall/compare/v0.5.0...v0.6.0) (2026-07-22)


### Features

* **auth:** keep sessions alive with a token bump + silent refresh ([8670b00](https://github.com/jhbruhn/federfall/commit/8670b00a111f9720b7444887c0f1b3e0db97104f))


### Bug Fixes

* **cases:** widen scope to all cases when opening a case outside "mine" ([b678798](https://github.com/jhbruhn/federfall/commit/b67879875839ecf7313b10d85f1b992881b80017))

## [0.5.0](https://github.com/jhbruhn/federfall/compare/v0.4.0...v0.5.0) (2026-07-05)


### Features

* **cases:** add a server-side PDF case report (Typst) ([b43116d](https://github.com/jhbruhn/federfall/commit/b43116de71c11f9d815e2a1a1e36c6a654f8a412))
* **cases:** deep-link QR + Europe/Berlin timezone in the case report ([52a6397](https://github.com/jhbruhn/federfall/commit/52a6397ba71a7d04e26e6c729beca5b4d55f4f2a))
* **cases:** include the animal's photo in the PDF case report ([b4e10ef](https://github.com/jhbruhn/federfall/commit/b4e10efab9261b01e51c7adadaa2d1737b8b03ba))
* **cases:** open cases from hardware barcode-scanner hardware ([219da1d](https://github.com/jhbruhn/federfall/commit/219da1d56ebab9c4e6814d146ff83a98d5dcf6c8))
* **cases:** switch the case-report QR to a federfall:// deep link ([1bfa526](https://github.com/jhbruhn/federfall/commit/1bfa5262c538d7c15f9f323fb9cb1fb6ccf8705b))
* **printing:** connect and print to ESC/POS receipt printers ([b9515b9](https://github.com/jhbruhn/federfall/commit/b9515b9755a69709ab336cc2db1780b51ef0d300))
* **reports:** render receipt-printer PNGs alongside the PDF report ([5686188](https://github.com/jhbruhn/federfall/commit/5686188408369eff03db0b186e6e8a54d914cf2c))


### Bug Fixes

* **cases:** drive the report's timezone from the client, not a hard-coded zone ([3819304](https://github.com/jhbruhn/federfall/commit/38193040d72c7ee133820f5c05eb9acfddadc191))
* **cases:** resolve federfall:// deep links via go_router directly ([9e78cc7](https://github.com/jhbruhn/federfall/commit/9e78cc756498b7a7eabe9234bb26e168cced3fc7))
* **server-setup:** allow plain http:// on the development flavor ([cb24b0c](https://github.com/jhbruhn/federfall/commit/cb24b0c54df3c8649f5475ef0a4ed2d9a7f23663))

## [0.4.0](https://github.com/jhbruhn/federfall/compare/v0.3.1...v0.4.0) (2026-07-04)


### Features

* **cases:** add a consolidated photo gallery to the case Overview tab ([af6fa94](https://github.com/jhbruhn/federfall/commit/af6fa94f38f90ce6de000cbb64ee573685a6d2a6))
* **statistics:** add intake find-location overview map ([b7cb368](https://github.com/jhbruhn/federfall/commit/b7cb368c512ffd879b43a20f07733bab4ded13b1))
* **statistics:** show the intake map as a preview card, not a menu action ([08ec449](https://github.com/jhbruhn/federfall/commit/08ec4499ffce370e253aec5eda8e3bdedc2513c9))


### Bug Fixes

* **statistics:** enrich the intake pin sheet and fix "Open case" navigation ([395d41b](https://github.com/jhbruhn/federfall/commit/395d41b34d747dd292d24c0bfd0443981031202d))
* **ui:** open the fullscreen image viewer on the root navigator ([7bbb299](https://github.com/jhbruhn/federfall/commit/7bbb29950e36cb8d4a86b4d7675568a8303d62ad))

## [0.3.1](https://github.com/jhbruhn/federfall/compare/v0.3.0...v0.3.1) (2026-07-04)


### Bug Fixes

* **cases:** clarify share sheet empty state and add carer role hint ([0d41871](https://github.com/jhbruhn/federfall/commit/0d41871ef9bbc4578efea1d4667231496c5d5e9f))

## [0.3.0](https://github.com/jhbruhn/federfall/compare/v0.2.1...v0.3.0) (2026-07-04)


### Features

* **animals:** supervisor duplicate-merge flow (federfall-eqy6) ([e02a819](https://github.com/jhbruhn/federfall/commit/e02a819589cf581ee3ed9952a3f89ff890634bf1))
* **aviaries:** aviary residency ledger (aviary_stays) + centralized hook ([d487ddb](https://github.com/jhbruhn/federfall/commit/d487ddba1bbd93dbcef865660267f22acdd0819b))
* **aviaries:** Bestand/Pflege tabs + flock-care timeline ([82b382b](https://github.com/jhbruhn/federfall/commit/82b382b0198fee0286e16ac74426977f85484c2f))
* **aviaries:** dual-parent journal_entries (case OR aviary) ([ba4be01](https://github.com/jhbruhn/federfall/commit/ba4be018d102ca3a4476acf66481cdfc37607a6d))
* **conditions:** add a contagious flag, distinct from notifiable ([c00b788](https://github.com/jhbruhn/federfall/commit/c00b7881077ee58b31040aed30fe215c234d2b43))
* **profile:** show app and server version ([e8ba472](https://github.com/jhbruhn/federfall/commit/e8ba4729b04ffc6e59c8a0d04b8edefcd85a008d))


### Performance Improvements

* **aviaries:** fix N+1 query in the flock health rollup ([ba4db6b](https://github.com/jhbruhn/federfall/commit/ba4db6b74c6c69b8ec659e24755ab1b36f4a4fe4))
* **data:** trim the flock rollup's fetches to columns it reads ([93b2962](https://github.com/jhbruhn/federfall/commit/93b29627995303f9774c51a46920313e1eda2331))

## [0.2.1](https://github.com/jhbruhn/federfall/compare/v0.2.0...v0.2.1) (2026-07-03)


### Bug Fixes

* **routing:** stop stranding users on the profile screen ([ca8a614](https://github.com/jhbruhn/federfall/commit/ca8a61461dd6733c337df21eaba4e773b8268f27))
* **routing:** use go_router state restoration; fix cross-branch stranding ([f692a4f](https://github.com/jhbruhn/federfall/commit/f692a4f4d43211d6f80ffee7f6ecf88a79a955c7))

## [0.2.0](https://github.com/jhbruhn/federfall/compare/v0.1.2...v0.2.0) (2026-07-03)


### Features

* **app:** send a federfall/&lt;version&gt; User-Agent instead of the Dart default ([8f1af45](https://github.com/jhbruhn/federfall/commit/8f1af450ddad600f93b927e6c2db0705b4ace926))


### Bug Fixes

* **auth:** open OAuth2 sign-in in an in-app browser tab on mobile ([af3df78](https://github.com/jhbruhn/federfall/commit/af3df782c4ff58091f4f4edc4a585dd4ce7ad867))
* **ci:** generate federfall_models codegen before analyze ([55bb920](https://github.com/jhbruhn/federfall/commit/55bb9203f3b258ec745f25868ddbe3bc7dd9dd10))

## [0.1.2](https://github.com/jhbruhn/federfall/compare/v0.1.1...v0.1.2) (2026-07-03)


### Bug Fixes

* **android:** add missing INTERNET permission to the release manifest ([a929bfc](https://github.com/jhbruhn/federfall/commit/a929bfc8d3063bfa448c9232e5d59c0d4944e2dd))
* **auth:** passwordReset and invite must not imply password sign-in ([3e3582f](https://github.com/jhbruhn/federfall/commit/3e3582f9fb1415d5f1d2b635feafd4ca022d1b97))
* **security:** CSP default missed OpenFreeMap after the vector-tile switch ([83dd28d](https://github.com/jhbruhn/federfall/commit/83dd28dab6a89a64e39d36c52dd8ae4e80493efa))
* **web:** service worker never intercepts requests, kills a Firefox SSE bug ([98d1a2c](https://github.com/jhbruhn/federfall/commit/98d1a2ce64929e1e1a933e5cf19f62ab984b08cc))

## [0.1.1](https://github.com/jhbruhn/federfall/compare/v0.1.0...v0.1.1) (2026-07-03)


### Performance Improvements

* **ci:** build docker image natively per-arch instead of QEMU emulation ([5104c02](https://github.com/jhbruhn/federfall/commit/5104c025790683a2426415fb9aeac9abcbe83808))

## 0.1.0 (2026-07-03)


### Features

* adaptive/two-pane layouts for web & large screens (federfall-zbe) ([bf8ea0f](https://github.com/jhbruhn/federfall/commit/bf8ea0f83cb027cb6c69f021dc6dced3e09dfab5))
* **app:** surface record-outcome on the case actions card (federfall-m1z) ([bdc8511](https://github.com/jhbruhn/federfall/commit/bdc8511080bc00b81d589b92784f15bfea111fad))
* **auth:** brand-first login header (app name + tagline) ([9c172da](https://github.com/jhbruhn/federfall/commit/9c172da67408fcca9f30fc59ed3d5c96289802d2))
* **backend:** cache geocoding lookups (geocode_cache) ([d6f9c80](https://github.com/jhbruhn/federfall/commit/d6f9c80dcbb5740b42e98235857d297d28ca501a))
* **backend:** trustedProxy env so rate limits see real client IPs ([34a624a](https://github.com/jhbruhn/federfall/commit/34a624aec91de86c3ba126e219abb9f388cb6700))
* bootstrap the first Supervisor from env (federfall-7zx) ([28afd8a](https://github.com/jhbruhn/federfall/commit/28afd8acf4dbbf127aba7889323904be05ae01ea))
* cache protected images by token-stripped key (federfall-xu3) ([b356956](https://github.com/jhbruhn/federfall/commit/b3569561b65ff572d34fa71df0fb558e193fb481))
* cap readable content width on wide screens (federfall-zbe) ([36dc96d](https://github.com/jhbruhn/federfall/commit/36dc96d1200fce6882eefe26ddf01f869da561db))
* **cases:** autocomplete the intake species from recorded kinds ([9b25357](https://github.com/jhbruhn/federfall/commit/9b25357a8f052fd9056d7acf28521788b22d33fc))
* **cases:** configurable quarantine duration + inline end-quarantine (federfall-uvm) ([7544538](https://github.com/jhbruhn/federfall/commit/7544538828d917d96f2d94aa168c0056349dcd55))
* **cases:** guard intake against discard + open the created case (federfall-2r0, federfall-y8c) ([364dd95](https://github.com/jhbruhn/federfall/commit/364dd9501a06aafa0b017bc1c65ab5302511f104))
* **cases:** make admission reasons a runtime-editable code list ([af97438](https://github.com/jhbruhn/federfall/commit/af974389e69e2d89957269947f16ae3cb629f359))
* **cases:** promote quarantine to a case-timeline record (federfall-uvm) ([3f4b0aa](https://github.com/jhbruhn/federfall/commit/3f4b0aaf94fc47d985e37a0615af05097232df76))
* **cases:** render quarantine start and end as separate timeline entries ([dd0b25e](https://github.com/jhbruhn/federfall/commit/dd0b25e66c38899bd71ed75dbe7a56262814ae10))
* **ci:** release-please pipeline with Docker + signed Android APK publishing ([2fcf088](https://github.com/jhbruhn/federfall/commit/2fcf088a3d441833dd171d14fc1cb324cf31b5bb))
* configure OAuth2 providers from env, not just the Admin UI (federfall-uvf) ([7d831c3](https://github.com/jhbruhn/federfall/commit/7d831c3cb4e95191a233107abb6ae35754de9d07))
* constrain modal sheets on wide screens (federfall-zbe) ([6c8a4ba](https://github.com/jhbruhn/federfall/commit/6c8a4ba763fd7c6fd4cafa287b186f2b211c6406))
* **dashboard:** jump to Cases tab from KPIs + lead with Today ([3606264](https://github.com/jhbruhn/federfall/commit/360626420b53cb17ffa98c1bb86e12bba4683fcd))
* disable (not hide) disposed outcome; inline log-dose (xc8.2, xc8.5) ([83535ed](https://github.com/jhbruhn/federfall/commit/83535ed2eda19771fa44aa309e9e41ecabe063e0))
* env-driven SMTP + Federfall app name (federfall-353) ([6ac684d](https://github.com/jhbruhn/federfall/commit/6ac684d2d031d3ee14c715050244b9576b7fbbd9))
* finder PII retention — anonymise after the retention window (federfall-69p) ([c869ac7](https://github.com/jhbruhn/federfall/commit/c869ac73321aafa9dcb83b6370b46618cf337406))
* gate case write UI behind permissions + read-only badge (federfall-n5q) ([0e05a5d](https://github.com/jhbruhn/federfall/commit/0e05a5d38ee2cce4f1235837f655ade79bb8d3b3))
* grouped add-entry sheet + History FAB (federfall-xc8.1) ([0a7f4ad](https://github.com/jhbruhn/federfall/commit/0a7f4ad6fe98222ded2f74b54c6a20e39bbfed07))
* **intake:** idempotency key makes retrying a timed-out intake safe ([a895685](https://github.com/jhbruhn/federfall/commit/a895685bccdfdc77f8b7d8f90482e0f3f3247545))
* make exam timeline entries readable (federfall-533) ([fa074b1](https://github.com/jhbruhn/federfall/commit/fa074b1f188a2c716ba7dd7e89045480b7136c21))
* **maps:** default to OpenFreeMap vector tiles, keep raster as an option ([87781bd](https://github.com/jhbruhn/federfall/commit/87781bda7b944e9ffd1f992120649e607bf58004))
* **markings:** make marking types a runtime-editable code list ([a53320d](https://github.com/jhbruhn/federfall/commit/a53320d268bab379bd343c58648fda4fd2dcf90c))
* **medications:** make medication routes a runtime-editable code list ([4c51c0f](https://github.com/jhbruhn/federfall/commit/4c51c0f4a1c17c3d8d133cdb28520d6d88913ee7))
* OAuth2 self-registration — guest role, group mapping, OAuth2-only (federfall-49l.3) ([3c195ae](https://github.com/jhbruhn/federfall/commit/3c195ae5faab1d609886d48f1d51ef5a09306ff4))
* OAuth2 sign-in UI + guest awaiting-access screen (federfall-pj3) ([1032c70](https://github.com/jhbruhn/federfall/commit/1032c702c2ad21c8e2891d95d14d3eaff9236ca5))
* optional per-user MFA (email OTP) + enable OAuth2 (federfall-uvf) ([05cbd72](https://github.com/jhbruhn/federfall/commit/05cbd72465ef8004e2659f001caf4b4ef33fb207))
* password-reset email links to the app + env-driven appURL (federfall-353) ([df350dd](https://github.com/jhbruhn/federfall/commit/df350dd4dc17993d9ce35518c0ce9f16232420fb))
* protect clinical/finder image fields with file tokens (federfall-49l.1) ([8e9858f](https://github.com/jhbruhn/federfall/commit/8e9858f1df426709bf3ade8c4e17d0c9ac76607a))
* **reminders:** local medication-due notifications (federfall-3uz) ([819f3c2](https://github.com/jhbruhn/federfall/commit/819f3c267bd6051a7777628fed0a2789b1e11439))
* **routing:** restore last-visited route on cold start (federfall-7ev8) ([dab251d](https://github.com/jhbruhn/federfall/commit/dab251d4c50975ab1e88c2adabf9290347cb4c74))
* **security:** Content-Security-Policy for the SPA + sandboxed file serving ([b3c941d](https://github.com/jhbruhn/federfall/commit/b3c941ddcab02c6ee23b48245e0c29ebfe5cc0a6))
* show active carer on cases (federfall-127) ([6a2e0d7](https://github.com/jhbruhn/federfall/commit/6a2e0d7bf1fc21c4e5aa1cf4c75b3877ea7b98f2))
* two-column dashboard on wide screens (federfall-zbe) ([e63c641](https://github.com/jhbruhn/federfall/commit/e63c641db569f83cd6523058010ce66c7ccbb3fa))
* two-pane Today/worklist on wide screens (federfall-zbe.7) ([457bc00](https://github.com/jhbruhn/federfall/commit/457bc00eb476d3019db693d7b538bd1b28e9e674))
* **ui:** activation CTAs in empty states + hide redundant FAB ([75c7f79](https://github.com/jhbruhn/federfall/commit/75c7f79bf53175141ba377e3f5348c5d6cf77e53))
* **ui:** guard sheets against discarding unsaved input (federfall-lhz) ([2b6eb54](https://github.com/jhbruhn/federfall/commit/2b6eb5432f29d9ab365b56502840cd859b4bcf29))
* **ui:** multiline + sentence capitalization for prose text fields (federfall-pwr) ([5f671a5](https://github.com/jhbruhn/federfall/commit/5f671a5ace06aa9516765079478859f8fc9fc123))
* **ui:** tailor dashboard theme — hero KPIs, icon chips, filled cards ([d8d921b](https://github.com/jhbruhn/federfall/commit/d8d921b52d5b61662098dcceba681f63ff2b51f2))
* verify a genuine Federfall server + server-informed login (federfall-7nf.1) ([b0fce8f](https://github.com/jhbruhn/federfall/commit/b0fce8fe0dead9272a262fc4d2f455039a4aa315))


### Bug Fixes

* **animals:** full-screen photo viewer for the animal avatar (federfall-o9ge) ([5541ec7](https://github.com/jhbruhn/federfall/commit/5541ec718079694f0b4ba2c091d36670fcf520e1))
* **app:** a11y + correctness bundle from 2026-07-02 review ([f716ac3](https://github.com/jhbruhn/federfall/commit/f716ac3ff1e43d9cdea594fddf4d9c1d5e7f04f0))
* **app:** auth/core P1 bundle (federfall-945k, c9sm, l4zs) ([37e9464](https://github.com/jhbruhn/federfall/commit/37e9464c6f5f4a6035ded14e120230879f92add7))
* **app:** block removing a member who still carries open cases (federfall-xxi) ([502a6e1](https://github.com/jhbruhn/federfall/commit/502a6e1094e7ffda7613095b08e6f0434b83f7a6))
* **app:** breakpoint state handoff, clock-only worklist tick (P2) + P3 bundle ([3d31bf4](https://github.com/jhbruhn/federfall/commit/3d31bf4da22a014faad65ca9b818e2bfa28edd5b))
* **app:** cases search matches ring/chip codes; share sheet access edit + revoke confirm (federfall-78b, uaf) ([b959e38](https://github.com/jhbruhn/federfall/commit/b959e388e39f3ec8719e668ecf68ecaffb04f2eb))
* **app:** date cross-validation + password min-length (federfall-6sp, twe) ([e232b0a](https://github.com/jhbruhn/federfall/commit/e232b0a37a22f8f02ee96f750c11d4ca9e365c06))
* **app:** give the prescription start a time of day (federfall-oaj) ([7a7a0ac](https://github.com/jhbruhn/federfall/commit/7a7a0ac39ae6bfe7a42e39a4edeaf32b53d9b7d5))
* **app:** hide weight delete unless author or supervisor (federfall-tha) ([91f6cf3](https://github.com/jhbruhn/federfall/commit/91f6cf316d430d0841d25197f234a7df06843dd4))
* **app:** let the MFA/OTP login step go back and resend the code (federfall-8r9) ([8c382da](https://github.com/jhbruhn/federfall/commit/8c382da578c6605d636f26defc8767b6877752c5))
* **app:** small UX bundle (federfall-3cq, dai, u8l, kml, 7zf) ([ff7d856](https://github.com/jhbruhn/federfall/commit/ff7d856cbdac770551c2665ba85cdcfcec8e06ed))
* atomic exam save + server-side member-removal guards (P1 bundle) ([868b44b](https://github.com/jhbruhn/federfall/commit/868b44b6d43d0cddad28a64ae0855d2873e0c172))
* **auth:** purge protected photo cache on sign-out and server switch (federfall-4o4) ([fcdd385](https://github.com/jhbruhn/federfall/commit/fcdd385d0c78b0f311e2b5f2a370d76faca39c0e))
* **backend:** close the security/logic review bundle ([46f1fd0](https://github.com/jhbruhn/federfall/commit/46f1fd043986f4ca555ecd88e3b6e17b1bee7a4e))
* **backend:** make access-boundary relations immutable after create (federfall-621) ([ec2276e](https://github.com/jhbruhn/federfall/commit/ec2276e0b4a05185719a34c5c105e1b14a5ed388))
* **backend:** make case intake and handoff atomic server-side transactions ([a30d204](https://github.com/jhbruhn/federfall/commit/a30d2041859a67d832975cb7778a92b606d75ca2))
* **backend:** numeric case-number sequencing + guest wall on late collections ([98ad73d](https://github.com/jhbruhn/federfall/commit/98ad73d3fe204df92e9d6531f8791eee6c22c45c))
* **backend:** scope the case_number unique index to the org ([7f6019f](https://github.com/jhbruhn/federfall/commit/7f6019f0835bced4f83ded5af0738623b3d5e618))
* case/animal detail URLs not updating in the address bar ([4329c36](https://github.com/jhbruhn/federfall/commit/4329c366b53c89457f6756ef820f483efebf7298))
* **cases:** live-update quarantine records on case detail (federfall-yej) ([b768788](https://github.com/jhbruhn/federfall/commit/b7687885cfaf0c8083931c0d7f61c3d279db1711))
* **ci:** drop the release-please PAT, use default GITHUB_TOKEN ([f4d22be](https://github.com/jhbruhn/federfall/commit/f4d22bed91918338b402b305463ced187e3225a0))
* **ci:** job-level if: can't reference secrets; simplify android gate ([9ce125c](https://github.com/jhbruhn/federfall/commit/9ce125c6d8fde3d0fe61997c4308d22f7d8ba58e))
* **ci:** release-please uses a PAT, not the default token ([012e8ec](https://github.com/jhbruhn/federfall/commit/012e8ec50bbb6f5bd55276a06e0f2697624a56f2))
* **data:** exclude guests from activeMembers picker source (federfall-2ry) ([551bcc0](https://github.com/jhbruhn/federfall/commit/551bcc06d117571f50ae517d3da8d7a5b239ca21))
* **data:** timeouts, safe parsing and partial-update semantics (P2 bundle) ([37db2ff](https://github.com/jhbruhn/federfall/commit/37db2ffe79440c6c24c0d38015140f93084442b8))
* disposition integrity + async-gap guards + data-layer hardening (P1 bundle) ([3bb83e6](https://github.com/jhbruhn/federfall/commit/3bb83e6e9212bc439773d603293b293cddc17dd5))
* don't stack the timeline loading bar over pull-to-refresh ([9a6f66f](https://github.com/jhbruhn/federfall/commit/9a6f66f9ba2191b6fee18636c4ed6dfa329ce812))
* guard against Ref-after-dispose in async providers (federfall-bzg) ([217a896](https://github.com/jhbruhn/federfall/commit/217a8961b888d32cb0888076e6fce4625f0aa8e7))
* **images:** actually generate 200x200 thumbs; never distort the decode ([dba7ee3](https://github.com/jhbruhn/federfall/commit/dba7ee3fb279f24c405fab95d455f7008ddea0d9))
* keep intake milestones above a same-instant weight ([8377c60](https://github.com/jhbruhn/federfall/commit/8377c602b0283c0f268d1ce1cb6b240e0b1f28a1))
* live-update prior-cases card + animal history on share (federfall-53h) ([f3d9756](https://github.com/jhbruhn/federfall/commit/f3d97562217e9d8d3e028279e80111dda16a40e2))
* live-update shared cases for the recipient (federfall-53h) ([59e5579](https://github.com/jhbruhn/federfall/commit/59e55795ef3fa1ba2331eb970a397109fa7536bb))
* make member emails visible in the team roster (emailVisibility) ([e91d00c](https://github.com/jhbruhn/federfall/commit/e91d00c0f6c41e61cebded9122194f1cc328eb88))
* make OAuth2 self-registration actually create the account (federfall-49l.3) ([febb4c2](https://github.com/jhbruhn/federfall/commit/febb4c239eb187378c5b7c51266aeea638ff9d72))
* make timeline entries visually consistent (federfall-533) ([5bbdf36](https://github.com/jhbruhn/federfall/commit/5bbdf3612c7b31c90522f6f337a67cd36f798c71))
* **map:** show OSM attribution on the case-detail map + make it a link ([6fc22f4](https://github.com/jhbruhn/federfall/commit/6fc22f4787aa1511bc16f5f906d6a885d2f5e859))
* mark OAuth2 users verified so they aren't shown "invite pending" ([efa9721](https://github.com/jhbruhn/federfall/commit/efa9721c1e618d12b12f096823be9df8c18e87c7))
* **models:** PB zero-value exam vitals map to null, not 0 ([d11941d](https://github.com/jhbruhn/federfall/commit/d11941d75e5c880312cdafe77560ac657bfd239d))
* order a same-instant record above the genesis milestone ([e6d8675](https://github.com/jhbruhn/federfall/commit/e6d867586cf3aaf433fde7c0113a99858be7eba8))
* **release:** start at 0.1.0, not 1.0.0 ([3be274d](https://github.com/jhbruhn/federfall/commit/3be274d12eca28ed4f234b030f00b49178cbc6d2))
* **reminders:** drop exact alarms — single permission prompt on Android ([6276a4f](https://github.com/jhbruhn/federfall/commit/6276a4fb64ef5de080c1d149b28f32d298cf6425))
* retry a just-uploaded image's first load (federfall-q4d) ([8cee861](https://github.com/jhbruhn/federfall/commit/8cee861c42403787d10c861243d9b1365aadbc29))
* **security:** add Referrer-Policy + Permissions-Policy to SPA responses ([813f45b](https://github.com/jhbruhn/federfall/commit/813f45b3694b73351842437ba0ceb83025680ee0))
* **security:** allow blob: in connect-src — web image upload was blocked ([76ca4ad](https://github.com/jhbruhn/federfall/commit/76ca4ad6ea4d5d091fa6aae6d2daf5de6737a846))
* **security:** anchor finder PII retention on server created date, not disposed_at ([0b34ceb](https://github.com/jhbruhn/federfall/commit/0b34ceb3e1b5c47d323916deaa5f4befca5074ec))
* **security:** close 3 OWASP findings — cross-org user move, Android backup, PB checksum ([0a06ce3](https://github.com/jhbruhn/federfall/commit/0a06ce3c8119076715fff9eac270756a6dcabb8d))
* **security:** CSV injection guard, upload MIME allowlist, invite partial-failure signal, splash timeout (P2 bundle) ([c96a4f0](https://github.com/jhbruhn/federfall/commit/c96a4f067f60e7b96e83c00d34f1bfbf608cfe77))
* **security:** reject explicit http:// server URLs in setup, except localhost ([56a39f4](https://github.com/jhbruhn/federfall/commit/56a39f4a242db46c27a2554ae001e352f5350e49))
* **security:** scrub tokens/PII from AppLogger before any crash-reporting hook ([f4cdec6](https://github.com/jhbruhn/federfall/commit/f4cdec6600e722901e32cad2bd7e29a881c2e8ec))
* **security:** validate placement handoffs, gate geocode from guests, harden OAuth2 bootstrap ([0cfe676](https://github.com/jhbruhn/federfall/commit/0cfe676ffeb9a92596dda7002351481176985274))
* stop spurious offline banner on resume (federfall-vcm) ([cd648fa](https://github.com/jhbruhn/federfall/commit/cd648fa40296e0878d7c61ad6edd8cb155fadf70))
* **tests:** clear root-owned pb_data files before host cleanup (federfall-f6f) ([987e24c](https://github.com/jhbruhn/federfall/commit/987e24cbcc0b221805fb1526b581265077f00788))
* **ui:** P2 correctness bundle from 2026-07-02 review ([8835434](https://github.com/jhbruhn/federfall/commit/8835434b93183f4828f4cd8b6cfc894657eacf6c))
* **ui:** proper text-area styling for multiline fields ([6658bac](https://github.com/jhbruhn/federfall/commit/6658bacc44a322c5b96e259fda9baecc66b32b1a))
* untrack pb_data/, correct .gitignore inline-comment bug ([0293cfa](https://github.com/jhbruhn/federfall/commit/0293cfa600745bedf4fbc69d600224f13c4d7aa0))
* **ux:** surface errors from one-tap quick actions (federfall-2ct) ([ef4186a](https://github.com/jhbruhn/federfall/commit/ef4186af4536fabc2face371c3facf0bc792595d))
* **web:** register a real service worker so Firefox Android offers PWA install ([42df4f7](https://github.com/jhbruhn/federfall/commit/42df4f722e21be821bd409ab46fb8274b0efd3c8))
* **worklist:** guard ref.invalidate against a disposed WorklistTile after logging a dose ([f6cb148](https://github.com/jhbruhn/federfall/commit/f6cb148453212bc976ec33c5db9f6641b5bb4b5e))
* **worklist:** show ending quarantine only on its day, never as overdue ([c654543](https://github.com/jhbruhn/federfall/commit/c65454314076cf09a3bda78d138a2c3a1785ef01))


### Performance Improvements

* **cases:** lazy timeline, cached photo thumbs, parallel reid search (P2 bundle) ([7455bd6](https://github.com/jhbruhn/federfall/commit/7455bd64b70c4598b65f087636930d1224fb3e66))
* **cases:** one expanded fetch replaces ~17 requests on case open (federfall-kh0u) ([4b21d8e](https://github.com/jhbruhn/federfall/commit/4b21d8ea39b2d7c02797c63ff78e2d503ab4f5e4))
* **images:** render cached protected files instantly ([2019217](https://github.com/jhbruhn/federfall/commit/2019217b27cb842031b605f9b726bde54f663bb0))
