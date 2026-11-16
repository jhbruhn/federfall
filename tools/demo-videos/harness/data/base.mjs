// The base every video starts from. All names and addresses are fictional;
// e-mail addresses use the reserved .example domain.

export const ORG_NAME = {
  de: 'Wildvogelhilfe Elbmarsch',
  en: 'Elbmarsch Wild Bird Rescue',
};

// One account per role. The supervisor's e-mail must match
// FEDERFALL_SUPERVISOR_EMAIL in compose.yaml: the backend bootstraps that one.
export const PEOPLE = {
  supervisor: { role: 'supervisor', name: 'Johanna Brandt', email: 'leitung@wildvogelhilfe.example' },
  coordinator: { role: 'coordinator', name: 'Malte Riedel', email: 'malte@wildvogelhilfe.example' },
  carer: { role: 'carer', name: 'Lena Vogt', email: 'lena@wildvogelhilfe.example' },
  carer2: { role: 'carer', name: 'Tarek Aydin', email: 'tarek@wildvogelhilfe.example' },
};

// Code lists the migrations seed in German, keyed by the German label they
// seed. Only lists a recorded video shows are here so far; the demo dataset
// (federfall-1h9z.3) adds the rest. A row with no entry fails the setup.
export const CODE_LISTS = {
  admission_reasons: [
    { de: 'Verletzung', en: 'Injury' },
    { de: 'Krankheit', en: 'Illness' },
    { de: 'Verwaist (Jungtier)', en: 'Orphaned (juvenile)' },
    { de: 'Trauma', en: 'Trauma' },
    { de: 'Vergiftung', en: 'Poisoning' },
    { de: 'Gefangen/eingeklemmt', en: 'Trapped' },
    { de: 'Katzenangriff', en: 'Cat attack' },
    { de: 'Kollision', en: 'Collision' },
    { de: 'Verölt', en: 'Oiled' },
    { de: 'Verheddert', en: 'Entangled' },
    { de: 'Geschwächt/abgemagert', en: 'Weak/emaciated' },
    { de: 'Sonstiges', en: 'Other' },
  ],
};
