# Changelog

## [1.4.2](https://github.com/jhbruhn/federfall/compare/v1.4.1...v1.4.2) (2026-08-17)


### Bug Fixes

* **ui:** a weight axis that stops at zero, and a month per column ([3853517](https://github.com/jhbruhn/federfall/commit/3853517d79b511dd90eaec25e06e909d2b2d17b4))
* **ui:** axis labels that sit where they belong ([4953365](https://github.com/jhbruhn/federfall/commit/4953365e9d05d62fc6edfb61872683fb29114f4e))

## [1.4.1](https://github.com/jhbruhn/federfall/compare/v1.4.0...v1.4.1) (2026-08-17)


### Bug Fixes

* **backend:** no dose is due after the plan has ended ([e06228c](https://github.com/jhbruhn/federfall/commit/e06228c215eb3ab381b8fb688c2b4e29523434de))
* **backend:** one geocode cache, and a coordinate that survives the trip ([71a3e72](https://github.com/jhbruhn/federfall/commit/71a3e72dde29b46c16c9cb7b2a4dd2071e0615a1))
* **backend:** the guest wall reaches medication_due, and the sweep finds it itself ([66acccf](https://github.com/jhbruhn/federfall/commit/66acccf11d23fca68609d701c2a76d386b0706bb))
* **models:** an unset number is no number, not a zero ([7800c45](https://github.com/jhbruhn/federfall/commit/7800c453e61cc82e1bbadf49c3f40a85cbb899ec))


### Performance Improvements

* **data:** housed() fetches the two columns it is counted by ([1a1b630](https://github.com/jhbruhn/federfall/commit/1a1b6307735f10a819b7acf2f012b37723ddfc28))

## [1.4.0](https://github.com/jhbruhn/federfall/compare/v1.3.0...v1.4.0) (2026-08-13)


### Features

* **dashboard:** a dose round is offered where the work is first seen ([492a237](https://github.com/jhbruhn/federfall/commit/492a237b1f3958eabf757b22985a6a0ef8f298db))
* **medications:** a prescription can carry a give/pause rhythm ([798917d](https://github.com/jhbruhn/federfall/commit/798917d8646ac32c3933047b3bf62c4a543b07e0))
* **medications:** a whole dose round goes in with one tap ([d2d37fb](https://github.com/jhbruhn/federfall/commit/d2d37fb3c211bd6bda387e9f2c9d6f5cb2ca727e))
* **medications:** one course reaches a whole group in one write ([4a53136](https://github.com/jhbruhn/federfall/commit/4a531369327e3128d7439ea5b43f09be9eb1953b))
* **medications:** the catalogue carries the course length, and the cycle is drawn ([ad3e7f6](https://github.com/jhbruhn/federfall/commit/ad3e7f604c98370641119574451605ab1932ea28))
* **medications:** the cycle preview draws the whole course, not one round ([dd6424e](https://github.com/jhbruhn/federfall/commit/dd6424e1bb70c2ba8890f21a8a1a95f9032354d6))


### Bug Fixes

* **backend:** 1700000089 repairs the boundary freeze instead of refusing to boot ([aa8849f](https://github.com/jhbruhn/federfall/commit/aa8849ff8ed94930e503d21d9e7874547361c513))
* **medications:** an unset rhythm is no rhythm, not two zeroes ([c894794](https://github.com/jhbruhn/federfall/commit/c8947946a24b49fe82ce9cce41982a59a1c97cc9))

## [1.3.0](https://github.com/jhbruhn/federfall/compare/v1.2.0...v1.3.0) (2026-08-11)


### Features

* **aviaries:** the flock log belongs to the enclosure's keeper ([db201db](https://github.com/jhbruhn/federfall/commit/db201db19024a3bf0416f0b478d2f09713574b4c))
* **vaccinations:** record shots on the bird, not on the case ([7d5f7a8](https://github.com/jhbruhn/federfall/commit/7d5f7a87fc01a7fbc365e55173939c464d0d38ac))
* **vaccinations:** vaccinate a whole enclosure in one act ([384b1f5](https://github.com/jhbruhn/federfall/commit/384b1f5f82549287afd1b67ace38aa5c55f66f50))


### Bug Fixes

* **worklist:** show an ending quarantine on its end day only ([5d5f83e](https://github.com/jhbruhn/federfall/commit/5d5f83e38b4c2cad4d5edeb2bbda596a5d60bea5))

## [1.2.0](https://github.com/jhbruhn/federfall/compare/v1.1.1...v1.2.0) (2026-08-11)


### Features

* **animals:** the add-resident sheet offers the species vocabulary ([948b41f](https://github.com/jhbruhn/federfall/commit/948b41f5aa9533d6ebb88175b8d67f01751505bf))
* **animals:** the identity edit sheet offers the species vocabulary too ([e71e795](https://github.com/jhbruhn/federfall/commit/e71e7958a18873265f009d8a742f67d762a8348c))
* **aviaries:** the keeper of an enclosure may edit it ([600da36](https://github.com/jhbruhn/federfall/commit/600da363e75d263ff9898fdaa03db6491fdeba70))


### Bug Fixes

* editing an aviary or an outcome no longer 404s ([c323b50](https://github.com/jhbruhn/federfall/commit/c323b50475baea43f6f7bfb48f9d0a1590b6e110))
* **weights:** a weight taken without a case can be corrected ([08cc697](https://github.com/jhbruhn/federfall/commit/08cc697b1c4917c2f0ba9501de60dfe285e4cf3f))

## [1.1.1](https://github.com/jhbruhn/federfall/compare/v1.1.0...v1.1.1) (2026-08-11)


### Bug Fixes

* **ci:** slight trigger for release ([b9d21dc](https://github.com/jhbruhn/federfall/commit/b9d21dc9a61d45ab0ca45748c1300794a2b12359))

## [1.1.0](https://github.com/jhbruhn/federfall/compare/v1.0.0...v1.1.0) (2026-08-11)


### Features

* **sponsorships:** a read-only detail sheet for a patronage ([656b4db](https://github.com/jhbruhn/federfall/commit/656b4dbadc928ff46501dfee1faef9b0e71774cc))
* **sponsorships:** end a patronage in one tap ([12408a7](https://github.com/jhbruhn/federfall/commit/12408a77f1d1fd911ce3599afb2057a798743e36))
* **sponsorships:** one coordinator screen over every patronage ([1dc834c](https://github.com/jhbruhn/federfall/commit/1dc834c5a51576bd9b0d580766a029695c7d6174))
* **sponsorships:** Patenschaften that follow the bird ([e9424f0](https://github.com/jhbruhn/federfall/commit/e9424f0df95eac4e14c55fe2620660f57d1cd9b0))


### Bug Fixes

* **cases:** a chip group is not a field, and one chip is enough ([325f8f9](https://github.com/jhbruhn/federfall/commit/325f8f9fd4aecabf8cca2d0b432198e4eefb0cb0))
* **codelists:** a catch-all belongs at the end of the list ([5ad985b](https://github.com/jhbruhn/federfall/commit/5ad985bece742ebd7971b4317a2b03b83428915d))
* **sponsorships:** the patronage card sat flush against the cases card ([ee0609b](https://github.com/jhbruhn/federfall/commit/ee0609b931a7ce61df0bdf9f0f1370919e3a4bf7))

## [1.0.0](https://github.com/jhbruhn/federfall/compare/v0.19.0...v1.0.0) (2026-08-10)


### ⚠ BREAKING CHANGES

* recording, editing or deleting a weight, marking or egg record requires custody of the animal. An older client offers all three to any member and will draw 403s for birds the user does not hold.
* admitting an existing animal now requires holding it or nobody holding it, and a deceased animal cannot be admitted below coordinator. An older client offers the re-identification picker for any bird in the org and will draw 403s for those it may no longer take on.
* editing an animal, or adding a resident to an aviary, now requires custody of that bird. An older client still offers both to any member and will draw 403s until the matching UI gating lands (federfall-q7ks.6).
* `aviaries.keeper` is required, so a client that omits it can no longer create or save an aviary. An app older than this refuses nothing locally and sends no keeper, drawing a validation error from the server instead.

### Features

* admitting an existing bird follows custody ([7691f85](https://github.com/jhbruhn/federfall/commit/7691f85ce971ee0d547d8d9c6f6d80f70b36b567))
* every aviary has a keeper ([ffaec3d](https://github.com/jhbruhn/federfall/commit/ffaec3db160ecd48a8ef5e7898398ba9fb94e0b7))
* the app only offers what custody allows ([5e5f8fe](https://github.com/jhbruhn/federfall/commit/5e5f8fedc7f391b6f501decdb5e8619a63521486))
* weights, markings and egg records follow custody ([a568699](https://github.com/jhbruhn/federfall/commit/a568699f515aebe9c138adf968b05136a01eaf6b))
* writing about a bird requires holding it ([780aa5b](https://github.com/jhbruhn/federfall/commit/780aa5b8a35fc0bf171b42e386d60b2c23803adb))


### Bug Fixes

* **app:** the aviary tile counts residents, not the lifetime label ([f9cfade](https://github.com/jhbruhn/federfall/commit/f9cfade2059049effe683c22c2b633732ff40e85))
* **backend:** a disposition cannot have happened tomorrow ([cdd50f2](https://github.com/jhbruhn/federfall/commit/cdd50f2fb0d2db55f8fb9492042170b4f05e9afe))
* **backend:** a row may not be filed into a case its writer cannot read ([b60971a](https://github.com/jhbruhn/federfall/commit/b60971abe89d1e18d06fc67baa834611c80b9d86))
* **backend:** an open case decides a bird's lifetime state ([1fcfce9](https://github.com/jhbruhn/federfall/commit/1fcfce9e19f862c019463ef1c26b340cd83b0fe1))
* **backend:** close the two routes back into a stale carer's custody ([505dad1](https://github.com/jhbruhn/federfall/commit/505dad166fd27b21b2d7670d1f2b6cb76fab0424))
* **backend:** close the two write paths that reached around custody ([11228f1](https://github.com/jhbruhn/federfall/commit/11228f1880605f398b89ab6fce8bc4050756b78d))
* **backend:** every relation must live in the writer's own organisation ([3787006](https://github.com/jhbruhn/federfall/commit/3787006819290c89379fea0cc5e5bf64cf8e8518))
* **backend:** moving a bird needs custody of it, with no correction exemption ([1c43001](https://github.com/jhbruhn/federfall/commit/1c4300177f89a240e8182cce66c0032d67578aa5))
* **security:** lock org and the derived residency fields on the identity layer ([f5b65fe](https://github.com/jhbruhn/federfall/commit/f5b65fe04fd3c7c8723d740856bf2d43e44f5388))

## [0.19.0](https://github.com/jhbruhn/federfall/compare/v0.18.0...v0.19.0) (2026-08-09)


### Features

* crop the animal photo before uploading it ([b06a5b6](https://github.com/jhbruhn/federfall/commit/b06a5b6831511e3f90dc846e3b629d0e5d593d72))
* record a marking as already present when the bird was found ([239d1b3](https://github.com/jhbruhn/federfall/commit/239d1b389e226eaa92f6da699762dd4467a7f9b8))

## [0.18.0](https://github.com/jhbruhn/federfall/compare/v0.17.2...v0.18.0) (2026-08-09)


### Features

* manage the microscopy vocabulary from the admin hub ([515a4d9](https://github.com/jhbruhn/federfall/commit/515a4d96c254bbd48cf77faffd8ae75f125ba322))
* map microscopy records into models, repositories and the audit log ([5cb8145](https://github.com/jhbruhn/federfall/commit/5cb814533295b5d66bdd167bd4bdbaedd6593db7))
* record microscopy findings on a case (backend) ([f60d3a1](https://github.com/jhbruhn/federfall/commit/f60d3a11ac17b5f99ff00b0a478ae640f37c6133))
* record microscopy on the case timeline (sheet, tile, attachments) ([91cca51](https://github.com/jhbruhn/federfall/commit/91cca51ac2df6fd8a140fad62e15efd45b972ea7))
* require the preparation on a faecal microscopy sample ([feb9219](https://github.com/jhbruhn/federfall/commit/feb92193150239ce12d8d4b7cf17e8ab521daa81))

## [0.17.2](https://github.com/jhbruhn/federfall/compare/v0.17.1...v0.17.2) (2026-08-09)


### Bug Fixes

* **cases:** polish the intake wizard's first two steps ([15b4756](https://github.com/jhbruhn/federfall/commit/15b47562f474d8df59a39120de5e5e79591d1b6c))
* **dashboard:** count obligations, not rows, and quiet the workload card ([97b7270](https://github.com/jhbruhn/federfall/commit/97b727053fd36ad2fc9d4b1479ec0e5fb488013f))
* **statistics:** draw the conditions breakdown as bars, not a lying donut ([77dc922](https://github.com/jhbruhn/federfall/commit/77dc922a8b1aa2b0f827250044ce1c8fd06113fb))
* **statistics:** give each rate tile its own denominator ([d1a70df](https://github.com/jhbruhn/federfall/commit/d1a70dfb372e80c2cdc182f6ab70482b0e8fdd7d))
* **statistics:** name every month on the intakes axis ([9a26e7a](https://github.com/jhbruhn/federfall/commit/9a26e7addd8461f836852619fd4cdbb5643f5e7c))
* **statistics:** round the intakes axis up to a tick, not to tallest + step ([64861bc](https://github.com/jhbruhn/federfall/commit/64861bc236a348a6fee3f6428bfd1410ed21ad50))

## [0.17.1](https://github.com/jhbruhn/federfall/compare/v0.17.0...v0.17.1) (2026-08-07)


### Bug Fixes

* remove redundant sentence to trigger release ([6814ae9](https://github.com/jhbruhn/federfall/commit/6814ae92212d186d7acff1464fd40b57090bf38a))

## [0.17.0](https://github.com/jhbruhn/federfall/compare/v0.16.0...v0.17.0) (2026-08-07)


### Features

* **backend:** count views for the dashboard, so it stops reading whole collections ([6cf5928](https://github.com/jhbruhn/federfall/commit/6cf592814334bdd080d6cca412fd07688f6de750))
* **statistics:** a month is a period too, and each breakdown shows its shape ([c207b7d](https://github.com/jhbruhn/federfall/commit/c207b7d2f6f21d311bdb737ce8e5a74ae2dbf5a1))
* **statistics:** let the statistics screen use a desktop window ([e22cc71](https://github.com/jhbruhn/federfall/commit/e22cc717c4eaa007251350538af1ac1b094917b3))
* **statistics:** report intakes over time, and outcome rates ([998e923](https://github.com/jhbruhn/federfall/commit/998e923a0ae502ff0b70a78e4a4318025072960d))


### Bug Fixes

* **app:** render every date in local time, through one formatter (federfall-yok0) ([4bf3dc4](https://github.com/jhbruhn/federfall/commit/4bf3dc4fec0b42a5c787c0f8d7c6aa81765bb6d4))
* **app:** report the error that happened, not a ParallelWaitError ([9dee209](https://github.com/jhbruhn/federfall/commit/9dee209f3a8a9091cfa0dd7bd3f1d60c41c1b307))
* **app:** seed the prescription end date in local time (federfall-ao0k) ([3943115](https://github.com/jhbruhn/federfall/commit/394311524a64b5ac2f13a7b6c92694d2a20f2395))
* **app:** stop a token refresh refetching the case list and the worklist ([bca7fd0](https://github.com/jhbruhn/federfall/commit/bca7fd0d759c74a559030a07d8215038f59850d2))
* **backend:** budget the report render routes, and make the rate-limit labels actually bind (federfall-ds0d) ([f66fd66](https://github.com/jhbruhn/federfall/commit/f66fd664e04d53762795734b3c8228dc38220e4c))
* **backend:** hand the report payload to typst as a file, not as an argv element (federfall-ds0d) ([77cf588](https://github.com/jhbruhn/federfall/commit/77cf5880297bcb78d5fceeb60938c419bf98d2ba))
* **backend:** make vet_appointments case/org immutable after create (federfall-nbqy) ([a7a1b13](https://github.com/jhbruhn/federfall/commit/a7a1b13b646d8dfe0416da26000dbf79b4723529))
* **backend:** pin authorship fields to the authenticated caller (federfall-vfry) ([189b237](https://github.com/jhbruhn/federfall/commit/189b2371a064ffa5b56273de67fb735fdb10a8a1))
* **backend:** re-point a merged animal's egg records and aviary stays (federfall-0ua6) ([dd25cb0](https://github.com/jhbruhn/federfall/commit/dd25cb081d36457cbf4fd358f0c3f1ecbd34a1b9))
* **backend:** stop the geocode rate limiter from disarming PocketBase's default brakes (federfall-sjtg) ([20f5937](https://github.com/jhbruhn/federfall/commit/20f5937c26b44f7f7dd24e459b9c2410eac3ac8f))
* **backend:** stop the purge crons from spinning forever on an undeletable page (federfall-ex20) ([d0cdecc](https://github.com/jhbruhn/federfall/commit/d0cdecc75406bb1c0356ca23bb24650c58a1e328))
* **cases:** keep paging when the outcome facet empties a page (federfall-etd7) ([0f4d6ce](https://github.com/jhbruhn/federfall/commit/0f4d6ce98cf159d1a497599c127aadd0c7408462))
* **cases:** one caseload picker instead of a scope toggle beside it ([88165fc](https://github.com/jhbruhn/federfall/commit/88165fcd0873abec724678041a8d0cf7efe0d261))
* **dashboard,cases:** make each KPI equal the list it opens, and survive a missing view ([5421ba5](https://github.com/jhbruhn/federfall/commit/5421ba59af37e7c671bb98855803c555f0355227))
* **dashboard:** stop the Today card blinking out every time it reloads ([fdb946e](https://github.com/jhbruhn/federfall/commit/fdb946ef9d753b0b31c6c136dfcca136bf912ef3))
* **dashboard:** stop the workload provider wrapping its errors too ([ade743b](https://github.com/jhbruhn/federfall/commit/ade743b2e0d12963c70c4dfc1fe02098c6fdf691))
* **hooks,dashboard:** one timezone helper, and one year boundary ([58d943f](https://github.com/jhbruhn/federfall/commit/58d943fd064880c2ad4ec35311c3bdd249ef2f33))
* **hooks:** read an org's settings in one place, and decode it there ([a48e1be](https://github.com/jhbruhn/federfall/commit/a48e1beb508526366f311c01162384e9499f80d3))
* **hooks:** read the finder retention window the app actually writes ([1f588a4](https://github.com/jhbruhn/federfall/commit/1f588a43caf279cc619089aca905aca3b22231f1))
* **intake:** keep a fractional intake weight (federfall-nd2c) ([d089db3](https://github.com/jhbruhn/federfall/commit/d089db3f422935644e390c6283de6b214b328ec7))
* **intake:** set lifetime_status on a newly admitted animal ([ae3720c](https://github.com/jhbruhn/federfall/commit/ae3720c175470600e50a141851dd061cef7757e1))
* **ui,dashboard:** one size per KPI row, and a split the dashboard can afford ([b6ef2f6](https://github.com/jhbruhn/federfall/commit/b6ef2f69489f69f0dfe0ed618a450d470c1f8909))


### Performance Improvements

* **cases,animals:** filter the browser and registry on the server ([ec9bc5c](https://github.com/jhbruhn/federfall/commit/ec9bc5c156e8d25a9c6da026f9b3297d5a069b8b))
* **dashboard:** count on the server, stop pulling two collections to the device ([b3e6c5b](https://github.com/jhbruhn/federfall/commit/b3e6c5bcb70521725a714993c8b304bcd1825608))
* **worklist,statistics:** ask the server for the rows, not for the collection ([c38566a](https://github.com/jhbruhn/federfall/commit/c38566aeb786ba7b191ae86b67094349d168bf4e))

## [0.16.0](https://github.com/jhbruhn/federfall/compare/v0.15.0...v0.16.0) (2026-08-04)


### Features

* **admin:** group the management hub, and say what each entry governs ([c7521c2](https://github.com/jhbruhn/federfall/commit/c7521c204af2636fae2c7f58c84465788332c0b0))
* **audit:** add keyset paging and the audit events repository ([5f0f1c1](https://github.com/jhbruhn/federfall/commit/5f0f1c1204cff8de0647c86517cc2872f4daf4c6))
* **audit:** add lib_audit.js — the emitter and the action registry ([9e7f3ce](https://github.com/jhbruhn/federfall/commit/9e7f3ceb51361859c7dfc460cd75dcb27094e71b))
* **audit:** add the append-only audit_events collection and tamper guard ([2282431](https://github.com/jhbruhn/federfall/commit/228243180e0bad73858948cb8df6cccb6dbacdf5))
* **audit:** add the Dart model layer for audit events ([fb6d395](https://github.com/jhbruhn/federfall/commit/fb6d39575ffe3f0826a758bd189ba1c66cbf400b))
* **audit:** add the supervisor audit screen and per-case activity ([d666cd5](https://github.com/jhbruhn/federfall/commit/d666cd536e2e979d027894cb1328040c7782156d))
* **audit:** emit domain events for every collection-API write ([7406930](https://github.com/jhbruhn/federfall/commit/74069301cbcbb4c562c2cb3e9d7d16960f001fa6))
* **audit:** emit one semantic event from each custom route ([7dfee7f](https://github.com/jhbruhn/federfall/commit/7dfee7f44d19945026ca0a13025e2eab38bb08a4))
* **audit:** filter the log by period ([062ead6](https://github.com/jhbruhn/federfall/commit/062ead6614edd839eb36c79d8df9dd6c0e4aaf31))
* **audit:** label what each event was actually about ([4c35785](https://github.com/jhbruhn/federfall/commit/4c357851b9e864cbb745e43f93dab0570ba97e70))
* **audit:** let the screen ask the questions the query could already answer ([effd7cf](https://github.com/jhbruhn/federfall/commit/effd7cf4dbb6d9cc13d429934739e59a566fccd2))
* **audit:** log exports and the system paths nobody is logged in for ([4aa4d09](https://github.com/jhbruhn/federfall/commit/4aa4d0987e32256c0d3d0a100d8609594ea2bba7))
* **audit:** log logins, failed logins and access changes ([c68e689](https://github.com/jhbruhn/federfall/commit/c68e689497874f0e32f7007e82ad9f00c33751a6))
* **audit:** make the whole row reachable, not just its summary ([a4f3048](https://github.com/jhbruhn/federfall/commit/a4f3048d470d2fd6e53942f3de57fb197304eb47))
* **audit:** name the case a row belongs to ([81328f1](https://github.com/jhbruhn/federfall/commit/81328f1c0638c8e44ae43e50181d4d5474befacf))
* **audit:** name the people and places a row is about ([4d67c12](https://github.com/jhbruhn/federfall/commit/4d67c12e6e0886047e0df111f74b638c53117752))
* **audit:** purge audit rows past their retention window ([cae5d47](https://github.com/jhbruhn/federfall/commit/cae5d47b36608c4796b6cfe1274ce17c7708eaed))
* **audit:** record what a create wrote and a delete destroyed ([ddc7a77](https://github.com/jhbruhn/federfall/commit/ddc7a779450627d9a7711c56ca8b8f951d75afc9))
* **audit:** record what a disposition did, and stop reading creates as diffs ([f36b821](https://github.com/jhbruhn/federfall/commit/f36b821649730ccd7f780031a8086da263815bf1))
* **audit:** render audit events as translated, structured lines ([7af8b3d](https://github.com/jhbruhn/federfall/commit/7af8b3dc9853872ee887e3a735160a1aa249d0ac))
* **audit:** say that a password change ended every session ([8e87be4](https://github.com/jhbruhn/federfall/commit/8e87be4193d03a9f9d277305e8210c0ec6e21adb))


### Bug Fixes

* **audit:** file a finding under its case, index the login dedup, surface a failed page ([bd8eafd](https://github.com/jhbruhn/federfall/commit/bd8eafd388ae4957f1d2f3481162864b5cfc0e5a))
* **audit:** stop the diff path logging prose and bare ids ([daef2cb](https://github.com/jhbruhn/federfall/commit/daef2cbd05a6dacdf04fbc927807700915eac144))
* **auth:** purge the intake draft on sign-out and server switch ([e5f5d8d](https://github.com/jhbruhn/federfall/commit/e5f5d8de687c496070c481b1cf7c21f3f1d13eb2))
* **auth:** stop disabling PKCE for env-configured OIDC providers ([fcb7010](https://github.com/jhbruhn/federfall/commit/fcb70109be8d77edaba19ce74874ad5ea4fa3970))
* **routing:** give every admin surface a URL, and a way back ([8d66520](https://github.com/jhbruhn/federfall/commit/8d6652060b027f0fb0c6483b7b74fe434284cd67))

## [0.15.0](https://github.com/jhbruhn/federfall/compare/v0.14.1...v0.15.0) (2026-08-03)


### Features

* **reporting:** annual report as a server-rendered PDF, CSV off the same route ([b120c9a](https://github.com/jhbruhn/federfall/commit/b120c9a0312f080a04fd1fd54a627facdc69db4c))
* **reporting:** date the annual report's markings per case, drop the roster ([5c9a719](https://github.com/jhbruhn/federfall/commit/5c9a71967c31e02899e8299d5d1474db224fd648))
* **reporting:** year selector for the annual report export ([cc2b9d4](https://github.com/jhbruhn/federfall/commit/cc2b9d45e1c7efc8e20eb408cdc25661b3da75eb))


### Bug Fixes

* **l10n:** restore the arrow in the hydration help text ([299ef3e](https://github.com/jhbruhn/federfall/commit/299ef3effbab43d7b389012c1b6ee5c18bdd1773))
* **map:** step whole zoom levels on scroll-wheel zoom ([0ce6e51](https://github.com/jhbruhn/federfall/commit/0ce6e5115f096a46eaa612358c3d4290b7371038))
* **statistics:** frame the intake map via initialCameraFit so tiles load ([f070f47](https://github.com/jhbruhn/federfall/commit/f070f47b0729cf5e0503fb9d1ce8d5ba4d80a2e5))
* **web:** bundle Noto text-fallback fonts instead of fetching them from Google ([ed22ce5](https://github.com/jhbruhn/federfall/commit/ed22ce5def298f5c6aa396503b00c843129fa51f))


### Performance Improvements

* **map:** stop pre-fetching a ring of off-screen tiles ([3379676](https://github.com/jhbruhn/federfall/commit/337967679d3ef5deb11dbb3685cb40925568973c))

## [0.14.1](https://github.com/jhbruhn/federfall/compare/v0.14.0...v0.14.1) (2026-08-03)


### Bug Fixes

* **intake:** promote the first intake photo to the animal portrait ([72c3714](https://github.com/jhbruhn/federfall/commit/72c3714d8d1696385c3c165209b4a1453eebe042))
* **models:** use a null-aware element in the vet lead test ([6f17b07](https://github.com/jhbruhn/federfall/commit/6f17b07c64ce8874c0f0b26abaddf6dd57a66af4))

## [0.14.0](https://github.com/jhbruhn/federfall/compare/v0.13.1...v0.14.0) (2026-08-03)


### Features

* **cases:** add a vet appointment to the device calendar ([b5ceeab](https://github.com/jhbruhn/federfall/commit/b5ceeaba7cd39610db89e7a54d5df64e269fdd43))
* **cases:** vet appointments per case, on the Today card, with reminders ([c1b09af](https://github.com/jhbruhn/federfall/commit/c1b09af2bce188b6ba98dd807f915f1bae325556))


### Bug Fixes

* **cases:** report vet appointments and egg records ([2889c55](https://github.com/jhbruhn/federfall/commit/2889c553eca8bf2531198df08d436d13afb9e34b))

## [0.13.1](https://github.com/jhbruhn/federfall/compare/v0.13.0...v0.13.1) (2026-08-03)


### Bug Fixes

* **web:** send a cross-origin Referer so OSM stops 403ing map tiles ([af3987f](https://github.com/jhbruhn/federfall/commit/af3987f05852ef06a9dad56dcf8555baaf1f3970))

## [0.13.0](https://github.com/jhbruhn/federfall/compare/v0.12.0...v0.13.0) (2026-08-03)


### Features

* **dashboard:** add a carer workload card and a carer case filter ([737cc4c](https://github.com/jhbruhn/federfall/commit/737cc4cd78a3b2766b82a934caad0eb30a5ebabb))

## [0.12.0](https://github.com/jhbruhn/federfall/compare/v0.11.1...v0.12.0) (2026-08-03)


### Features

* **maps:** default to OSM raster tiles instead of OpenFreeMap vector ([ddda18d](https://github.com/jhbruhn/federfall/commit/ddda18df84e0224bd804c05f7a245b0d140b80ef))
* **maps:** serve the map tile source from /api/federfall/info ([908e20c](https://github.com/jhbruhn/federfall/commit/908e20c98c69610f930866a587542843fac3f85c))

## [0.11.1](https://github.com/jhbruhn/federfall/compare/v0.11.0...v0.11.1) (2026-08-02)


### Bug Fixes

* **auth:** request the groups scope so OIDC group mapping can work ([7056a73](https://github.com/jhbruhn/federfall/commit/7056a73bc6b2c6b0a261b561c08ee38ba2a15cc9))

## [0.11.0](https://github.com/jhbruhn/federfall/compare/v0.10.0...v0.11.0) (2026-08-02)


### Features

* **auth:** block sign-in when app and server majors disagree ([9839f7b](https://github.com/jhbruhn/federfall/commit/9839f7ba7f2e2eab4406b61454362e7484a08eec))
* **backend:** condition_labels view for the recorded diagnosis vocabulary ([0cea11e](https://github.com/jhbruhn/federfall/commit/0cea11eba11c8b6cbb19828d3d1f1fa4cd8fed01))
* **cases:** filter the browser by outcome and diagnosis ([1cb3291](https://github.com/jhbruhn/federfall/commit/1cb3291f2ae0ef8e1ed353aff0662a8bfbba87fc))
* **cases:** keep an interrupted intake wizard recoverable ([2128e0e](https://github.com/jhbruhn/federfall/commit/2128e0e858d62545878d76b860e24625d6d3f225))
* **cases:** keep the finder's contact details in an intake draft ([423d92d](https://github.com/jhbruhn/federfall/commit/423d92d1937c0857b46eca4b5db084df8944935c))
* **statistics:** assemble the report CSV server-side, with a busy spinner ([a811d5f](https://github.com/jhbruhn/federfall/commit/a811d5f93fa428a83a00ed526340941039813109))
* **statistics:** tap a breakdown row through to the cases it counts ([273b3e1](https://github.com/jhbruhn/federfall/commit/273b3e1c996c229afc44710678d33eed075248cf))


### Bug Fixes

* **statistics:** attribute the intake-map preview thumbnail ([ddafb5f](https://github.com/jhbruhn/federfall/commit/ddafb5fc01c5806098626916714fac8c79bfc307))

## [0.10.0](https://github.com/jhbruhn/federfall/compare/v0.9.0...v0.10.0) (2026-07-26)


### Features

* **l10n:** follow the device language instead of pinning German ([bfae403](https://github.com/jhbruhn/federfall/commit/bfae403fa7972b624a3a277c54c264b09a5de639))
* **ui:** show the offline state once, app-wide ([9beccbe](https://github.com/jhbruhn/federfall/commit/9beccbec47daff813856b82b37f544bb3c0fb2a1))


### Bug Fixes

* **cases:** make journal photo thumbnails tappable while they load ([07875c8](https://github.com/jhbruhn/federfall/commit/07875c8509adeb59f51e2239e723a5b32ca1ab63))
* **cases:** one location field on a placement, and never an aviary ([d5abb44](https://github.com/jhbruhn/federfall/commit/d5abb443ab6980d90dbc9d9678378095e921265a))
* **ios:** declare de instead of the scaffold's es, and make it the base language ([9d068e3](https://github.com/jhbruhn/federfall/commit/9d068e341e47dd058408fb05e900ce69bc3a2d09))
* **l10n:** address the reader informally in the read-only tooltip ([7595f01](https://github.com/jhbruhn/federfall/commit/7595f01310ddd67837ddc1906411a4f75fa284bf))
* **l10n:** name both halves of the merged placement entry ([fc8c530](https://github.com/jhbruhn/federfall/commit/fc8c5305653d1e680e55645603e166333394225f))
* **l10n:** one word for a placement, and it is "Umzug" ([8eede3a](https://github.com/jhbruhn/federfall/commit/8eede3aa537092a9002f0e7db2f39e5482e14f56))

## [0.9.0](https://github.com/jhbruhn/federfall/compare/v0.8.0...v0.9.0) (2026-07-26)


### Features

* **admin:** give the catalogue placeholders example values ([6265511](https://github.com/jhbruhn/federfall/commit/62655118101c60fa7a7654931e404e68223facf0))
* **admin:** org-managed drug catalogue behind the prescription form ([b8008cb](https://github.com/jhbruhn/federfall/commit/b8008cb42144e13098a396af56aa373fc693790e))
* **cases:** calculate doses from body weight when logging a dose ([6d037cd](https://github.com/jhbruhn/federfall/commit/6d037cdcf4bf0b11c51dfb69e57656b88d8207b1))
* **cases:** prescribe the rate so a plan follows the bird's weight ([2fd82c6](https://github.com/jhbruhn/federfall/commit/2fd82c622448e3541aa220f9a6498d0843be13f8))


### Bug Fixes

* **admin:** code-list deletes state the damage and offer deactivating ([e330249](https://github.com/jhbruhn/federfall/commit/e330249c612c660fc6532e53ee2a1fe629cf1eae))
* **cases:** a cleared PocketBase number is 0, not null — and log a planned dose in one tap ([c503757](https://github.com/jhbruhn/federfall/commit/c503757d3870f26177c0e3fa4c9106027624f411))
* **cases:** one dose number in a prescription, read per kg or flat ([576712a](https://github.com/jhbruhn/federfall/commit/576712a9bde129f3c19bbf25b0c4eec6b08ebb5e))
* **cases:** picking a catalogue entry replaces the dosing, not just the gaps ([163da2d](https://github.com/jhbruhn/federfall/commit/163da2dc6fba3ad67b8cb6856be444f17eb6b4ca))
* **ui:** destructive confirms differ from Cancel in shape, not just colour ([237e986](https://github.com/jhbruhn/federfall/commit/237e9867471e37823753efaa23ca58e1e2513b5a))

## [0.8.0](https://github.com/jhbruhn/federfall/compare/v0.7.0...v0.8.0) (2026-07-25)


### Features

* **animals:** let supervisors delete animals and cases ([878359d](https://github.com/jhbruhn/federfall/commit/878359d1e06ecfe582dfed2927ead69f59773770))
* **backend:** add egg_records collection with org-scoped rules ([b7823d3](https://github.com/jhbruhn/federfall/commit/b7823d36d69cb166ba95982ae473f034dcf5d39b))
* **cases:** log egg-laying events on the case timeline ([4e5c170](https://github.com/jhbruhn/federfall/commit/4e5c1700959943ecde60c3838a24c7cacfbfc317))
* **cases:** re-attribute eggs and show a laying history per animal ([17b16ba](https://github.com/jhbruhn/federfall/commit/17b16ba2780904afa4a4613a320aceb6aa0f02e2))
* **models:** add EggRecord model, enums and repository ([fa14cf6](https://github.com/jhbruhn/federfall/commit/fa14cf6e51fab3d4758863de85d99a4d6d4e4751))


### Bug Fixes

* **backend:** delete finders no case references any more ([11869e7](https://github.com/jhbruhn/federfall/commit/11869e74a87cab3e4b2ad6c5a2824bcdb8b37aa3))
* **backend:** reject an animal relation from another organisation ([452776d](https://github.com/jhbruhn/federfall/commit/452776d7b641a7bedef7c1b5084c735a124221be))

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
