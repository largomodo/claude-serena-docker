# java-angular notes

Condensed from README.md Usage > 3. Launch (java-angular caveats note) and
Persistence (npm cache); edit both.

Dev server: `ng serve --host 0.0.0.0`, published ports 4200/8080/5005. For
a backend proxy, use a `proxy.conf.json` mapping `/api` to
`http://localhost:8080` via `ng serve --proxy-config proxy.conf.json`, a
single origin with no CORS needed in dev.

Unit tests run under Vitest + jsdom -- no browser is baked in. If a
scaffold produces Karma, migrate to the Vitest builder rather than
installing Chrome. Scaffold another Angular major with
`npx @angular/cli@<major>`.

`/opt/node` is root-owned: the only correct global install path is
`sudo /opt/node/bin/npm install -g <pkg>`. Run `which node` to confirm
resolution against /opt/node -- `/usr/bin/node` (apt Node) stays installed
but unreferenced.

`~/.npm` is persisted, so `npm ci` is fast and network-independent after
the first run. Serena's polyglot project lists `[java, angular]` and warns
at init if Angular source is present without `node_modules`.

This file is prose only: check-tools.sh verifies the sheet's `## Tools` and `## Environment` tables, never the content here.
