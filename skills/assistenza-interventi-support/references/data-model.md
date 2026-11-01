# Data model — interventi di assistenza

Evidenze di verifica sul tenant `progest` (db1, 2026-08-18): la tabella
`interventi` esiste con 379 righe; `interventi_stato` 5 righe; `manodopera`
12; `structures` 404; `interventi_tipo`/`tipo1`/`tipo2` e `autoveicoli` 0
righe. Le tabelle di CAP-20260812-032 (`testacommesse_interventi`,
`interventi_checklists*`) NON esistono su questo tenant.

Fonte canonica: DATA-INTV-001..008, DATA-TCI-001..005 (Knowledge MCP).

## CAP-20260811-007 — TabellaBase `interventi`

### Campi chiave (da QRY-INTV-001/002)

| Campo | Semantica | Note |
|---|---|---|
| `id` | id intervento | PK |
| `dataintervento` | data intervento | formato date; la lista formatta dd-mm-YYYY e usa `dataintervento_eng` per l'ordinamento |
| `orario`, `fineintervento` | orari inizio/fine | |
| `idimpianto` | impianto | → `structures.id` (decodifica lista); semantica DA CONFERMARE vs `structures_subscriptions.id` nel flusso documento (FIND-INTV-003) |
| `idmanodopera` | tecnico | → `manodopera.cidmanodopera`; obbligatorio in UI; può essere CSV in rami tenant |
| `statointervento` | stato | → `interventi_stato.codice`; default TODO su insert se vuoto (RULE-INTV-001) |
| `tipointervento` | tipologia | → `interventi_tipo.codice` |
| `nome`, `citta`, `indirizzo` | anagrafica luogo | autofill da `structures` su insert (RULE-INTV-003) |
| `lat`, `lng` | coordinate | geocodifica su insert (RULE-INTV-004); NON ricalcolate su update nel flusso standard |
| `father_id` | padre serie ricorrente | vuoto per i padri; popolato per le occorrenze |
| `recurrency` | config ricorrenza JSON | usata in insert (RULE-INTV-005) |
| `repeat_days` | config ricorrenza persistita | JSON; `limit.repeat_type=autocreate` = generazione differita |
| `structures_subscription_id` | collegamento subscription | se `idimpianto` vuoto, l'hook recupera `structure_id` (RULE-INTV-002) |
| `cidfattura` | documento collegato | affidabile SOLO ramo tenant `bene` (EXT-INTV-002) |

### Referenziali

| Tabella | Chiave | Campo display |
|---|---|---|
| `interventi_stato` | `codice` | `titolo` |
| `interventi_tipo` (+ `tipo1`, `tipo2`) | `codice` | `titolo` |
| `manodopera` | `cidmanodopera` | `cdescmanodopera` |
| `structures` | `id` | `name` (+ `city`, `address`, `cod_fatturazione`) |
| `autoveicoli` | — | veicolo assegnato (0 righe su progest) |

### Effetti server-side (hook postInsert, RULE-INTV-001..005)

Su `pn_tabellabase_new` per `interventi` il backend esegue, nell'ordine:
stato default TODO → recupero `idimpianto` da `structures_subscription_id` →
autofill nome/città/indirizzo da `structures` → geocodifica lat/lng →
generazione ricorrenze (occorrenze con `father_id`, nome "Ricorrente: ...",
stato TODO) se `recurrency` valorizzato.

Su update: nessun hook nel descrittore standard (preUpdate/postUpdate vuoti).

### Collegamento documento (RULE-INTV-009)

`testapiedefatture.intervento_id` ← valorizzato al salvataggio di un
documento aperto con `intervento_id`; cliente di fatturazione risolto da
`structures.cod_fatturazione` via `structures_subscriptions` solo se la
testata non ha già cliente.

## CAP-20260812-032 — Interventi su commessa (non installato su progest)

| Tabella | Semantica |
|---|---|
| `testacommesse_interventi` | riga intervento: `idcommessa` → `testacommesse.cidcommessa`, indirizzo, `checklist_id`, firma (`fine_signature_image_data`, `fine_signature_name`), `fine_data`/`fine_ora`, `stato` (DONE alla firma) |
| `testacommesse` | commessa: `cidcommessa`, `cdesccommessa`, `nidcliente` → `arccli.codice` |
| `interventi_checklists` / `_rows` | struttura checklist e voci |
| `interventi_checklists_rows_results` | risposte SI/NO/NA + note per intervento (delete-and-reinsert, RULE-TCI-004) |

Route dedicate (non esposte dal MCP): `/tabelle/testacommesse_interventi/scheda`,
`/salvachecklistrisposte`, `/{intervento_id}/firma`.
