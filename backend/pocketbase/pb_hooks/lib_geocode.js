/// <reference path="../pb_data/types.d.ts" />

// Moved to zugvogel as zv_geocode.js, which takes the env-variable PREFIX as a
// parameter so both apps can share it — federfall reads FEDERFALL_NOMINATIM_URL,
// eiermann reads EIERMANN_NOMINATIM_URL. Binding the prefix here keeps every
// call site unchanged.
//
// Usage is unchanged:
//
//   const geo = require(`${__hooks}/lib_geocode.js`);
//   const { base, key, ua } = geo.upstream();

const bound = () => require(`${__hooks}/zv_geocode.js`).withEnv("FEDERFALL");

module.exports = {
  upstream: (...args) => bound().upstream(...args),
  cacheGet: (...args) => bound().cacheGet(...args),
  cachePut: (...args) => bound().cachePut(...args),
  toResult: (...args) => require(`${__hooks}/zv_geocode.js`).toResult(...args),
};
