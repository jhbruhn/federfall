// Labels by KEY, straight from the app's own ARB files.
//
// A script never spells a UI string. It names the ARB key (`authSignInAction`)
// and gets back whatever the app shows in the run's language, so one script
// serves de and en, and a reworded label cannot silently break a selector: the
// script follows the rewording, and a removed key fails loudly at lookup.
//
// The ARB values are ICU messages. Only what the app actually uses is handled:
// `{name}` placeholders, `{n, plural, =0{…} one{…} other{…}}` with `#`, and
// `{x, select, a{…} other{…}}`. Anything else throws rather than guessing.
import { readFileSync } from 'node:fs';
import path from 'node:path';

const cache = new Map();

function load(dir, locale) {
  const file = path.join(dir, `app_${locale}.arb`);
  if (!cache.has(file)) {
    cache.set(file, JSON.parse(readFileSync(file, 'utf8')));
  }
  return cache.get(file);
}

// Parses an ICU message into nodes: strings and {arg, type, options}.
function parse(src) {
  let i = 0;
  function message(stopAtBrace) {
    const out = [];
    let text = '';
    while (i < src.length) {
      const c = src[i];
      if (c === "'" && src[i + 1] === "'") {
        text += "'";
        i += 2;
      } else if (c === "'" && (src[i + 1] === '{' || src[i + 1] === '}')) {
        // ICU quoting: '{' is a literal brace.
        const end = src.indexOf("'", i + 1);
        text += src.slice(i + 1, end < 0 ? src.length : end);
        i = end < 0 ? src.length : end + 1;
      } else if (c === '{') {
        if (text) out.push(text);
        text = '';
        i++;
        out.push(argument());
      } else if (c === '}') {
        if (!stopAtBrace) throw new Error(`unbalanced "}" in ${src}`);
        break;
      } else {
        text += c;
        i++;
      }
    }
    if (text) out.push(text);
    return out;
  }
  function word() {
    const m = /^\s*([^\s,{}]+)\s*/.exec(src.slice(i));
    if (!m) throw new Error(`malformed ICU argument in ${src}`);
    i += m[0].length;
    return m[1];
  }
  function argument() {
    const name = word();
    if (src[i] === '}') {
      i++;
      return { arg: name };
    }
    if (src[i] !== ',') throw new Error(`malformed ICU argument in ${src}`);
    i++;
    const type = word();
    if (type !== 'plural' && type !== 'select') {
      throw new Error(`ICU type "${type}" is not supported (in ${src})`);
    }
    if (src[i] !== ',') throw new Error(`malformed ICU ${type} in ${src}`);
    i++;
    const options = {};
    while (true) {
      while (/\s/.test(src[i])) i++;
      if (src[i] === '}') {
        i++;
        break;
      }
      const key = word();
      if (src[i] !== '{') throw new Error(`malformed ICU option in ${src}`);
      i++;
      options[key] = message(true);
      i++; // the option's closing brace
    }
    return { arg: name, type, options };
  }
  const nodes = message(false);
  return nodes;
}

function pluralCategory(locale, n) {
  return new Intl.PluralRules(locale).select(n);
}

function render(nodes, params, locale, hash) {
  return nodes
    .map((n) => {
      if (typeof n === 'string') {
        return hash === undefined ? n : n.replaceAll('#', String(hash));
      }
      if (!(n.arg in params)) {
        throw new Error(`ARB placeholder {${n.arg}} needs a value`);
      }
      const v = params[n.arg];
      if (!n.type) return String(v);
      if (n.type === 'plural') {
        const exact = n.options[`=${v}`];
        const chosen = exact ?? n.options[pluralCategory(locale, Number(v))] ?? n.options.other;
        return render(chosen, params, locale, v);
      }
      const chosen = n.options[String(v)] ?? n.options.other;
      return render(chosen, params, locale, hash);
    })
    .join('');
}

/** A label lookup bound to one locale: `t('caseStepLabel', {current: 1, total: 3})`. */
export function labels(arbDir, locale) {
  const arb = load(arbDir, locale);
  const t = (key, params = {}) => {
    const raw = arb[key];
    if (typeof raw !== 'string') {
      throw new Error(`ARB key "${key}" does not exist in app_${locale}.arb`);
    }
    return render(parse(raw), params, locale);
  };
  return t;
}
