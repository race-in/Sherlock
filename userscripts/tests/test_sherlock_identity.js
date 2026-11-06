'use strict';
const assert = require('node:assert/strict');
const native = require('../Sherlock-Native-Tracker-Cards-v5.2.10.user.js');
const sync = require('../Sherlock-Tracker-Sync-Local-v1.3.2.user.js');

// The source directory must include all 205 primary trackers with a display code.
assert.equal(native.trackerDirectory.length, 205);
assert.equal(sync.trackerDirectory.length, 205);
assert.equal(native.trackerDirectory.filter(x => x.source === 'official').length, 173);
assert.equal(native.trackerDirectory.filter(x => x.source === 'generated').length, 32);
for (const entry of native.trackerDirectory) {
  assert.ok(entry.name, 'directory entry has a name');
  assert.ok(entry.short, `${entry.name} has a display abbreviation`);
  assert.equal(native.trackerDirectoryEntry(entry.name).short, entry.short);
  assert.equal(native.shortCodeFromName(entry.name), entry.short);
  assert.equal(sync.trackerDirectoryEntry(entry.name).short, entry.short);
  assert.equal(sync.shortNameOf(entry.name), entry.short);
}
console.log('PASS: all 205 tracker identities (173 source abbreviations + 32 marked generated codes)');

// Host aliases retain exact canonical full names and source abbreviations.
const canonicalHosts = [
  ['redacted.sh', 'Redacted', 'RED'], ['flacsfor.me', 'Redacted', 'RED'],
  ['orpheus.network', 'Orpheus', 'OPS'], ['opsfet.ch', 'Orpheus', 'OPS'],
  ['hdbits.org', 'HDBits', 'HDB'], ['landof.tv', 'BroadcasTheNet', 'BTN'],
  ['phoenixproject.app', 'Phoenix Project', 'PHX'], ['anthelion.me', 'Anthelion', 'ANT'],
  ['animebytes.tv', 'AnimeBytes', 'AB'], ['gazellegames.net', 'GazelleGames', 'GGn'],
  ['aither.cc', 'Aither', 'ATH'], ['blutopia.cc', 'Blutopia', 'BLU'],
  ['cinematik.net', 'Cinematik', 'TiK'], ['darkpeers.org', 'DarkPeers', 'DP'],
  ['homiehelpdesk.net', 'HomieHelpDesk', 'HHD'], ['itatorrents.xyz', 'ItaTorrents', 'ITT'],
  ['lst.gg', 'LST', 'LST'], ['oldtoons.world', 'OldToons', 'OTW'],
  ['iptorrents.com', 'IPTorrents', 'IPT'], ['torrentleech.org', 'TorrentLeech', 'TL'],
  ['desigaane.rocks', 'DesiGaane', 'DG'], ['onlyencodes.cc', 'OnlyEncodes+', 'OE'],
  ['racing4everyone.eu', 'Racing4Everyone', 'R4E'], ['rastastugan.org', 'Rastastugan', 'RAS'],
  ['reelflix.cc', 'ReelFliX', 'RFX'], ['seedpool.org', 'Seedpool', 'SP'],
  ['upload.cx', 'upload.cx', 'ULCX'], ['yu-scene.net', 'YUSCENE', 'YUSC']
];
for (const [host, fullName, short] of canonicalHosts) {
  const a = native.registryEntry(host);
  const b = sync.trackerIdentity(host);
  // Keep each userscript's previous supported-host set. Both resolve the common
  // identity directory, while Sync Local retains its pre-existing IPT/TL/DG hosts.
  if (a) {
    assert.equal(a.name, fullName, `native full name ${host}`);
    assert.equal(a.short, short, `native short code ${host}`);
  }
  assert.equal(b.name, fullName, `sync full name ${host}`);
  assert.equal(b.shortName, short, `sync short code ${host}`);
}
assert.equal(native.registryEntry('sub.blutopia.cc').short, 'BLU');
assert.equal(sync.trackerIdentity('www.cinematik.net').shortName, 'TiK');
assert.equal(native.registryEntry('iptorrents.com'), null);
assert.equal(native.registryEntry('torrentleech.org'), null);
assert.equal(native.registryEntry('desigaane.rocks'), null);
console.log(`PASS: ${canonicalHosts.length} canonical host mappings; Native Cards host support unchanged`);

// Legacy full-name records migrate to short display labels without losing identity.
const legacyNative = { host: 'blutopia.cc', name: 'Blutopia', short_name: 'BLU', snapshots: [{ uploaded: 123 }] };
assert.equal(native.normalizeTrackerRecord(legacyNative, legacyNative.host), true);
assert.equal(legacyNative.name, 'BLU');
assert.equal(legacyNative.full_name, 'Blutopia');
assert.equal(legacyNative.short_name, 'BLU');
assert.equal(legacyNative.snapshots[0].uploaded, 123);
assert.equal(native.displayTrackerName(legacyNative), 'BLU');
assert.equal(native.isSupportedTrackerRecord({ host: 'newtracker.net', slug: 'unit3d:newtracker.net' }), true);
assert.equal(native.isSupportedTrackerRecord({ host: 'random.example', name: 'Random' }), false);
const legacySync = { host: 'cinematik.net', name: 'Cinematik', shortName: 'TiK' };
sync.normalizeTrackerRecord(legacySync, legacySync.host);
assert.equal(legacySync.name, 'TiK');
assert.equal(legacySync.fullName, 'Cinematik');
assert.equal(sync.displayTrackerName(legacySync), 'TiK');
console.log('PASS: abbreviation-first migration preserves full identity and history');

// Canonical-name lookup also accepts common brand variants and API suffixes.
assert.equal(native.trackerDirectoryEntry('OnlyEncodes').short, 'OE');
assert.equal(native.trackerDirectoryEntry('ClearJAV').short, 'CJ');
assert.equal(sync.trackerIdentityForName('PhoenixProject').shortName, 'PHX');
assert.equal(sync.trackerIdentityForName('OnlyEncodes+').name, 'OnlyEncodes+');
console.log('PASS: normalized full-name aliases');

// Generic UNIT3D detection remains strict: stats bar + a framework marker.
global.document = {
  querySelector(selector) {
    if (selector.includes('.ratio-bar') || selector.includes('#userinfo_stats')) return {};
    if (selector.includes('csrf-token')) return {};
    return null;
  },
  querySelectorAll() { return []; }
};
assert.equal(native.isUnit3DSite(), true);
assert.equal(native.shouldCaptureCurrentPage('newtracker.net'), true);
global.document = {
  querySelector(selector) {
    if (selector.includes('.ratio-bar') || selector.includes('#userinfo_stats')) return {};
    return null;
  },
  querySelectorAll() { return []; }
};
assert.equal(native.isUnit3DSite(), false);
assert.equal(native.shouldCaptureCurrentPage('random-site.example'), false);
console.log('PASS: strict generic UNIT3D detection');

// UNIT3D site metadata is canonicalized through the directory before abbreviation generation.
global.location = { href: 'https://cinematik.net/users/42/member-name', origin: 'https://cinematik.net' };
global.document = {
  querySelector(selector) {
    if (selector === 'meta[property="og:site_name"]') return { getAttribute: () => 'Cinematik' };
    if (selector.includes('apple-touch-icon') || selector.includes('rel~="icon"')) return { href: 'https://cinematik.net/favicon.ico', getAttribute: () => 'https://cinematik.net/favicon.ico' };
    return null;
  },
  querySelectorAll() { return []; }
};
const tik = native.unit3dIdentity('cinematik.net');
assert.equal(tik.name, 'Cinematik');
assert.equal(tik.short, 'TiK');
assert.equal(tik.slug, 'unit3d:cinematik.net');
global.location = { href: 'https://newtracker.net/users/42/member-name', origin: 'https://newtracker.net' };
global.document = {
  querySelector(selector) {
    if (selector === 'meta[property=\"og:site_name\"]') return { getAttribute: () => 'Newtracker' };
    return null;
  },
  querySelectorAll() { return []; }
};
const unknown = native.unit3dIdentity('newtracker.net');
assert.equal(unknown.short, 'NEWT'); // deterministic fallback from Newtracker
console.log('PASS: UNIT3D metadata -> canonical tracker abbreviation; unknown host fallback');

// Preserve previously supported stats parser behavior and UNIT3D ratio-bar extraction.
const locale = sync.parseLocaleNumber('1.234,5');
assert.equal(locale, 1234.5);
assert.equal(sync.parseBytes('1.23 TiB', false), Math.round(1.23 * 1024 ** 4));
assert.equal(sync.parseCount('12,345'), 12345);
assert.equal(sync.parseRatio('2.31').value, 2.31);

global.location = { href: 'https://newtracker.net/users/42/member-name', origin: 'https://newtracker.net', hostname: 'newtracker.net', pathname: '/users/42/member-name' };
const barElements = [
  { className: 'ratio-bar__uploaded', getAttribute: key => key === 'title' ? '1.23 TiB' : null, textContent: '' },
  { className: 'ratio-bar__downloaded', getAttribute: key => key === 'title' ? '512.5 GiB' : null, textContent: '' },
  { className: 'ratio-bar__ratio', getAttribute: key => key === 'title' ? '2.46' : null, textContent: '' },
  { className: 'ratio-bar__points', getAttribute: key => key === 'title' ? '48,213.57' : null, textContent: '' },
  { className: 'ratio-bar__seeding', getAttribute: key => key === 'title' ? '142' : null, textContent: '' },
  { className: 'ratio-bar__leeching', getAttribute: key => key === 'title' ? '1' : null, textContent: '' }
];
const fakeBar = { querySelectorAll: () => barElements };
global.document = {
  body: { innerText: '', textContent: '' },
  querySelector(selector) {
    if (selector.includes('.ratio-bar')) return fakeBar;
    if (selector.includes('csrf-token')) return {};
    if (selector === 'meta[property="og:site_name"]') return { getAttribute: () => 'New Tracker Brand' };
    if (selector.includes('apple-touch-icon') || selector.includes('rel~="icon"')) return { href: 'https://newtracker.net/favicon.ico', getAttribute: () => 'https://newtracker.net/favicon.ico' };
    return null;
  },
  querySelectorAll() { return []; }
};
const extracted = {};
native.extractUnit3dBar(extracted);
assert.equal(extracted.uploaded, Math.round(1.23 * 1024 ** 4));
assert.equal(extracted.downloaded, Math.round(512.5 * 1024 ** 3));
assert.equal(extracted.ratio, 2.46);
assert.equal(extracted.bonus_points, 48213.57);
assert.equal(extracted.seeding, 142);
assert.equal(extracted.leeching, 1);
console.log('PASS: UNIT3D upload/download/ratio/bonus/seeding/leeching extraction');

// End-to-end capture writes full canonical name separately and short code as tracker.name.
const savedValues = {};
global.GM_getValue = (key, fallback) => savedValues[key] ?? fallback;
global.GM_setValue = (key, value) => { savedValues[key] = value; };
global.GM_notification = () => {};
assert.equal(native.captureProfile(), true);
const captured = savedValues['sherlockNativeTrackerCards.v3']['newtracker.net'];
assert.equal(captured.full_name, 'New Tracker Brand');
assert.equal(captured.name, 'NTB');
assert.equal(captured.short_name, 'NTB');
assert.equal(captured.snapshots.length, 1);
assert.equal(captured.snapshots[0].uploaded, Math.round(1.23 * 1024 ** 4));
assert.equal(captured.snapshots[0].downloaded, Math.round(512.5 * 1024 ** 3));
console.log('PASS: end-to-end UNIT3D capture stores canonical name + abbreviation-first display');

console.log('ALL TESTS PASSED');