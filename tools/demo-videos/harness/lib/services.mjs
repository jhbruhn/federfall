// Two stand-ins the runner serves for the length of a run, on the loopback it
// shares with the backend (compose `network_mode: service:backend`):
//
//   :8091  a fixed-answer Nominatim. The backend's geocode proxy is pointed at
//          it (FEDERFALL_NOMINATIM_URL), so the map search always finds the
//          same place and no public geocoder is ever asked.
//   :8092  the map tiles. The backend prescribes this URL through /info
//          (FEDERFALL_MAP_TILE_URL — "Map source is runtime" in CLAUDE.md), and
//          its CSP derives the origin from the same variable, so the app needs
//          no change. Tiles come from a read-through cache under
//          /work/.cache/tiles (persisted in out/.cache): a miss is fetched once
//          from FFDEMO_TILE_UPSTREAM, after which a run needs no network. With
//          FFDEMO_TILES=offline a miss is answered with a plain tile instead,
//          which is what guarantees a run cannot reach the internet at all.
import http from 'node:http';
import { mkdirSync, readFileSync, writeFileSync, existsSync, renameSync } from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';

const PLACES = {
  de: {
    lat: '53.5503', lon: '9.9930',
    display_name: 'Rathausmarkt 1, 20095 Hamburg, Deutschland',
    address: { road: 'Rathausmarkt', house_number: '1', postcode: '20095',
      city: 'Hamburg', state: 'Hamburg', country: 'Deutschland', country_code: 'de' },
  },
  en: {
    lat: '53.5503', lon: '9.9930',
    display_name: 'Rathausmarkt 1, 20095 Hamburg, Germany',
    address: { road: 'Rathausmarkt', house_number: '1', postcode: '20095',
      city: 'Hamburg', state: 'Hamburg', country: 'Germany', country_code: 'de' },
  },
};

function geocoder(getLocale) {
  return http.createServer((req, res) => {
    const place = { place_id: 1, ...PLACES[getLocale()] ?? PLACES.en };
    const body = JSON.stringify(req.url.startsWith('/search') ? [place] : place);
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(body);
  });
}

// A 256×256 tile of one colour, as a PNG, built by hand (no image library).
function plainTile() {
  const crcTable = Array.from({ length: 256 }, (_, n) => {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    return c >>> 0;
  });
  const crc = (buf) => {
    let c = 0xffffffff;
    for (const b of buf) c = crcTable[(c ^ b) & 0xff] ^ (c >>> 8);
    return (c ^ 0xffffffff) >>> 0;
  };
  const chunk = (type, data) => {
    const len = Buffer.alloc(4);
    len.writeUInt32BE(data.length);
    const td = Buffer.concat([Buffer.from(type), data]);
    const c = Buffer.alloc(4);
    c.writeUInt32BE(crc(td));
    return Buffer.concat([len, td, c]);
  };
  const size = 256;
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(size, 0);
  ihdr.writeUInt32BE(size, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 2; // RGB
  const row = Buffer.alloc(1 + size * 3);
  for (let x = 0; x < size; x++) row.set([0xf2, 0xef, 0xe9], 1 + x * 3);
  const raw = Buffer.concat(Array.from({ length: size }, () => row));
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0)),
  ]);
}

function tiles({ cacheDir, upstream, offline, log }) {
  const plain = plainTile();
  const stats = { hit: 0, fetched: 0, plain: 0 };
  const server = http.createServer(async (req, res) => {
    const headers = {
      'content-type': 'image/png',
      'access-control-allow-origin': '*',
      'cross-origin-resource-policy': 'cross-origin',
      'cache-control': 'public, max-age=86400',
    };
    const m = /^\/(\d+)\/(\d+)\/(\d+)\.png$/.exec(req.url);
    if (!m) {
      res.writeHead(404, headers);
      res.end();
      return;
    }
    const [, z, x, y] = m;
    const file = path.join(cacheDir, z, x, `${y}.png`);
    try {
      if (existsSync(file)) {
        stats.hit++;
        res.writeHead(200, headers);
        res.end(readFileSync(file));
        return;
      }
      if (offline) throw new Error('offline');
      const url = upstream.replace('{z}', z).replace('{x}', x).replace('{y}', y);
      const r = await fetch(url, { headers: { 'user-agent': 'federfall-demo-videos/1 (tile cache for recorded demo clips; https://github.com/jhbruhn/federfall)' } });
      if (!r.ok) throw new Error(`upstream ${r.status}`);
      const buf = Buffer.from(await r.arrayBuffer());
      mkdirSync(path.dirname(file), { recursive: true });
      writeFileSync(`${file}.tmp`, buf);
      renameSync(`${file}.tmp`, file);
      stats.fetched++;
      res.writeHead(200, headers);
      res.end(buf);
    } catch (e) {
      stats.plain++;
      if (!offline) log?.(`tile ${z}/${x}/${y}: ${e.message}; serving a plain tile`);
      res.writeHead(200, headers);
      res.end(plain);
    }
  });
  server.stats = stats;
  return server;
}

/** Starts both stand-ins; `setLocale` switches the geocoder's language. */
export async function startServices({ cacheDir, log }) {
  let locale = 'de';
  const geo = geocoder(() => locale);
  const tileServer = tiles({
    cacheDir: path.join(cacheDir, 'tiles'),
    upstream: process.env.FFDEMO_TILE_UPSTREAM ?? 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    offline: process.env.FFDEMO_TILES === 'offline',
    log,
  });
  await new Promise((r) => geo.listen(8091, '127.0.0.1', r));
  await new Promise((r) => tileServer.listen(8092, '127.0.0.1', r));
  return {
    setLocale: (l) => { locale = l; },
    tileStats: () => ({ ...tileServer.stats }),
    close: () => Promise.all([geo, tileServer].map((s) => new Promise((r) => s.close(r)))),
  };
}
