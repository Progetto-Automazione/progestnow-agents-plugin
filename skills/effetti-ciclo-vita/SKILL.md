---
name: effetti-ciclo-vita
description: Verifica lo stato degli effetti documentali (RIBA/RID), analizza anomalie, esegue il ciclo generazione → distinta → file bancario → trasferimento in prima nota → insoluti, e diagnostica i fallimenti, seguendo le regole di CAP-20260812-006.
---

> **Nel plugin (Claude, Codex).** Questa procedura nasce per il motore ProgestAI: dove differisce, vale questa nota.
> - `output=url` non va usato per scaricare dati: il tuo ambiente di esecuzione non raggiunge gli URL ProgestNOW. Restringi i filtri, aggrega lato server con `pn_tabellabase_aggregate`, oppure pagina con limiti piccoli; i calcoli locali li fai sui dati gia restituiti dai tool, nel tuo ambiente di esecuzione, al posto del "sandbox".
> - Questi tool qui non esistono: `pn_excel_generate`, `pn_pdf_generate`, `pn_ai_skill_resource`. Se un passaggio li richiede, usa un equivalente disponibile (il tuo ambiente di esecuzione per calcoli e file, la chat per testi da inviare) oppure dichiara all'utente il limite; non inventare chiamate.

# Ciclo di vita effetti documentali (RIBA/RID)

Procedura specialistica per lavorare sugli effetti documentali di ProgestNOW
(capability `CAP-20260812-006`). La semantica completa (regole, configurazioni,
dati) resta nella knowledge base canonica: consultala con il Knowledge MCP
(`get_capability_context`/`get_knowledge_unit` su `CAP-20260812-006` e sui nodi
`RULE-EFF-*`, `CFG-EFF-*`, `DATA-EFF-*`, `DIAG-EFF-*`, `QRY-EFF-*`) prima di
rispondere quando il caso non è coperto da questa procedura.

## Prerequisiti

- Identificare l'oggetto: `ideffetto` oppure anno + numero fattura (+ cliente).
- Le superfici di lettura sono le TabellaBase `effetti`, `effetti_presentati`,
  `effetti_daraggruppare`, `effetti_raggruppati` (se abilitate nel toolset).
- Le operazioni di scrittura si eseguono SOLO con i tool della famiglia
  `pn_effetti_*` (instruction EFFETTI-001). Se il tool manca: fermarsi e
  dichiarare il TOOLING_GAP, proponendo la UI come alternativa.

## Fasi

### Fase 1 — Stato di un effetto (UC-01)

1. Identifica l'effetto: `pn_tabellabase_single` su `effetti` (o `list` con filtri
   `anno`/`numerofattura`/`idcliente`).
2. Ricostruisci lo stato dal flag: `presentato` (0/1), `accreditato` (0/1),
   `ltrasferito` (0/1), `codicebancapresentazione`, `ndistinta`,
   `datapresentazione`, `datascadenza`, `importo`, `tipo_eff` (riba/rid).
3. Se serve il lineage col documento: cerca la fattura con
   `pn_documents_search` (macro tipo F/C, anno+numero) e `pn_document_read`.
4. Se serve il riscontro contabile (trasferito/insoluto): `pn_coge_partitario_search`
   per `rifpa = A/numerofattura` (o `anno/numerofattura`).
5. Restituisci: stato completo + eventuali anomalie (es. non presentato con
   scadenza passata, banca assente, presentato ma non trasferito).

Regole di riferimento: `RULE-EFF-002`, `RULE-EFF-006`, `DATA-EFF-001/003`.

### Fase 2 — Analisi di un insieme (UC-02)

1. Definisci i filtri (cliente, periodo scadenza, tipo, stato, banca).
2. `pn_tabellabase_list` con `output=url` se il volume è grande; altrimenti
   `pn_tabellabase_aggregate` per totali/conteggi.
3. Per stato "da presentare": filtra `presentato=0` (superficie
   `effetti_daraggruppare`); per "presentati": `effetti_presentati`.
4. Consegna dataset inline/URL; per report finali `pn_excel_generate`/
   `pn_pdf_generate` (tramite `result_set_id` o `inline_records`).

Regole di riferimento: `RULE-EFF-001`, `DATA-EFF-001`.

### Fase 3 — Generazione effetti da fatture (UC-03, write)

1. Verifica i documenti idonei con `pn_effetti_generation_candidates`
   (esercizio, tipo_eff riba/rid, tipo documento F/C, filtri periodo; la
   selezione applica `RULE-EFF-001` lato backend).
2. Presenta all'utente l'elenco e chiedi conferma di esecuzione.
3. Esegui `pn_effetti_generate_bulk` con la selezione (e banca per RIBA se
   richiesta). L'esito riporta effetti creati per documento e skip motivati.
4. Verifica con una lettura (Fase 1) che il documento sia marcato
   `trasfeffetti=1` e che gli effetti esistano.

Regole: `RULE-EFF-001..004`; config: `CFG-EFF-002/003/009`.

### Fase 4 — Distinta e file bancario (UC-07, write)

1. Seleziona gli effetti da presentare (non presentati, stessa banca).
2. `pn_effetti_distinta_create` (data presentazione, numero distinta, banca):
   validazione backend univoca (`RULE-EFF-006`); effetti marcati presentato.
3. `pn_effetti_distinta_file_generate` con formato
   `riba|rid|xml_sepa|lcr` e `n_distinta`: ritorna URL S3 temporaneo del file
   (non persistere l'URL; rinnovarlo se necessario).
4. Nota: la conformità ai layout bancari (CBI/SEPA) è `DA CONFERMARE` a runtime
   su tenant autorizzato.

Regole: `RULE-EFF-006/007`; config: `CFG-EFF-001` (raggruppa_riba).

### Fase 5 — Trasferimento in prima nota (UC-08, write)

1. Verifica effetti presentati non trasferiti (`ltrasferito=0`).
2. Raccogli i parametri: esercizio, data registrazione (entro l'esercizio),
   causale contabile (`tabcauc.tipo1=9`), banca di presentazione, sottoconto
   opzionale.
3. `pn_effetti_transfer_primanota`: l'esito dipende da `savePn`
   (`CAP-20260810-003`); la marcatura `ltrasferito=1` avviene solo a
   registrazione riuscita.
4. In caso di errore: riporta il messaggio dello store (es. "Data non
   compatibile con esercizio") e segui `DIAG-EFF-003`.

Regole: `RULE-EFF-008`; config: `CFG-EFF-005`, `CFG-EFF-009`.

### Fase 6 — Insoluti (UC-09, write)

1. Identifica gli effetti presentati da portare a insoluto.
2. Raccogli: causale contabile, data, esercizio, banca.
3. `pn_effetti_insoluti_transfer`: righe cliente in DARE, banca in AVERE
   (segno invertito rispetto al trasferimento ordinario).
4. Errori tipici e messaggi in `DIAG-EFF-003` / `RULE-EFF-009`.

Regole: `RULE-EFF-009`; config: `CFG-EFF-004` (insoluti_postfisso),
`CFG-EFF-005`.

### Fase 7 — Diagnosi (UC-11)

Applica i runbook canonici in ordine:

- Generazione senza effetti: `DIAG-EFF-001` (documento idoneo? `QRY-EFF-002`;
  scadenze/importi? `QRY-EFF-001`; effetti creati ma non visibili? `QRY-EFF-003`;
  `FIND-EFF-002` tipo_eff nullo).
- Distinta/file falliti: `DIAG-EFF-002` (stato e banca effetti `QRY-EFF-004`;
  banca completa `QRY-EFF-005`; S3).
- Trasferimento fallito: `DIAG-EFF-003` (esercizio/data; effetti già trasferiti;
  esito `savePn`; partite `QRY-EFF-005` parte 2).

Regola di sicurezza: la verifica di password per blocco/sblocco è solo
client-side (`FIND-EFF-001`): non citare il valore della password, non
riprodurre il controllo lato agente, e segnalare la limitazione se rilevante.

## Quando fermarsi / delegare

- Fermarsi e chiedere chiarimenti se mancano parametri obbligatori per write
  (esercizio, data, causale, banca).
- Delegare la sola lettura documentale a PNOWDOC se il toolset corrente non
  include `pn_documents_search`.
- Non inventare stati, distinte, partite o file: tutto ciò che non è leggibile
  va dichiarato come non verificabile.

## Criteri di completamento

- Stato ricostruito con evidenze (flag, distinta, partita).
- Ogni write eseguita solo con tool dedicati e approvata dall'utente (pending
  action) nei casi sensibili.
- Gap tool dichiarati esplicitamente, mai aggirati.
- Riferimenti KB citati per regole/config non banali.
