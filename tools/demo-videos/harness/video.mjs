// What a video script imports. See README.md, "Writing a video".
import { DATASETS } from './lib/dataset.mjs';
import { VIEWPORTS } from './lib/stage.mjs';

const LOCALES = ['de', 'en'];

/** Validates a video definition up front, so a typo fails before anything starts. */
export function defineVideo(v) {
  const problems = [];
  if (!/^[A-Z][0-9]+$/.test(v.id ?? '')) problems.push('id must look like "A3"');
  if (!/^[a-z0-9]+(-[a-z0-9]+)*$/.test(v.slug ?? '')) problems.push('slug must be kebab-case');
  for (const l of LOCALES) if (!v.title?.[l]) problems.push(`title.${l} is missing`);
  if (v.viewport && !VIEWPORTS[v.viewport]) problems.push(`viewport must be one of ${Object.keys(VIEWPORTS)}`);
  if (!v.signInAs) problems.push('signInAs is missing');
  if (v.dataset && !DATASETS.includes(v.dataset)) problems.push(`dataset must be one of ${DATASETS}`);
  if (!Array.isArray(v.steps) || v.steps.length === 0) problems.push('steps are missing');
  (v.steps ?? []).forEach((st, i) => {
    if (typeof st.run !== 'function') problems.push(`step ${i + 1} has no run()`);
    for (const key of ['say', 'title']) {
      if (st[key]) for (const l of LOCALES) if (!st[key][l]) problems.push(`step ${i + 1}: ${key}.${l} is missing`);
    }
  });
  if (problems.length) throw new Error(`video ${v.id ?? '?'}: ${problems.join('; ')}`);
  return Object.freeze({ viewport: 'phone', dataset: 'base', ...v });
}

/**
 * The sign-in, as steps: the person the video signs in as types their e-mail
 * and password and signs in. Narration and title are the caller's.
 */
export function signIn({ title, say } = {}) {
  return [
    {
      name: 'sign in',
      title,
      say,
      run: async (s) => {
        const { person } = s.data;
        await s.type(s.textbox('authEmailLabel'), person.email);
        await s.type(s.textbox('authPasswordLabel'), person.password);
        await s.click(s.button('authSignInAction'));
        await s.gone(s.button('authSignInAction'), { timeout: 20_000, what: 'the sign-in screen' });
      },
    },
  ];
}
