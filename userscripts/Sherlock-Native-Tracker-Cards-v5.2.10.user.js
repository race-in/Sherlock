
// ==UserScript==
// @name         Sherlock Native Tracker Cards
// @namespace    https://github.com/race-in/
// @version      5.2.10
// @description  Canonical tracker identity directory with abbreviation-first display; preserves tracker capture, stats, logos, history and dashboard integration.
// @author       Local browser userscript
// @match        *://*/*
// @run-at       document-idle
// @grant        GM_getValue
// @grant        GM_setValue
// @grant        GM_registerMenuCommand
// @grant        GM_notification
// @noframes
// ==/UserScript==

(function () {
  'use strict';

  var STORAGE_KEY = 'sherlockNativeTrackerCards.v3';
  var MAX_SNAPSHOTS = 1500;
  var DAY_MS = 86400000;
  var CARD_ATTR = 'data-sherlock-local-tracker';
  var MODAL_ID = 'sherlock-local-tracker-dialog';
  var STYLE_ID = 'sherlock-local-tracker-style';
  var captureTimer = null;
  var mutationTimer = null;
  var lastRenderSignature = '';

  var ALIASES = {
    uploaded: ['total uploaded', 'uploaded amount', 'upload amount', 'total upload', 'uploaded data', 'uploaded bytes', 'uploadedbytes', 'upload bytes', 'uploadbytes', 'uploaded', 'upload'],
    downloaded: ['total downloaded', 'downloaded amount', 'download amount', 'total download', 'downloaded data', 'downloaded bytes', 'downloadedbytes', 'download bytes', 'downloadbytes', 'downloaded', 'download'],
    ratio: ['share ratio', 'share_ratio', 'shareratio', 'ratio'],
    bonus_points: ['bonus points', 'bonus point', 'bonus credits', 'seed bonus', 'karma'],
    seeding: ['seeding', 'seeding torrents', 'seeding count', 'seed torrents'],
    leeching: ['leeching', 'leeching torrents', 'leeching count', 'leech torrents'],
    snatched: ['snatched', 'snatched torrents', 'snatches', 'completed downloads'],
    hit_and_runs: ['hit and runs', 'hit & runs', 'hit and run', 'hitrun'],
    uploads: ['uploads', 'uploaded torrents', 'torrents uploaded', 'uploaded count'],
    forum_posts: ['forum posts', 'forum post count'],
    torrent_comments: ['torrent comments', 'torrent comment count']
  };

  var BYTE_FIELDS = { uploaded: true, downloaded: true };
  var COUNT_FIELDS = {
    seeding: true, leeching: true, snatched: true, hit_and_runs: true,
    uploads: true, forum_posts: true, torrent_comments: true
  };
  var LABELS = [];

  Object.keys(ALIASES).forEach(function (field) {
    ALIASES[field].forEach(function (alias) {
      LABELS.push({ field: field, alias: alias });
    });
  });
  LABELS.sort(function (a, b) { return b.alias.length - a.alias.length; });

  function readStore() {
    try {
      var value = GM_getValue(STORAGE_KEY, {});
      return value && typeof value === 'object' ? value : {};
    } catch (e) {
      return {};
    }
  }

  function writeStore(value) {
    GM_setValue(STORAGE_KEY, value);
  }

  function normalizeHost(host) {
    return String(host || '').trim().toLowerCase().replace(/\.$/, '').replace(/^www\./, '');
  }

  function hostKey() {
    return normalizeHost(location.hostname);
  }

  var TRACKER_DIRECTORY = [
    { name: "3ChangTrai", short: "3CT", source: "official" },
    { name: "Abnormal", short: "ABN", source: "official" },
    { name: "ABTorrents", short: "ABT", source: "official" },
    { name: "Aidoru!Online", short: "AIO", source: "generated" },
    { name: "Aither", short: "ATH", source: "official" },
    { name: "AlphaRatio", short: "AR", source: "official" },
    { name: "Anime Datenbank Tracker", short: "ADBT", source: "official" },
    { name: "AnimeBytes", short: "AB", source: "official" },
    { name: "AnimeTorrents", short: "AnT", source: "official" },
    { name: "AnimeWorld", short: "AW", source: "official" },
    { name: "Anthelion", short: "ANT", source: "official" },
    { name: "AsianCinema", short: "ACM", source: "official" },
    { name: "AstraTorrent", short: "ASTR", source: "generated" },
    { name: "Audionews", short: "AN", source: "official" },
    { name: "AvistaZ", short: "AZ", source: "official" },
    { name: "BakaBT", short: "BBT", source: "official" },
    { name: "Bemaniso", short: "SOWS", source: "official" },
    { name: "BeyondHD", short: "BHD", source: "official" },
    { name: "Bibliotik", short: "BiB", source: "official" },
    { name: "BitBr", short: "BTBR", source: "official" },
    { name: "BitPorn", short: "BITP", source: "generated" },
    { name: "BitTorrentFiles", short: "BTF", source: "official" },
    { name: "Blutopia", short: "BLU", source: "official" },
    { name: "Borgzelle", short: "Borg", source: "official" },
    { name: "BrSociety", short: "BRS", source: "official" },
    { name: "BrasilTracker", short: "BT", source: "official" },
    { name: "BroadcasTheNet", short: "BTN", source: "official" },
    { name: "BrokenStones", short: "BRKs", source: "official" },
    { name: "BTSCHOOL", short: "BTS", source: "official" },
    { name: "BwTorrents", short: "BwT", source: "official" },
    { name: "C411", short: "C411", source: "generated" },
    { name: "Canal Street", short: "CAST", source: "official" },
    { name: "CapybaraBR", short: "CBR", source: "official" },
    { name: "CarPT", short: "CPT", source: "generated" },
    { name: "Cathode-Ray.Tube", short: "CRT", source: "official" },
    { name: "CGPeers", short: "CGP", source: "official" },
    { name: "Cinematik", short: "TiK", source: "official" },
    { name: "CinemaZ", short: "CZ", source: "official" },
    { name: "ClearJAV (API)", short: "CJ", source: "official" },
    { name: "Coastal Music Crew", short: "CMC", source: "official" },
    { name: "Concertos", short: "CONC", source: "generated" },
    { name: "CynicalGen", short: "CG", source: "official" },
    { name: "DanishBytes", short: "DBy", source: "official" },
    { name: "Dark-Shadow", short: "DS", source: "official" },
    { name: "DasUnerwartete", short: "DU", source: "official" },
    { name: "DarkPeers", short: "DP", source: "official" },
    { name: "DeepBassNine", short: "DB9", source: "official" },
    { name: "DesiTorrents", short: "DESI", source: "generated" },
    { name: "DICMusic", short: "DIC", source: "official" },
    { name: "DigitalCore", short: "DC", source: "official" },
    { name: "DocsPedia.world", short: "DPW", source: "generated" },
    { name: "Empornium", short: "EMP", source: "official" },
    { name: "eShareNet", short: "ESN", source: "generated" },
    { name: "ExoticaZ", short: "EZ", source: "official" },
    { name: "ExtremeBits", short: "XB", source: "official" },
    { name: "F1Carreras", short: "F1C", source: "official" },
    { name: "F1GP", short: "F1GP", source: "official" },
    { name: "Fappaizuri", short: "FAP", source: "generated" },
    { name: "FearNoPeer", short: "FNP", source: "official" },
    { name: "Femdomcult", short: "FDC", source: "official" },
    { name: "FileList", short: "FL", source: "official" },
    { name: "GazelleGames", short: "GGn", source: "official" },
    { name: "Gemini Tracker", short: "G3MINI", source: "official" },
    { name: "Generation Free", short: "GF", source: "official" },
    { name: "GreatPosterWall", short: "GPW", source: "official" },
    { name: "GGPT", short: "GGPT", source: "generated" },
    { name: "HappyFappy", short: "HF", source: "official" },
    { name: "Hawke-UNO", short: "HUNO", source: "official" },
    { name: "HD-Forever", short: "HDF", source: "official" },
    { name: "HD-Space", short: "HDS", source: "official" },
    { name: "HD-Torrents", short: "HDT", source: "official" },
    { name: "HDArea", short: "HDA", source: "official" },
    { name: "HDBits", short: "HDB", source: "official" },
    { name: "HDChina", short: "HDC", source: "official" },
    { name: "HDFans", short: "HDFans", source: "official" },
    { name: "HeBits", short: "HEB", source: "official" },
    { name: "HomieHelpDesk", short: "HHD", source: "official" },
    { name: "Hon3yHD", short: "H3HD", source: "generated" },
    { name: "House of Devil", short: "HoD", source: "official" },
    { name: "HQMusic", short: "HQM", source: "official" },
    { name: "Immortuos", short: "IMMO", source: "generated" },
    { name: "IndieTorrents", short: "IP", source: "official" },
    { name: "Infire", short: "INF", source: "official" },
    { name: "iNSANE", short: "INSA", source: "generated" },
    { name: "IPTorrents", short: "IPT", source: "official" },
    { name: "ItaTorrents", short: "ITT", source: "official" },
    { name: "JME-REUNIT3D", short: "JME", source: "official" },
    { name: "JPopsuki", short: "JPS", source: "official" },
    { name: "JPTVTS", short: "JPTV", source: "generated" },
    { name: "Karagarga", short: "KG", source: "official" },
    { name: "Keep Friends", short: "FRDS", source: "official" },
    { name: "KrayTracker", short: "KT", source: "official" },
    { name: "Le Saloon", short: "LS", source: "generated" },
    { name: "Last Digital Underground", short: "LDU", source: "official" },
    { name: "Lat-Team", short: "LT", source: "generated" },
    { name: "LearnFlakes", short: "LF", source: "official" },
    { name: "LegacyHD", short: "LHD", source: "official" },
    { name: "Libble", short: "LiB", source: "official" },
    { name: "LinkoManija", short: "LM", source: "official" },
    { name: "LST", short: "LST", source: "generated" },
    { name: "LzTr", short: "LZTR", source: "generated" },
    { name: "M-Team", short: "MTTP", source: "official" },
    { name: "MaDs Revolution", short: "MaDs", source: "official" },
    { name: "Malayabits", short: "MB", source: "official" },
    { name: "Materialize", short: "MAT", source: "official" },
    { name: "Max New Vision", short: "MNV", source: "official" },
    { name: "Milkie", short: "MILK", source: "generated" },
    { name: "MojBlink", short: "MBJ", source: "official" },
    { name: "MoreThanTV", short: "MTV", source: "official" },
    { name: "MusicVids", short: "MV", source: "official" },
    { name: "MyAnonaMouse", short: "MAM", source: "official" },
    { name: "MySpleen", short: "MS", source: "official" },
    { name: "nCore", short: "NCORE", source: "generated" },
    { name: "Nebulance", short: "NBL", source: "official" },
    { name: "New Propaganda", short: "NP", source: "official" },
    { name: "New Real World", short: "NRW", source: "official" },
    { name: "NewHeaven", short: "NH", source: "official" },
    { name: "Nostradamus", short: "NOST", source: "generated" },
    { name: "NordicQuality (API)", short: "NQ", source: "official" },
    { name: "OldToons", short: "OTW", source: "official" },
    { name: "OnlyEncodes+", short: "OE", source: "official" },
    { name: "Orpheus", short: "OPS", source: "official" },
    { name: "OurBits", short: "OB", source: "official" },
    { name: "PassThePopcorn", short: "PTP", source: "official" },
    { name: "Phoenix Project", short: "PHX", source: "official" },
    { name: "PixelCove", short: "PxC", source: "official" },
    { name: "PolishTracker", short: "PT", source: "official" },
    { name: "Pornbay", short: "PB", source: "official" },
    { name: "Portugas", short: "PTG", source: "official" },
    { name: "PrivateHD", short: "PHD", source: "official" },
    { name: "PTerClub", short: "PTer", source: "official" },
    { name: "PTFiles", short: "PTF", source: "official" },
    { name: "PTFans", short: "PTFans", source: "official" },
    { name: "punck-tracker", short: "PNT", source: "generated" },
    { name: "PuroVicio", short: "PRV", source: "official" },
    { name: "Racing4Everyone", short: "R4E", source: "official" },
    { name: "RacingForMe", short: "RFM", source: "official" },
    { name: "Rastastugan", short: "RAS", source: "official" },
    { name: "Redacted", short: "RED", source: "official" },
    { name: "Retroflix", short: "RF", source: "official" },
    { name: "ReelFliX", short: "RFX", source: "official" },
    { name: "RevolutionTT", short: "RTT", source: "official" },
    { name: "RocketHD", short: "RHD", source: "official" },
    { name: "Samaritano", short: "SAMA", source: "generated" },
    { name: "SceneHD", short: "SCEN", source: "generated" },
    { name: "SceneLinks", short: "SL", source: "official" },
    { name: "SceneTime", short: "ST", source: "official" },
    { name: "SecretCinema", short: "SC", source: "official" },
    { name: "seedpool", short: "SP", source: "official" },
    { name: "SeedFile", short: "SF", source: "official" },
    { name: "Shareisland", short: "SHR", source: "official" },
    { name: "Share Friends Project", short: "SFP", source: "official" },
    { name: "Simurg", short: "SIM", source: "official" },
    { name: "SkipTheCommercials", short: "STC", source: "official" },
    { name: "SnowPT (Skyeysnow)", short: "SSPT", source: "official" },
    { name: "SocietyGlitch", short: "SG", source: "official" },
    { name: "SpeedApp", short: "SPEE", source: "generated" },
    { name: "Spirit of Revolution", short: "SoR", source: "official" },
    { name: "SportsCult", short: "SC", source: "official" },
    { name: "SpringSunday", short: "SSD", source: "official" },
    { name: "SugoiMusic", short: "SM", source: "official" },
    { name: "SuperBits", short: "SBS", source: "official" },
    { name: "Swarmazon", short: "SMZ", source: "official" },
    { name: "Tasmanit", short: "TAS", source: "official" },
    { name: "The Falling Angels", short: "TFA", source: "official" },
    { name: "The Horror Charnel", short: "THC", source: "official" },
    { name: "The Leach Zone", short: "TLZ", source: "official" },
    { name: "The New Retro", short: "TNR", source: "official" },
    { name: "The Old School", short: "TOS", source: "official" },
    { name: "The Paradiese", short: "TP", source: "official" },
    { name: "The Shinning", short: "TSH", source: "official" },
    { name: "The-Crazy-Ones", short: "TCO", source: "official" },
    { name: "The-New-Fun", short: "TNF", source: "official" },
    { name: "TheGeeks", short: "TG", source: "official" },
    { name: "TheMixingBowl", short: "TMB", source: "official" },
    { name: "ThePlace", short: "TP", source: "official" },
    { name: "TheScenePlace", short: "TSP", source: "official" },
    { name: "TheVault", short: "TV", source: "official" },
    { name: "TNTracker", short: "TN", source: "official" },
    { name: "Torrent Explosiv", short: "TE", source: "official" },
    { name: "Torrent Sector Crew", short: "TSC", source: "official" },
    { name: "Torrent Trader", short: "TT", source: "official" },
    { name: "Torrent-Syndikat", short: "TS", source: "official" },
    { name: "TorrentBD", short: "TBD", source: "official" },
    { name: "TorrentDay", short: "TD", source: "official" },
    { name: "TorrentLand", short: "TLND", source: "generated" },
    { name: "TorrentLeech", short: "TL", source: "official" },
    { name: "Torrentleech.pl", short: "TL.pl", source: "official" },
    { name: "Torrenteros", short: "TTR", source: "official" },
    { name: "ToTheGlory", short: "TTG", source: "official" },
    { name: "TR4KER", short: "T4", source: "official" },
    { name: "TurkSeed", short: "TURK", source: "generated" },
    { name: "TV-Vault", short: "TVV", source: "official" },
    { name: "U2", short: "U2", source: "official" },
    { name: "Universal-Torrents", short: "UT", source: "official" },
    { name: "Unwalled", short: "UNW", source: "official" },
    { name: "upload.cx", short: "ULCX", source: "official" },
    { name: "Upscale Vault", short: "UV", source: "official" },
    { name: "Utopia", short: "UTOP", source: "generated" },
    { name: "V3X", short: "V3X", source: "generated" },
    { name: "World-of-Tomorrow", short: "WoT", source: "official" },
    { name: "Xbtmusic", short: "XBT", source: "official" },
    { name: "XtremeWrestlingTorrents", short: "XWT", source: "official" },
    { name: "YggReborn", short: "YGGR", source: "generated" },
    { name: "YUSCENE", short: "YUSC", source: "generated" },
  ];

  var SITE_REGISTRY = [
    { slug: 'redacted', name: 'Redacted', short: 'RED', hosts: ['redacted.sh', 'flacsfor.me'] },
    { slug: 'orpheus', name: 'Orpheus', short: 'OPS', hosts: ['orpheus.network', 'opsfet.ch'] },
    { slug: 'hdbits', name: 'HDBits', short: 'HDB', hosts: ['hdbits.org'] },
    { slug: 'broadcasthenet', name: 'BroadcasTheNet', short: 'BTN', hosts: ['broadcasthe.net', 'landof.tv', 'api.broadcasthe.net'] },
    { slug: 'phoenixproject', name: 'Phoenix Project', short: 'PHX', hosts: ['phoenixproject.app'] },
    { slug: 'anthelion', name: 'Anthelion', short: 'ANT', hosts: ['anthelion.me'] },
    { slug: 'animebytes', name: 'AnimeBytes', short: 'AB', hosts: ['animebytes.tv'] },
    { slug: 'gazellegames', name: 'GazelleGames', short: 'GGn', hosts: ['gazellegames.net'] },
    { slug: 'aither', name: 'Aither', short: 'ATH', hosts: ['aither.cc'] },
    { slug: 'blutopia', name: 'Blutopia', short: 'BLU', hosts: ['blutopia.cc'] },
    { slug: 'cinematik', name: 'Cinematik', short: 'TiK', hosts: ['cinematik.net'] },
    { slug: 'darkpeers', name: 'DarkPeers', short: 'DP', hosts: ['darkpeers.org'] },
    { slug: 'homiehelpdesk', name: 'HomieHelpDesk', short: 'HHD', hosts: ['homiehelpdesk.net'] },
    { slug: 'itatorrents', name: 'ItaTorrents', short: 'ITT', hosts: ['itatorrents.xyz'] },
    { slug: 'lst', name: 'LST', short: 'LST', hosts: ['lst.gg'] },
    { slug: 'oldtoons', name: 'OldToons', short: 'OTW', hosts: ['oldtoons.world'] },
    { slug: 'onlyencodes', name: 'OnlyEncodes+', short: 'OE', hosts: ['onlyencodes.cc'] },
    { slug: 'racing4everyone', name: 'Racing4Everyone', short: 'R4E', hosts: ['racing4everyone.eu'] },
    { slug: 'rastastugan', name: 'Rastastugan', short: 'RAS', hosts: ['rastastugan.org'] },
    { slug: 'reelflix', name: 'ReelFliX', short: 'RFX', hosts: ['reelflix.cc'] },
    { slug: 'seedpool', name: 'Seedpool', short: 'SP', hosts: ['seedpool.org'] },
    { slug: 'uploadcx', name: 'upload.cx', short: 'ULCX', hosts: ['upload.cx'] },
    { slug: 'yuscene', name: 'YUSCENE', short: 'YUSC', hosts: ['yu-scene.net'] }
  ];

  function normalizeTrackerName(value) {
    return String(value || '').toLowerCase()
      .replace(/\s*\(api\)\s*$/i, '')
      .replace(/&/g, 'and')
      .replace(/[^a-z0-9]+/g, '');
  }

  var TRACKER_DIRECTORY_INDEX = Object.create(null);
  TRACKER_DIRECTORY.forEach(function (entry) {
    TRACKER_DIRECTORY_INDEX[normalizeTrackerName(entry.name)] = entry;
  });

  function trackerDirectoryEntry(value) {
    return TRACKER_DIRECTORY_INDEX[normalizeTrackerName(value)] || null;
  }

  function shortCodeFromName(name) {
    var known = trackerDirectoryEntry(name);
    if (known) return known.short;
    var words = String(name || '').replace(/[^A-Za-z0-9]+/g, ' ').trim().split(/\s+/).filter(Boolean);
    if (!words.length) return 'TRK';
    var code = words.length > 1
      ? words.filter(function (word) { return !/^(the|of|and|a|an)$/i.test(word); }).slice(0, 5).map(function (word) { return word.charAt(0); }).join('')
      : words[0].slice(0, 4);
    return (code || 'TRK').toUpperCase().slice(0, 8);
  }

  function displayTrackerName(tracker) {
    return tracker && (tracker.short_name || tracker.name) || (tracker && tracker.host) || 'TRK';
  }

  function isDynamicUnit3DRecord(tracker) {
    return Boolean(tracker && (String(tracker.slug || '').indexOf('unit3d:') === 0 || tracker.dynamic === true));
  }

  function isSupportedTrackerRecord(tracker) {
    return Boolean(tracker && tracker.host && (registryEntry(tracker.host) || isDynamicUnit3DRecord(tracker)));
  }

  // Migrate legacy full-name records to an abbreviation-first display without
  // changing tracker identity, history, stats, logo URLs or capture timestamps.
  function normalizeTrackerRecord(tracker, host) {
    if (!tracker || typeof tracker !== 'object') return false;
    host = normalizeHost(host || tracker.host);
    var before = [tracker.name, tracker.full_name, tracker.short_name, tracker.slug].join('\u0000');
    var canonical = registryEntry(host);
    if (canonical) {
      tracker.full_name = canonical.name;
      tracker.short_name = canonical.short || shortCodeFromName(canonical.name);
      tracker.name = tracker.short_name;
      tracker.slug = canonical.slug;
    } else if (isDynamicUnit3DRecord(tracker)) {
      var originalFullName = tracker.full_name || tracker.name || fallbackNameFromHost(host);
      var directoryEntry = trackerDirectoryEntry(originalFullName) || trackerDirectoryEntry(fallbackNameFromHost(host));
      tracker.full_name = directoryEntry ? directoryEntry.name : originalFullName;
      tracker.short_name = directoryEntry ? directoryEntry.short : (tracker.short_name || shortCodeFromName(tracker.full_name));
      tracker.name = tracker.short_name;
      tracker.dynamic = true;
    } else {
      var fullName = tracker.full_name || tracker.name || fallbackNameFromHost(host);
      var directory = trackerDirectoryEntry(fullName) || trackerDirectoryEntry(fallbackNameFromHost(host));
      tracker.full_name = directory ? directory.name : fullName;
      tracker.short_name = directory ? directory.short : (tracker.short_name || shortCodeFromName(tracker.full_name));
      tracker.name = tracker.short_name;
    }
    tracker.host = host;
    return before !== [tracker.name, tracker.full_name, tracker.short_name, tracker.slug].join('\u0000');
  }


  function registryEntry(host) {
    host = normalizeHost(host);
    for (var i = 0; i < SITE_REGISTRY.length; i++) {
      var site = SITE_REGISTRY[i];
      if (site.hosts.some(function (candidate) {
        return host === candidate || host.endsWith('.' + candidate);
      })) return site;
    }
    return null;
  }

  // UNIT3D trackers share a distinctive stats bar and Laravel/UNIT3D page markers.
  // This lets newly encountered UNIT3D trackers auto-capture without weakening the
  // whitelist for unrelated websites that happen to show upload/download numbers.
  function isUnit3DSite() {
    var statsBar = document.querySelector('.ratio-bar, [class*="ratio-bar__"], #userinfo_stats');
    if (!statsBar) return false;

    var frameworkMarker = document.querySelector(
      'meta[name="csrf-token"], input[name="_token"], a.top-nav__username, #userinfo_username'
    );
    return Boolean(frameworkMarker);
  }

  function cleanSiteName(value) {
    var name = String(value || '').replace(/[\s\u00a0]+/g, ' ').trim();
    if (!name || name.length > 45) return '';
    if (/^(home|index|login|log in|sign in|welcome|torrents?|profile|account|user|member|dashboard|forums?)$/i.test(name)) return '';
    if (/\b(profile|account|dashboard|login|register|username|member area)\b/i.test(name)) return '';
    return name;
  }

  function unit3dSiteLogo() {
    var selectors = [
      'header img[class*="logo" i]', 'header img[id*="logo" i]',
      'header a[href="/"] img', '.navbar-brand img',
      '[class*="site-logo"] img', '[class*="brand-logo"] img',
      'img[alt*="logo" i]'
    ];
    for (var i = 0; i < selectors.length; i++) {
      var images = document.querySelectorAll(selectors[i]);
      for (var j = 0; j < images.length; j++) {
        var img = images[j];
        var marker = ((img.getAttribute('alt') || '') + ' ' + (img.getAttribute('class') || '') + ' ' + (img.id || '')).toLowerCase();
        if (/avatar|profile|userpic|user-pic|gravatar/.test(marker)) continue;
        var src = absoluteImageUrl(img.currentSrc || img.getAttribute('src') || img.getAttribute('data-src'));
        if (src) return src;
      }
    }

    var icon = document.querySelector('link[rel~="apple-touch-icon"], link[rel~="icon"], link[rel="shortcut icon"]');
    return icon ? (absoluteImageUrl(icon.href || icon.getAttribute('href')) || location.origin + '/favicon.ico')
      : location.origin + '/favicon.ico';
  }

  function unit3dIdentity(host) {
    var name = '';
    var metaSelectors = [
      'meta[property="og:site_name"]',
      'meta[name="application-name"]',
      'meta[name="apple-mobile-web-app-title"]'
    ];
    for (var i = 0; i < metaSelectors.length && !name; i++) {
      var meta = document.querySelector(metaSelectors[i]);
      name = cleanSiteName(meta && meta.getAttribute('content'));
    }

    var brandSelectors = [
      'a.navbar-brand', '.navbar-brand', 'header .site-name',
      'header .brand-name', 'header [data-site-name]',
      'header [class~="logo-text"]', 'header .brand'
    ];
    for (var j = 0; j < brandSelectors.length && !name; j++) {
      var brand = document.querySelector(brandSelectors[j]);
      name = cleanSiteName(brand && (brand.getAttribute('data-site-name') || brand.textContent));
    }

    // Never use document.title here: on account pages it commonly contains the member's
    // username or profile heading, which is how incorrect tracker names were introduced.
    name = name || fallbackNameFromHost(host);
    var directoryEntry = trackerDirectoryEntry(name) || trackerDirectoryEntry(fallbackNameFromHost(host));
    if (directoryEntry) name = directoryEntry.name;
    return {
      slug: 'unit3d:' + normalizeHost(host),
      name: name,
      short: directoryEntry ? directoryEntry.short : shortCodeFromName(name),
      dynamic: true,
      logo: unit3dSiteLogo()
    };
  }

  function shouldCaptureCurrentPage(host) {
    return Boolean(registryEntry(host) || isUnit3DSite());
  }

  // Optional per-tracker logo overrides. Add corrected URLs here later.
  // Example: redacted: 'https://example.com/redacted.png'
  var SITE_LOGO_OVERRIDES = {
    cinematik: 'https://cinematik.net/favicon.ico'
  };

  function defaultLogoUrl(identity) {
    if (SITE_LOGO_OVERRIDES[identity.slug]) return SITE_LOGO_OVERRIDES[identity.slug];
    return 'https://raw.githubusercontent.com/race-in/Sherlock/feature/feral-rootless-edition/sherlock-v2/app/assets/images/sites/' + identity.slug + '.png';
  }

  function resolvedLogo(tracker, identity) {
    // An explicitly configured override always wins. Otherwise preserve manual URLs.
    if (SITE_LOGO_OVERRIDES[identity.slug]) return SITE_LOGO_OVERRIDES[identity.slug];
    return isGeneratedLogo(tracker && tracker.logo) ? defaultLogoUrl(identity) : tracker.logo;
  }

  function isGeneratedLogo(url) {
    return !url || /^https:\/\/raw\.githubusercontent\.com\/race-in\/Sherlock\/feature\/feral-rootless-edition\/sherlock-v2\/app\/assets\/images\/sites\//i.test(String(url));
  }

  function fallbackNameFromHost(host) {
    host = normalizeHost(host);
    var knownSuffixes = [
      'co.uk', 'org.uk', 'ac.uk', 'com.au', 'net.au', 'org.au', 'co.nz',
      'com.br', 'com.tr', 'com.sg', 'com.tw', 'co.in', 'firm.in', 'net.in',
      'org.in', 'co.za', 'com.mx', 'com.ar', 'com.pl', 'com.ua'
    ];
    var labels = host.split('.').filter(Boolean);
    if (labels.length > 2) {
      var suffix2 = labels.slice(-2).join('.');
      var suffix3 = labels.slice(-3).join('.');
      labels = knownSuffixes.indexOf(suffix2) >= 0 ? labels.slice(-3) :
        (knownSuffixes.indexOf(suffix3) >= 0 ? labels.slice(-4) : labels.slice(-2));
    }
    var label = labels[0] || host;
    return label.replace(/[-_]+/g, ' ').replace(/\b\w/g, function (ch) {
      return ch.toUpperCase();
    });
  }

  function absoluteImageUrl(value) {
    if (!value) return '';
    try {
      var url = new URL(value, location.href);
      if (url.protocol !== 'http:' && url.protocol !== 'https:') return '';
      return url.href;
    } catch (e) {
      return '';
    }
  }

  function localTime(date) {
    date = date || new Date();
    var offset = -date.getTimezoneOffset();
    var sign = offset >= 0 ? '+' : '-';
    var abs = Math.abs(offset);
    function pad(n) { return String(n).padStart(2, '0'); }
    return date.getFullYear() + '-' + pad(date.getMonth() + 1) + '-' +
      pad(date.getDate()) + 'T' + pad(date.getHours()) + ':' +
      pad(date.getMinutes()) + ':' + pad(date.getSeconds()) + sign +
      pad(Math.floor(abs / 60)) + ':' + pad(abs % 60);
  }

  function normalize(value) {
    return String(value || '').toLowerCase()
      .replace(/[：:]/g, ' ')
      .replace(/[()[\]{}]/g, ' ')
      .replace(/[._-]/g, ' ')
      .replace(/\s+/g, ' ').trim();
  }

  function parseValue(raw, field) {
    if (raw == null) return null;
    var text = String(raw).replace(/\u00a0/g, ' ').replace(/,/g, '').trim();
    if (!text) return null;

    var match;
    if (BYTE_FIELDS[field]) {
      match = text.match(/(-?\d+(?:\.\d+)?)\s*(bytes?|b|kib|kb|mib|mb|gib|gb|tib|tb|pib|pb)?\b/i);
      if (!match) return null;
      var amount = Number(match[1]);
      if (!Number.isFinite(amount)) return null;
      var unit = (match[2] || 'b').toLowerCase();
      var powers = {
        b: 0, byte: 0, bytes: 0, kb: 1, kib: 1,
        mb: 2, mib: 2, gb: 3, gib: 3, tb: 4, tib: 4, pb: 5, pib: 5
      };
      return Math.round(amount * Math.pow(1024, powers[unit] == null ? 0 : powers[unit]));
    }

    match = text.match(/-?\d+(?:\.\d+)?/);
    if (!match) return null;
    var number = Number(match[0]);
    if (!Number.isFinite(number)) return null;
    return COUNT_FIELDS[field] ? Math.round(number) : number;
  }

  function setIfMissing(result, field, value) {
    if (result[field] == null && value != null && Number.isFinite(value)) {
      result[field] = value;
    }
  }

  // UNIT3D exposes account totals in classed ratio-bar elements. Some themes put
  // the value in title/aria-label instead of visible text, so inspect all three.
  function extractUnit3dBar(result) {
    var bar = document.querySelector('.ratio-bar, [class*="ratio-bar"]');
    if (!bar) return;

    var fields = {
      uploaded: 'uploaded', downloaded: 'downloaded', ratio: 'ratio',
      points: 'bonus_points', bonus: 'bonus_points',
      seeding: 'seeding', leeching: 'leeching'
    };

    bar.querySelectorAll('[class*="ratio-bar__"]').forEach(function (node) {
      var match = String(node.className || '').match(/ratio-bar__([a-z_-]+)/i);
      var field = match && fields[match[1].toLowerCase()];
      if (!field) return;
      var raw = node.getAttribute('title') || node.getAttribute('aria-label') || node.textContent || '';
      setIfMissing(result, field, parseValue(raw, field));
    });
  }

  function aliasForLabel(label) {
    var normalized = normalize(label);
    return LABELS.find(function (entry) {
      return normalize(entry.alias) === normalized;
    }) || null;
  }

  function extractFromDom(result) {
    var selectors = 'dt, th, .label, .stat-label, .profile-label, .key, strong, b';
    document.querySelectorAll(selectors).forEach(function (node) {
      var labelText = normalize(node.textContent);
      if (!labelText || labelText.length > 55) return;

      var entry = aliasForLabel(labelText);
      if (!entry) return;

      var valueText = node.nextElementSibling ? node.nextElementSibling.textContent : '';
      if (!valueText && node.parentElement) {
        var siblings = Array.from(node.parentElement.children);
        var index = siblings.indexOf(node);
        if (index >= 0 && siblings[index + 1]) valueText = siblings[index + 1].textContent;
        if (!valueText) valueText = node.parentElement.textContent;
      }
      if (valueText) {
        valueText = valueText.replace(node.textContent || '', '').trim();
        setIfMissing(result, entry.field, parseValue(valueText, entry.field));
      }
    });

    document.querySelectorAll('[data-stat], [data-field], [itemprop]').forEach(function (node) {
      var key = normalize(
        node.getAttribute('data-stat') ||
        node.getAttribute('data-field') ||
        node.getAttribute('itemprop')
      );
      var entry = aliasForLabel(key);
      if (entry) setIfMissing(result, entry.field, parseValue(node.textContent, entry.field));
    });
  }

  function isNonAccountTransferLine(line, field) {
    var value = String(line || '').toLowerCase();
    if (field !== 'uploaded' && field !== 'downloaded') return false;
    return /\b(?:speed|rate|limit|per\s+second|\/s|\/sec|uploading|downloading)\b/i.test(value);
  }

  function startsWithKnownLabel(line) {
    var value = String(line || '').trim();
    if (!value) return false;
    return LABELS.some(function (entry) {
      var escaped = entry.alias.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      return new RegExp('^\\s*' + escaped + '(?=$|[^a-z0-9])\\s*(?:[:：=]|$)', 'i').test(value);
    });
  }

  function extractFromText(text, result) {
    var lines = String(text || '').replace(/\u00a0/g, ' ').split(/\r?\n/);

    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim();
      if (!line) continue;

      for (var j = 0; j < LABELS.length; j++) {
        var entry = LABELS[j];
        if (result[entry.field] != null) continue;
        if (isNonAccountTransferLine(line, entry.field)) continue;
        if (entry.field === 'uploaded' && /\buploaded?\s+(?:torrents?|count)\b/i.test(line)) continue;
        if (entry.field === 'downloaded' && /\bdownloaded?\s+(?:torrents?|count)\b/i.test(line)) continue;

        var escaped = entry.alias.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
        var regex = new RegExp(
          '(?:^|[^a-z0-9])' + escaped +
          '(?=$|[^a-z0-9])\\s*(?:[:：=]\\s*)?(.*)$',
          'i'
        );
        var match = line.match(regex);
        if (!match) continue;

        var rawValue = (match[1] || '').trim();
        var parsed = parseValue(rawValue, entry.field);

        // A few trackers render the label and its value on separate lines.
        if (parsed == null && i + 1 < lines.length && !startsWithKnownLabel(lines[i + 1])) {
          if (!isNonAccountTransferLine(lines[i + 1], entry.field)) {
            parsed = parseValue(lines[i + 1], entry.field);
          }
        }
        setIfMissing(result, entry.field, parsed);
      }
    }
  }

  function flattenJson(value, result, depth) {
    depth = depth || 0;
    if (depth > 7 || value == null) return;
    if (Array.isArray(value)) {
      value.slice(0, 100).forEach(function (item) { flattenJson(item, result, depth + 1); });
      return;
    }
    if (typeof value !== 'object') return;

    Object.keys(value).forEach(function (key) {
      var entry = aliasForLabel(key);
      var val = value[key];
      if (entry && (typeof val === 'string' || typeof val === 'number')) {
        setIfMissing(result, entry.field, parseValue(val, entry.field));
      }
      if (val && typeof val === 'object') flattenJson(val, result, depth + 1);
    });
  }

  function extractStats() {
    var result = {};
    extractFromDom(result);
    extractUnit3dBar(result);
    extractFromText(document.body ? (document.body.innerText || document.body.textContent || '') : '', result);

    document.querySelectorAll(
      'script[type="application/ld+json"], script#__NEXT_DATA__, script[id*="state"], script[id*="State"]'
    ).forEach(function (script) {
      var raw = script.textContent || '';
      if (raw.length > 2000000) return;
      try { flattenJson(JSON.parse(raw), result, 0); } catch (e) {}
    });

    if (result.uploaded != null && result.downloaded != null) {
      result.buffer = result.uploaded - result.downloaded;
      if (result.ratio == null && result.downloaded > 0) {
        result.ratio = result.uploaded / result.downloaded;
      }
    }

    var hasUsefulMetric = result.uploaded != null ||
      result.downloaded != null || result.ratio != null ||
      result.bonus_points != null || result.seeding != null ||
      result.leeching != null || result.snatched != null ||
      result.hit_and_runs != null || result.uploads != null ||
      result.forum_posts != null || result.torrent_comments != null;

    if (!hasUsefulMetric) return null;

    return result;
  }

  function looksLikeProfile(stats) {
    var path = location.pathname.toLowerCase();
    var pathMatch = /(?:^|\/)(?:user|users|profile|member|account|myaccount|details|viewuser)(?:\.php)?(?:\/|$)/i.test(path);
    var queryMatch = /(?:^|[?&])(?:id|userid|user_id)=\d+/i.test(location.search) &&
      /user|member|profile/i.test(path);
    var headingMatch = Array.from(document.querySelectorAll('h1, h2, .page-title, .profile-title'))
      .some(function (node) {
        var heading = (node.textContent || '').trim();
        return /^(?:my\s+)?(?:user\s+)?profile(?:\s+details)?$|^account\s+statistics$/i.test(heading);
      });
    var hasStats = Boolean(stats && Object.keys(stats).some(function (key) {
      return stats[key] != null;
    }));
    return pathMatch || queryMatch || (headingMatch && hasStats);
  }

  function fingerprint(stats) {
    var sorted = {};
    Object.keys(stats).sort().forEach(function (key) { sorted[key] = stats[key]; });
    return JSON.stringify(sorted);
  }

  function captureProfile() {
    var host = hostKey();

    // Known trackers always use their canonical identity. An unknown site is accepted
    // only when it carries the UNIT3D signature; unrelated sites remain ignored.
    var identity = registryEntry(host);
    if (!identity) {
      if (!isUnit3DSite()) return false;
      identity = unit3dIdentity(host);
    }

    var stats = extractStats();
    if (!looksLikeProfile(stats)) return false;

    var store = readStore();
    var tracker = store[host] || {
      host: host,
      name: identity.name,
      logo: identity.dynamic ? identity.logo : '',
      slug: identity.slug,
      short_name: identity.short,
      first_seen: localTime(),
      snapshots: []
    };

    // Canonical tracker identity always wins.
    tracker.full_name = identity.name;
    tracker.short_name = identity.short || shortCodeFromName(identity.name);
    tracker.name = tracker.short_name;
    tracker.slug = identity.slug;
    tracker.dynamic = Boolean(identity.dynamic);

    // Known trackers use Sherlock's bundled logo (or an explicit override). New
    // UNIT3D trackers use the tracker's own site logo/favicon and keep manual logos.
    if (identity.dynamic) {
      if (isGeneratedLogo(tracker.logo) || !tracker.logo) tracker.logo = identity.logo || location.origin + '/favicon.ico';
    } else {
      tracker.logo = resolvedLogo(tracker, identity);
    }

    var rows = Array.isArray(tracker.snapshots) ? tracker.snapshots : [];

    if (!stats) {
      tracker.snapshots = rows;
      tracker.last_seen = localTime();
      store[host] = tracker;
      writeStore(store);
      lastRenderSignature = '';
      return true;
    }

    var previous = rows.length ? rows[rows.length - 1] : null;
    var fp = fingerprint(stats);

    if (previous && previous.fingerprint === fp &&
        Date.now() - (previous.captured_ms || 0) < DAY_MS) {
      tracker.last_seen = localTime();
      store[host] = tracker;
      writeStore(store);
      return false;
    }

    var snapshot = Object.assign({
      time: localTime(),
      captured_ms: Date.now(),
      fingerprint: fp
    }, stats);

    rows.push(snapshot);
    if (rows.length > MAX_SNAPSHOTS) rows = rows.slice(-MAX_SNAPSHOTS);

    tracker.snapshots = rows;
    tracker.last_seen = snapshot.time;
    store[host] = tracker;
    writeStore(store);

    try {
      GM_notification({
        title: 'Sherlock',
        text: tracker.name + ' profile captured',
        timeout: 1800
      });
    } catch (e) {}

    lastRenderSignature = '';
    return true;
  }

  function latest(tracker) {
    var rows = tracker.snapshots || [];
    return rows.length ? rows[rows.length - 1] : {};
  }

  function baseline24h(tracker) {
    var cutoff = Date.now() - DAY_MS;
    var baseline = null;

    (tracker.snapshots || []).forEach(function (row) {
      if (row.captured_ms <= cutoff) baseline = row;
    });

    return baseline;
  }

  function delta24h(tracker, field) {
    var current = latest(tracker);
    var baseline = baseline24h(tracker);

    if (!baseline || current[field] == null || baseline[field] == null) {
      return null;
    }
    return current[field] - baseline[field];
  }

  function formatBytes(value) {
    if (value == null || !Number.isFinite(value)) return '—';
    if (value === 0) return '0 B';

    var units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
    var index = Math.min(
      Math.floor(Math.log(Math.abs(value)) / Math.log(1024)),
      units.length - 1
    );

    return (value / Math.pow(1024, index)).toFixed(index === 0 ? 0 : 2) +
      ' ' + units[index];
  }

  function formatNumber(value, digits) {
    if (value == null || !Number.isFinite(value)) return '—';

    return Number(value).toLocaleString(undefined, {
      maximumFractionDigits: digits == null ? 0 : digits
    });
  }

  function escapeHtml(value) {
    return String(value == null ? '' : value).replace(/[&<>"']/g, function (ch) {
      return {
        '&': '&amp;',
        '<': '&lt;',
        '>': '&gt;',
        '"': '&quot;',
        "'": '&#39;'
      }[ch];
    });
  }

  function isSherlockDashboard() {
    var heading = Array.from(document.querySelectorAll('main h1')).find(function (node) {
      return /^dashboard$/i.test((node.textContent || '').trim());
    });

    return Boolean(
      heading &&
      (location.pathname === '/' || /\/dashboard\/?$/i.test(location.pathname))
    );
  }

  function isSherlockApp() {
    return Boolean(
      document.querySelector('nav[aria-label="Main"]') &&
      document.querySelector('main h1')
    );
  }

  function normalizedName(value) {
    return String(value || '').toLowerCase().replace(/[^a-z0-9]/g, '');
  }

  function findNativeTrackerGrid() {
    if (!isSherlockDashboard()) return null;

    var sections = Array.from(document.querySelectorAll('main section.grid'));

    for (var i = 0; i < sections.length; i++) {
      var section = sections[i];

      if (
        section.classList.contains('mt-6') &&
        section.classList.contains('gap-3') &&
        section.classList.contains('sm:grid-cols-2') &&
        section.classList.contains('lg:grid-cols-3')
      ) {
        return section;
      }
    }

    return null;
  }

  function nativeTrackerNames(grid) {
    var names = new Set();
    if (!grid) return names;

    grid.querySelectorAll('a[href*="/connections/"]').forEach(function (card) {
      var label = card.querySelector('.font-medium');
      if (label) names.add(normalizedName(label.textContent));
    });

    return names;
  }

  function makeMetric(label, value) {
    return '<div class="min-w-0">' +
      '<dt class="eyebrow">' + escapeHtml(label) + '</dt>' +
      '<dd class="mt-1 truncate text-sm font-semibold" title="' +
      escapeHtml(value) + '">' + escapeHtml(value) + '</dd>' +
      '</div>';
  }

  function cardStatsMarkup(tracker) {
    var snapshot = latest(tracker);

    var uploaded = snapshot.uploaded;
    var downloaded = snapshot.downloaded;
    var buffer = snapshot.buffer;
    var ratio = snapshot.ratio;

    if (buffer == null && uploaded != null && downloaded != null) {
      buffer = uploaded - downloaded;
    }

    if (ratio == null && uploaded != null && downloaded > 0) {
      ratio = uploaded / downloaded;
    }

    return '<dl class="mt-4 grid grid-cols-2 gap-x-4 gap-y-3 ' +
      'border-t border-line-strong pt-3">' +
      makeMetric('Upload', formatBytes(uploaded)) +
      makeMetric('Download', formatBytes(downloaded)) +
      makeMetric('Ratio', formatNumber(ratio, 4)) +
      makeMetric('Buffer', formatBytes(buffer)) +
      '</dl>';
  }

  function createNativeCard(tracker) {
    var card = document.createElement('a');

    card.className = 'card flex flex-col p-4 hover:border-line-strong';
    card.setAttribute(CARD_ATTR, tracker.host);
    card.href = '#sherlock-local-tracker=' + encodeURIComponent(tracker.host);
    card.setAttribute('aria-label', tracker.name + ' tracker');

    var header = document.createElement('div');
    header.className = 'flex items-center gap-2';

    var logo = document.createElement('img');
    logo.className = 'size-8 shrink-0 rounded-lg object-contain';
    logo.alt = '';
    logo.loading = 'lazy';
    logo.referrerPolicy = 'no-referrer';
    logo.src = tracker.logo || ('https://' + tracker.host + '/favicon.ico');

    var fallback = document.createElement('span');
    fallback.className =
      'inline-flex size-8 shrink-0 items-center justify-center rounded-lg ' +
      'bg-accent-soft text-accent text-xs font-bold';

    fallback.textContent = (tracker.name || tracker.host)
      .replace(/[^a-z0-9]/gi, '').slice(0, 2).toUpperCase() || 'TR';

    fallback.style.display = 'none';

    logo.addEventListener('error', function () {
      logo.style.display = 'none';
      fallback.style.display = 'inline-flex';
    });

    var name = document.createElement('span');
    name.className = 'flex-1 truncate font-medium';
    name.textContent = tracker.name || tracker.host;

    header.appendChild(logo);
    header.appendChild(fallback);
    header.appendChild(name);
    card.appendChild(header);

    var metrics = document.createElement('div');
    metrics.innerHTML = cardStatsMarkup(tracker);
    card.appendChild(metrics.firstElementChild);

    card.addEventListener('click', function (event) {
      event.preventDefault();
      showDetails(tracker.host);
    });

    return card;
  }

  function addModalStyles() {
    if (document.getElementById(STYLE_ID)) return;

    var style = document.createElement('style');
    style.id = STYLE_ID;

    style.textContent =
      '#' + MODAL_ID + '{position:fixed;inset:0;z-index:2147483646;' +
      'display:flex;align-items:center;justify-content:center;padding:18px}' +
      '#' + MODAL_ID + ' .stl-backdrop{position:absolute;inset:0;' +
      'background:rgba(0,0,0,.68)}' +
      '#' + MODAL_ID + ' .stl-dialog{position:relative;z-index:1;' +
      'width:min(100%,980px);max-height:90vh;overflow:auto;padding:22px}' +
      '@media(max-width:600px){#' + MODAL_ID + ' .stl-dialog{padding:14px}}';

    document.head.appendChild(style);
  }

  function showDetails(host) {
    var store = readStore();
    var tracker = store[host];

    if (!isSupportedTrackerRecord(tracker)) return;

    var old = document.getElementById(MODAL_ID);
    if (old) old.remove();

    var snapshot = latest(tracker);

    var stats = [
      ['Uploaded', formatBytes(snapshot.uploaded)],
      ['Downloaded', formatBytes(snapshot.downloaded)],
      ['Buffer', formatBytes(snapshot.buffer)],
      ['Ratio', formatNumber(snapshot.ratio, 4)],
      ['Bonus points', formatNumber(snapshot.bonus_points, 2)],
      ['Seeding', formatNumber(snapshot.seeding)],
      ['Leeching', formatNumber(snapshot.leeching)],
      ['Snatched', formatNumber(snapshot.snatched)],
      ['Hit & Runs', formatNumber(snapshot.hit_and_runs)],
      ['Uploads', formatNumber(snapshot.uploads)],
      ['Forum posts', formatNumber(snapshot.forum_posts)],
      ['Torrent comments', formatNumber(snapshot.torrent_comments)]
    ];

    var statHtml = stats.map(function (item) {
      return '<div class="card p-3">' +
        '<p class="eyebrow">' + escapeHtml(item[0]) + '</p>' +
        '<p class="mt-2 text-lg font-semibold">' + escapeHtml(item[1]) + '</p>' +
        '</div>';
    }).join('');

    var historyHtml = (tracker.snapshots || []).slice(-30).reverse().map(function (row) {
      return '<tr>' +
        '<td>' + escapeHtml(row.time) + '</td>' +
        '<td>' + escapeHtml(formatBytes(row.uploaded)) + '</td>' +
        '<td>' + escapeHtml(formatBytes(row.downloaded)) + '</td>' +
        '<td>' + escapeHtml(formatBytes(row.buffer)) + '</td>' +
        '<td>' + escapeHtml(formatNumber(row.ratio, 3)) + '</td>' +
        '</tr>';
    }).join('');

    var overlay = document.createElement('div');
    overlay.id = MODAL_ID;

    overlay.innerHTML =
      '<div class="stl-backdrop" data-stl-close></div>' +
      '<div class="stl-dialog card" role="dialog" aria-modal="true">' +
        '<div class="flex items-center justify-between gap-3 mb-4">' +
          '<div>' +
            '<h2 class="heading text-xl">' + escapeHtml(tracker.name) + '</h2>' +
            '<p class="hint mt-1">' + escapeHtml(tracker.host) +
            ' · Browser-local statistics</p>' +
          '</div>' +
          '<button type="button" class="btn-quiet" data-stl-close aria-label="Close">✕</button>' +
        '</div>' +
        '<div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">' + statHtml + '</div>' +
        '<h3 class="heading text-lg mt-6 mb-3">Snapshot history</h3>' +
        '<div class="overflow-x-auto">' +
          '<table class="table">' +
            '<thead><tr><th>Time</th><th>Uploaded</th><th>Downloaded</th>' +
            '<th>Buffer</th><th>Ratio</th></tr></thead>' +
            '<tbody>' + (historyHtml || '<tr><td colspan="5">No history yet</td></tr>') +
            '</tbody>' +
          '</table>' +
        '</div>' +
      '</div>';

    document.body.appendChild(overlay);

    overlay.querySelectorAll('[data-stl-close]').forEach(function (node) {
      node.addEventListener('click', function () {
        overlay.remove();
      });
    });

    function closeOnEscape(event) {
      if (event.key === 'Escape') {
        overlay.remove();
        document.removeEventListener('keydown', closeOnEscape);
      }
    }

    document.addEventListener('keydown', closeOnEscape);
    addModalStyles();
  }

  function renderNativeCards() {
    if (!isSherlockDashboard()) return;

    var grid = findNativeTrackerGrid();
    if (!grid) return;

    var store = readStore();

    // Canonical whitelist is enforced here as well as during capture.
    var trackers = Object.keys(store).map(function (key) {
      return store[key];
    }).filter(function (tracker) {
      return isSupportedTrackerRecord(tracker);
    });

    var storeChanged = false;
    trackers.forEach(function (tracker) {
      var canonical = registryEntry(tracker.host);
      if (normalizeTrackerRecord(tracker, tracker.host)) storeChanged = true;
      if (canonical) {
        var nextLogo = resolvedLogo(tracker, canonical);
        if (tracker.logo !== nextLogo) {
          tracker.logo = nextLogo;
          storeChanged = true;
        }
      }
    });

    if (storeChanged) writeStore(store);

    var nativeNames = nativeTrackerNames(grid);

    trackers = trackers.filter(function (tracker) {
      var nameKey = normalizedName(tracker.full_name || tracker.name);
      var shortKey = normalizedName(tracker.short_name);
      var displayKey = normalizedName(tracker.name);

      return !nativeNames.has(nameKey) &&
        !(shortKey && nativeNames.has(shortKey)) &&
        !(displayKey && nativeNames.has(displayKey));
    });

    trackers.sort(function (a, b) {
      var ca = registryEntry(a.host);
      var cb = registryEntry(b.host);
      var aPrimary = ca && ca.hosts[0] === a.host ? 0 : 1;
      var bPrimary = cb && cb.hosts[0] === b.host ? 0 : 1;
      return aPrimary - bPrimary || String(a.full_name || a.name).localeCompare(String(b.full_name || b.name));
    });

    var seenSites = new Set();

    trackers = trackers.filter(function (tracker) {
      var canonical = registryEntry(tracker.host);
      var key = canonical ? canonical.slug : tracker.host;

      if (seenSites.has(key)) return false;
      seenSites.add(key);
      return true;
    });

    var signature = JSON.stringify(trackers.map(function (tracker) {
      var last = latest(tracker);
      return [
        tracker.host,
        displayTrackerName(tracker),
        tracker.full_name || '',
        tracker.logo,
        last.fingerprint || '',
        last.uploaded,
        last.downloaded,
        last.ratio,
        last.buffer,
        (tracker.snapshots || []).length
      ];
    }));

    var existing = new Map();

    grid.querySelectorAll('[' + CARD_ATTR + ']').forEach(function (node) {
      existing.set(node.getAttribute(CARD_ATTR), node);
    });

    var expectedHosts = trackers.map(function (tracker) {
      return tracker.host;
    }).sort();

    var actualHosts = Array.from(existing.keys()).sort();

    if (
      signature === lastRenderSignature &&
      JSON.stringify(actualHosts) === JSON.stringify(expectedHosts)
    ) {
      return;
    }

    grid.querySelectorAll('[' + CARD_ATTR + ']').forEach(function (card) {
      card.remove();
    });

    trackers.forEach(function (tracker) {
      grid.appendChild(createNativeCard(tracker));
    });

    lastRenderSignature = signature;
    renderSidebar();
    addModalStyles();
  }

  function findTrackerSidebarArea(nav) {
    var heading = Array.from(nav.querySelectorAll('p.eyebrow')).find(function (node) {
      return /^trackers$/i.test((node.textContent || '').trim());
    });
    if (!heading) return null;

    var addLink = Array.from(nav.querySelectorAll('a')).find(function (node) {
      return /add tracker/i.test(node.textContent || '');
    });
    return addLink ? { heading: heading, addLink: addLink } : null;
  }

  function renderSidebar() {
    if (!isSherlockApp()) return;

    document.querySelectorAll('[data-sherlock-added-sidebar], [data-sherlock-local-sidebar-old]').forEach(function (node) { node.remove(); });

    document.querySelectorAll('nav[aria-label="Main"]').forEach(function (nav) {
      var area = findTrackerSidebarArea(nav);
      if (!area) return;

      var nativeNames = new Set();
      var node = area.heading.nextElementSibling;
      while (node && node !== area.addLink) {
        if (node.matches('a.nav-link') && !node.hasAttribute('data-sherlock-local-sidebar')) {
          if (node.style.display === 'none') node.style.removeProperty('display');
          nativeNames.add(normalizedName(node.querySelector('.flex-1')?.textContent || node.textContent));
        }
        node = node.nextElementSibling;
      }

      var store = readStore();
      var trackers = Object.keys(store).map(function (key) { return store[key]; })
        .filter(function (tracker) {
          if (!tracker || !tracker.host || !tracker.name || !isSupportedTrackerRecord(tracker)) return false;
          var name = normalizedName(tracker.full_name || tracker.name);
          var shortName = normalizedName(tracker.short_name);
          var displayName = normalizedName(displayTrackerName(tracker));
          return !nativeNames.has(name) && !(shortName && nativeNames.has(shortName)) && !(displayName && nativeNames.has(displayName));
        })
        .sort(function (a, b) {
          var ca = registryEntry(a.host);
          var cb = registryEntry(b.host);
          var aPrimary = ca && ca.hosts[0] === a.host ? 0 : 1;
          var bPrimary = cb && cb.hosts[0] === b.host ? 0 : 1;
          return aPrimary - bPrimary || String(a.name).localeCompare(String(b.name));
        });

      // Collapse alternate domains for the same canonical tracker.
      var uniqueSidebarTrackers = [];
      var seenSidebarSites = new Set();
      trackers.forEach(function (tracker) {
        var canonical = registryEntry(tracker.host);
        var siteKey = canonical ? canonical.slug : tracker.host;
        if (seenSidebarSites.has(siteKey)) return;
        seenSidebarSites.add(siteKey);
        uniqueSidebarTrackers.push(tracker);
      });
      trackers = uniqueSidebarTrackers;

      // Include uploaded value in the signature so the sidebar refreshes
      // when a new account snapshot is captured.
      var signature = JSON.stringify(trackers.map(function (tracker) {
        var current = latest(tracker);
        return [tracker.host, tracker.name, tracker.logo, current.uploaded, current.fingerprint || ''];
      }));

      var current = Array.from(nav.querySelectorAll('[data-sherlock-local-sidebar]'));
      var currentHosts = current.map(function (link) {
        return link.getAttribute('data-sherlock-local-sidebar');
      }).sort();
      var wantedHosts = trackers.map(function (tracker) { return tracker.host; }).sort();

      if (signature === nav.getAttribute('data-sherlock-sidebar-signature') &&
          JSON.stringify(currentHosts) === JSON.stringify(wantedHosts)) return;

      current.forEach(function (link) { link.remove(); });

      trackers.forEach(function (tracker) {
        var link = document.createElement('a');
        link.className = 'nav-link';
        link.href = '#sherlock-local-tracker=' + encodeURIComponent(tracker.host);
        link.setAttribute('data-sherlock-local-sidebar', tracker.host);
        link.title = tracker.name;

        var img = document.createElement('img');
        img.className = 'size-5 shrink-0 rounded-md object-contain';
        img.alt = '';
        img.loading = 'lazy';
        img.referrerPolicy = 'no-referrer';
        img.src = tracker.logo || ('https://' + tracker.host + '/favicon.ico');
        img.addEventListener('error', function () {
          img.replaceWith(document.createTextNode((tracker.name || '?').slice(0, 1).toUpperCase()));
        }, { once: true });

        var label = document.createElement('span');
        label.className = 'flex-1 min-w-0 truncate';
        label.textContent = tracker.name;

        // Uploaded amount beside tracker name, matching a compact native sidebar.
        var uploaded = latest(tracker).uploaded;
        var uploadValue = document.createElement('span');
        uploadValue.className = 'ml-auto shrink-0 text-xs text-muted tabular-nums';
        uploadValue.textContent = formatBytes(uploaded);
        uploadValue.title = 'Uploaded';
        uploadValue.setAttribute('aria-label', 'Uploaded ' + formatBytes(uploaded));

        link.appendChild(img);
        link.appendChild(label);
        link.appendChild(uploadValue);
        link.addEventListener('click', function (event) {
          event.preventDefault();
          showDetails(tracker.host);
        });

        area.addLink.parentNode.insertBefore(link, area.addLink);
      });

      nav.setAttribute('data-sherlock-sidebar-signature', signature);
    });
  }

  function exportCsv() {
    var store = readStore();
    var columns = [
      'tracker', 'host', 'time', 'uploaded', 'downloaded', 'buffer', 'ratio',
      'bonus_points', 'seeding', 'leeching', 'snatched', 'hit_and_runs',
      'uploads', 'forum_posts', 'torrent_comments', 'uploaded_change',
      'downloaded_change', 'buffer_change', 'interval_ratio'
    ];

    function quote(value) {
      return '"' + String(value == null ? '' : value).replace(/"/g, '""') + '"';
    }

    var rows = [columns.join(',')];
    Object.keys(store).forEach(function (host) {
      var tracker = store[host];
      (tracker.snapshots || []).forEach(function (row, index, list) {
        var previous = list[index - 1] || {};
        var up = row.uploaded != null && previous.uploaded != null
          ? row.uploaded - previous.uploaded : '';
        var down = row.downloaded != null && previous.downloaded != null
          ? row.downloaded - previous.downloaded : '';
        var buffer = row.buffer != null && previous.buffer != null
          ? row.buffer - previous.buffer : '';
        var intervalRatio = down !== '' && down > 0 && up !== '' ? up / down : '';

        rows.push([
          tracker.name, host, row.time, row.uploaded, row.downloaded, row.buffer,
          row.ratio, row.bonus_points, row.seeding, row.leeching, row.snatched,
          row.hit_and_runs, row.uploads, row.forum_posts, row.torrent_comments,
          up, down, buffer, intervalRatio
        ].map(quote).join(','));
      });
    });

    var blob = new Blob([rows.join('\r\n')], { type: 'text/csv;charset=utf-8' });
    var url = URL.createObjectURL(blob);
    var link = document.createElement('a');
    link.href = url;
    link.download = 'sherlock-tracker-history.csv';
    link.click();
    setTimeout(function () { URL.revokeObjectURL(url); }, 1000);
  }

  function migrateStores() {
    var current = readStore();
    var changed = false;
    var oldKeys = ['sherlockNativeTrackerCards.v2', 'sherlockTrackerStatsBridge.v1'];

    oldKeys.forEach(function (key) {
      try {
        var old = GM_getValue(key, null);
        if (!old || typeof old !== 'object' || Array.isArray(old)) return;
        Object.keys(old).forEach(function (host) {
          if (!current[host] && old[host]) {
            current[host] = old[host];
            changed = true;
          }
        });
      } catch (e) {}
    });

    // Migrate identity-only records from previous v5.0/v5.1 versions.
    try {
      var newer = GM_getValue('sherlock_additive_trackers_v5', null);
      if (Array.isArray(newer)) {
        newer.forEach(function (item) {
          if (!item) return;
          var host = String(item.host || item.id || '').toLowerCase().replace(/^www\./, '');
          if (!host || current[host]) return;
          var identity = registryEntry(host);
          var fullName = identity ? identity.name : fallbackNameFromHost(host);
          var shortName = identity ? identity.short : shortCodeFromName(fullName);
          current[host] = {
            host: host,
            name: shortName,
            full_name: fullName,
            logo: identity ? defaultLogoUrl(identity) : (item.logo || ''),
            slug: identity ? identity.slug : '',
            short_name: shortName,
            first_seen: localTime(),
            snapshots: []
          };
          changed = true;
        });
      }
    } catch (e) {}

    // Normalize saved names and logos using the canonical registry.
    Object.keys(current).forEach(function (host) {
      var tracker = current[host];
      if (!tracker || typeof tracker !== 'object') return;
      var canonical = registryEntry(host);
      if (normalizeTrackerRecord(tracker, host)) changed = true;
      if (canonical) {
        var desiredLogo = resolvedLogo(tracker, canonical);
        if (tracker.logo !== desiredLogo) {
          tracker.logo = desiredLogo;
          changed = true;
        }
      }

      if (!Array.isArray(tracker.snapshots)) tracker.snapshots = [];
    });

    if (changed) writeStore(current);
  }

  function init() {
    migrateStores();

    function scheduleAll() {
      clearTimeout(captureTimer);
      captureTimer = setTimeout(function () {
        if (isSherlockDashboard()) {
          renderNativeCards();
          renderSidebar();
        } else if (isSherlockApp()) {
          renderSidebar();
        } else if (shouldCaptureCurrentPage(hostKey())) {
          captureProfile();
        }
      }, 900);
    }

    ['pushState', 'replaceState'].forEach(function (method) {
      var original = history[method];
      if (typeof original !== 'function' || original.__sherlockNativeWrapped) return;

      var wrapped = function () {
        var result = original.apply(this, arguments);
        setTimeout(scheduleAll, 350);
        return result;
      };
      wrapped.__sherlockNativeWrapped = true;
      history[method] = wrapped;
    });

    window.addEventListener('popstate', scheduleAll);
    scheduleAll();

    var observer = new MutationObserver(function (mutations) {
      var relevant = mutations.some(function (mutation) {
        var nodes = Array.from(mutation.addedNodes || []).concat(Array.from(mutation.removedNodes || []));
        return nodes.some(function (node) {
          if (node.nodeType !== 1) return false;
          if (node.hasAttribute(CARD_ATTR) || node.hasAttribute('data-sherlock-local-sidebar')) return false;
          if (node.closest && node.closest('[' + CARD_ATTR + '], [data-sherlock-local-sidebar]')) return false;
          return true;
        });
      });

      if (!relevant) return;
      clearTimeout(mutationTimer);
      mutationTimer = setTimeout(function () {
        if (isSherlockDashboard()) {
          renderNativeCards();
          renderSidebar();
        } else if (isSherlockApp()) {
          renderSidebar();
        } else if (shouldCaptureCurrentPage(hostKey())) {
          captureProfile();
        }
      }, 700);
    });

    if (document.body) {
      observer.observe(document.body, {
        childList: true,
        subtree: true,
        characterData: true
      });
    }

    document.addEventListener('visibilitychange', function () {
      if (!document.hidden) scheduleAll();
    });

    // Repair Turbo partial replacements and refresh sidebar uploaded values.
    window.setInterval(function () {
      if (isSherlockDashboard()) renderNativeCards();
      if (isSherlockApp()) renderSidebar();
    }, 2500);

    if (typeof GM_registerMenuCommand === 'function') {
      GM_registerMenuCommand('Sherlock: Export local tracker history CSV', exportCsv);

      GM_registerMenuCommand('Sherlock: Refresh native tracker cards', function () {
        lastRenderSignature = '';
        renderNativeCards();
        renderSidebar();
      });

      GM_registerMenuCommand('Sherlock: Save current tracker profile now', function () {
        if (captureProfile()) alert('Tracker identity/profile saved.');
        else alert('This page was not detected as a supported tracker profile.');
      });

      GM_registerMenuCommand('Sherlock: Clear locally captured tracker data', function () {
        if (confirm('Delete all tracker statistics stored by this userscript?')) {
          writeStore({});
          lastRenderSignature = '';
          renderNativeCards();
          renderSidebar();
        }
      });
    }
  }

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
      normalizeHost: normalizeHost,
      registryEntry: registryEntry,
      fallbackNameFromHost: fallbackNameFromHost,
      trackerDirectory: TRACKER_DIRECTORY,
      trackerDirectoryEntry: trackerDirectoryEntry,
      shortCodeFromName: shortCodeFromName,
      displayTrackerName: displayTrackerName,
      normalizeTrackerRecord: normalizeTrackerRecord,
      isSupportedTrackerRecord: isSupportedTrackerRecord,
      isUnit3DSite: isUnit3DSite,
      unit3dIdentity: unit3dIdentity,
      extractUnit3dBar: extractUnit3dBar,
      shouldCaptureCurrentPage: shouldCaptureCurrentPage,
      captureProfile: captureProfile
    };
    return;
  }

  init();
})();