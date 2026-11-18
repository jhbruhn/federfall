// C2 — Custody and handing a bird over. One blackbird, Mika, seen from both
// sides of a handover, with the reason for each rule in the narration.
//
//   Mika's case      Lena holds Mika: Tarek handed him over for his holiday
//   Who may write    a case is written by whoever cares for the bird now, an
//                    edit share, the supervisor — everyone else reads at most
//   The handover     the placement in History that changed the carer, in the
//                    same step as the record of it
//   Back to Tarek    Lena hands Mika back on camera: the carer field turns a
//                    move into a handover, the confirmation says what she keeps
//   Read only        the badge (and its tooltip), no write control left — not
//                    even on the entry she just wrote — and why: writing about a
//                    bird belongs to whoever holds it; the animal record says
//                    the same
//   Tarek's side     a real role switch (signOut → signIn({ as })): Mika is in
//                    his list again, no badge, the entry has its menu
//
// Lena (carer) signs in first, Tarek (carer2) second. The story's data is the
// demo dataset's (Mika, handed over six days ago); nothing is added in setup().
import { defineVideo, signIn, signOut } from '../harness/video.mjs';
import { PEOPLE } from '../harness/data/base.mjs';
import { BIRDS } from '../harness/data/demo/cast.mjs';

const MIKA = BIRDS.mika.name;
const LENA = PEOPLE.carer.name;
const TAREK = PEOPLE.carer2.name;
const CONDITION = { de: 'Wunde verheilt, frisst selbstständig', en: 'Wound healed, feeding himself' };

/** The case header: avatar, name, species, carer line and status chip. */
const headerBox = (b) => ({ x: 16, y: b.y - 8, width: 380, height: 130 });

export default defineVideo({
  id: 'C2',
  slug: 'custody',
  title: { de: 'Obhut und Übergabe', en: 'Custody and handover' },
  viewport: 'phone',
  dataset: 'demo',
  signInAs: 'carer',
  steps: [
    ...signIn({
      say: {
        de: 'Wer darf über einen Vogel schreiben? Und was ändert sich, wenn du ihn weitergibst? Eine Amsel, zwei Pflegestellen.',
        en: 'Who may write about a bird? And what changes when you hand it on? One blackbird, two carers.',
      },
    }),

    // ── Mika's case ──────────────────────────────────────────────────────
    {
      name: 'open Mika',
      title: { de: 'Mikas Fall', en: "Mika's case" },
      run: async (s) => {
        await s.click(s.role('tab', s.t('navCases')));
        await s.click(s.role('button', s.rowOf(`${MIKA} ·`)));
        await s.waitFor(s.role('tab', s.t('caseTabHistory')));
        await s.rest({ x: s.vp.width * 0.7, y: s.vp.height * 0.2 });
      },
    },
    {
      name: 'Lena holds Mika',
      say: {
        de: 'Mika ist eigentlich Tareks Amsel. Für seinen Urlaub hat Tarek ihn an Lena übergeben – seitdem betreut sie ihn.',
        en: "Mika is really Tarek's blackbird. Tarek handed him to Lena for his holiday, and she has been caring for him since.",
      },
      zoom: { depth: 2 },
      run: async (s) => {
        await s.expectText(LENA);
        await s.focus(s.buttonStartingWith('caseOpenAnimal'), { box: headerBox });
      },
    },
    {
      name: 'who may write',
      title: { de: 'Wer schreiben darf', en: 'Who may write' },
      say: {
        de: 'Einen Fall bearbeiten darf, wer den Vogel gerade betreut. Dazu, wem der Fall zum Bearbeiten geteilt ist – und die Leitung. Alle anderen können höchstens lesen.',
        en: 'A case can be edited by whoever is caring for the bird right now. Also by anyone it is shared with for editing, and by the supervisor. Everyone else can read it at most.',
      },
      run: async (s) => { await s.hold(300); },
    },

    // ── The handover in the history ──────────────────────────────────────
    {
      name: 'to the handover',
      title: { de: 'Die Übergabe', en: 'The handover' },
      run: async (s) => {
        await s.click(s.role('tab', s.t('caseTabHistory')));
        await s.reveal(s.role('group', s.rowOf(s.t('placementHandedOffTo', { name: LENA }))));
        // reveal() stops once the node's box touches the screen; bring the
        // entry up to the middle, clear of the "Eintrag" button.
        await s.pointer.wheel('down', 3);
        await s.hold(400);
        await s.rest({ x: s.vp.width * 0.7, y: s.vp.height * 0.3 });
      },
    },
    {
      name: 'a placement with a new carer',
      say: {
        de: 'Im Verlauf steht die Übergabe: ein Umzug, bei dem die Pflegestelle wechselt. Zustand und Notiz gehen mit.',
        en: 'The handover is in the history: a move in which the carer changes. The condition and a note go with it.',
      },
      zoom: { depth: 2 },
      run: async (s) => {
        await s.focus(s.role('group', s.rowOf(s.t('placementHandedOffTo', { name: LENA }))));
      },
    },
    {
      name: 'one step',
      say: {
        de: 'Wer den Vogel betreut, wechselt im selben Schritt. So können Eintrag und Zuständigkeit nie auseinanderlaufen.',
        en: 'Who cares for the bird changes in the same step. So the record and the responsibility can never drift apart.',
      },
      zoom: { depth: 2 },
      run: async (s) => {
        await s.focus(s.role('group', s.rowOf(s.t('placementHandedOffTo', { name: LENA }))));
      },
    },

    // ── Lena hands Mika back ─────────────────────────────────────────────
    {
      name: 'open the placement form',
      title: { de: 'Zurück an Tarek', en: 'Back to Tarek' },
      say: {
        de: (t) => `Tarek ist zurück. Lena gibt Mika ab: „${t('timelineAddEntry')}“, dann „${t('placementTitle')}“.`,
        en: (t) => `Tarek is back. Lena hands Mika over: “${t('timelineAddEntry')}”, then “${t('placementTitle')}”.`,
      },
      run: async (s) => {
        await s.click(s.button('timelineAddEntry'));
        await s.click(s.button('placementTitle'));
        await s.waitFor(s.buttonStartingWith('placementFieldCarer'));
        await s.rest({ x: s.vp.width * 0.86, y: s.vp.height * 0.3 });
      },
    },
    {
      name: 'pick Tarek',
      run: async (s) => {
        await s.click(s.buttonStartingWith('placementFieldCarer'));
        await s.click(s.role('menuitem', TAREK));
        await s.expectText(s.t('placementHandoffHint'));
        await s.rest({ x: s.vp.width * 0.86, y: s.vp.height * 0.3 });
      },
    },
    {
      name: 'a move becomes a handover',
      say: {
        de: (t) => `Eine andere „${t('placementFieldCarer')}“ macht aus dem Umzug eine Übergabe. Der Hinweis darunter sagt es sofort.`,
        en: (t) => `A different “${t('placementFieldCarer')}” turns the move into a handover. The note below it says so at once.`,
      },
      zoom: { depth: 2 },
      run: async (s) => {
        await s.focus(s.buttonStartingWith('placementFieldCarer'), {
          box: (b) => ({ x: b.x, y: b.y, width: b.width, height: b.height + 52 }),
        });
      },
    },
    {
      name: 'condition and save',
      run: async (s) => {
        await s.type(s.textbox('placementFieldCondition'), s.pick(CONDITION));
        await s.click(s.button('actionSave'));
        await s.waitFor(s.button('placementHandoffConfirmAction'));
        await s.rest({ x: s.vp.width * 0.5, y: s.vp.height * 0.75 });
      },
    },
    {
      name: 'the confirmation',
      say: {
        de: 'Weil Lena damit ihre Schreibrechte abgibt, fragt die App nach. Sie behält nur Lesezugriff.',
        en: 'Because Lena is giving up her right to write, the app asks first. She keeps read access only.',
      },
      run: async (s) => {
        await s.expectText(s.t('placementHandoffConfirmBody', { name: TAREK }));
        await s.hold(300);
      },
    },
    {
      name: 'hand over',
      run: async (s) => {
        await s.click(s.button('placementHandoffConfirmAction'));
        await s.waitFor(s.role('checkbox', s.t('caseReadOnly')), { timeout: 15_000 });
        // Without a write control left, the entries have no nodes of their
        // own (their text merges into the tab's label): scroll to the top by
        // wheel and prove the new entry by its text.
        await s.pointer.moveTo(s.vp.width * 0.5, s.vp.height * 0.6);
        await s.pointer.wheel('up', 25);
        await s.expectText(s.t('placementHandedOffTo', { name: TAREK }));
        await s.rest({ x: s.vp.width * 0.86, y: s.vp.height * 0.5 });
      },
    },

    // ── Read only ────────────────────────────────────────────────────────
    {
      name: 'the badge',
      title: { de: 'Nur noch lesen', en: 'Read only now' },
      say: {
        de: (t) => `Oben steht jetzt „${t('caseReadOnly')}“, und Tarek ist als Pflegestelle eingetragen. Lena sieht alles – nur die Knöpfe zum Schreiben sind weg.`,
        en: (t) => `At the top it now says “${t('caseReadOnly')}”, and Tarek is the carer. Lena still sees everything – only the controls for writing are gone.`,
      },
      zoom: { depth: 2 },
      run: async (s) => {
        const badge = await s.box(s.role('checkbox', s.t('caseReadOnly')));
        await s.focus(s.buttonStartingWith('caseOpenAnimal'), {
          box: (b) => ({ x: b.x - 8, y: b.y - 8, width: badge.x + badge.width - b.x + 8, height: 130 }),
        });
        await s.expectText(TAREK);
        // Hovering the badge shows why.
        await s.pointer.moveTo(badge.x + badge.width / 2, badge.y + badge.height / 2);
      },
    },
    {
      name: 'not even her own entry',
      say: {
        de: 'Auch ihre eigene Übergabe kann Lena nicht mehr ändern oder löschen. Über einen Vogel schreibt nur, wer ihn gerade hält.',
        en: 'Lena can no longer change or delete even her own handover. Only whoever holds a bird now writes about it.',
      },
      zoom: { depth: 2 },
      run: async (s) => {
        // The newest two entries: the created milestone, then the handover.
        await s.focus(s.role('tab', s.t('caseTabHistory')), {
          box: (b) => ({ x: 16, y: b.y + b.height + 8, width: 380, height: 260 }),
        });
        await s.rest({ x: s.vp.width * 0.9, y: s.vp.height * 0.2 });
      },
    },
    {
      name: 'why it cannot be undone',
      say: {
        de: 'Sonst könnte jede frühere Pflegestelle einen Vogel zurückholen, ohne dass die jetzige es merkt. War es ein Versehen, gibt Tarek ihn mit einer neuen Übergabe zurück – oder die Leitung hilft.',
        en: 'Otherwise any former carer could take a bird back without the current one noticing. If it was a mistake, Tarek hands him back with a new handover – or the supervisor steps in.',
      },
      run: async (s) => { await s.hold(300); },
    },
    {
      name: 'the animal record',
      run: async (s) => {
        await s.click(s.buttonStartingWith('caseOpenAnimal'));
        await s.waitFor(s.role('checkbox', s.t('animalReadOnly')));
        await s.rest({ x: s.vp.width * 0.5, y: s.vp.height * 0.45 });
      },
    },
    {
      name: 'the bird, too',
      title: { de: 'Die Tierakte', en: 'The animal record' },
      say: {
        de: 'Die Tierakte sagt dasselbe: Gewichte, Fotos und Ringe trägt nur ein, wer den Vogel hält. Lebt er in einer Voliere, hält ihn auch, wer sie betreut.',
        en: 'The animal record says the same: weights, photos and rings are entered only by whoever holds the bird. If it lives in an aviary, its keeper holds it too.',
      },
      zoom: { depth: 2 },
      run: async (s) => {
        const badge = await s.box(s.role('checkbox', s.t('animalReadOnly')));
        await s.focus(s.role('checkbox', s.t('animalReadOnly')), {
          box: () => ({ x: 16, y: badge.y - 8, width: 380, height: 120 }),
        });
        await s.pointer.moveTo(badge.x + badge.width / 2, badge.y + badge.height / 2);
      },
    },
    {
      name: 'back to the registry',
      run: async (s) => {
        await s.click(s.button('actionBack'));
        await s.waitFor(s.textbox('animalsSearchHint'));
        await s.rest();
      },
    },

    // ── Tarek's side ─────────────────────────────────────────────────────
    ...signOut({
      title: { de: 'Tareks Seite', en: "Tarek's side" },
      say: {
        de: 'Jetzt dieselbe Amsel von der anderen Seite: Lena meldet sich ab, Tarek meldet sich an.',
        en: 'Now the same blackbird from the other side: Lena signs out, Tarek signs in.',
      },
    }),
    ...signIn({ as: 'carer2' }),
    {
      name: "Tarek's cases",
      run: async (s) => {
        // Signing in returns to where the app was: the profile, now Tarek's.
        await s.expectText(TAREK);
        await s.hold(600);
        await s.click(s.button('actionBack'));
        await s.click(s.role('tab', s.t('navCases')));
        await s.waitFor(s.role('button', s.rowOf(`${MIKA} ·`)));
        await s.rest();
      },
    },
    {
      name: 'Mika is in his list',
      say: {
        de: (t) => `Mika steht wieder in Tareks „${t('casesTitle')}“.`,
        en: (t) => `Mika is back in Tarek's “${t('casesTitle')}”.`,
      },
      zoom: { depth: 2 },
      run: async (s) => {
        await s.focus(s.role('button', s.rowOf(`${MIKA} ·`)));
      },
    },
    {
      name: 'open Mika as Tarek',
      run: async (s) => {
        await s.click(s.role('button', s.rowOf(`${MIKA} ·`)));
        await s.waitFor(s.role('tab', s.t('caseTabHistory')));
        await s.waitFor(s.button('caseEditIntakeTitle'));
        await s.rest({ x: s.vp.width * 0.7, y: s.vp.height * 0.2 });
      },
    },
    {
      name: 'no badge',
      say: {
        de: (t) => `Kein „${t('caseReadOnly')}“: Tarek betreut Mika wieder und kann alles eintragen.`,
        en: (t) => `No “${t('caseReadOnly')}”: Tarek is caring for Mika again and can record everything.`,
      },
      zoom: { depth: 2 },
      run: async (s) => {
        await s.gone(s.role('checkbox', s.t('caseReadOnly')));
        await s.focus(s.buttonStartingWith('caseOpenAnimal'), { box: headerBox });
      },
    },
    {
      name: 'his history',
      run: async (s) => {
        await s.click(s.role('tab', s.t('caseTabHistory')));
        await s.waitFor(s.role('group', s.rowOf(s.t('placementHandedOffTo', { name: TAREK }))));
        await s.rest({ x: s.vp.width * 0.7, y: s.vp.height * 0.2 });
      },
    },
    {
      name: 'the handover, his to change',
      say: {
        de: 'Die Übergabe steht auch bei ihm, und hier lässt sie sich bearbeiten. Alles, was Lena in der Urlaubswoche eingetragen hat, bleibt im Verlauf.',
        en: 'The handover is in his history too, and here it can be edited. Everything Lena recorded during the holiday week stays in the history.',
      },
      zoom: { depth: 2 },
      run: async (s) => {
        await s.focus(s.role('group', s.rowOf(s.t('placementHandedOffTo', { name: TAREK }))));
      },
    },
    {
      name: 'in short',
      title: { de: 'Kurz gesagt', en: 'In short' },
      say: {
        de: 'Schreiben darf, wer den Vogel hält. Eine Übergabe wechselt die Pflegestelle in einem Schritt, die alte behält Lesezugriff – und zurückgeben kann nur, wer ihn jetzt hat.',
        en: 'Whoever holds the bird writes about it. A handover changes the carer in one step, the old one keeps read access – and only whoever has the bird now can hand it back.',
      },
      run: async (s) => { await s.hold(300); },
    },
  ],
});
