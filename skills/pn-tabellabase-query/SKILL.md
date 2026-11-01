---
name: pn-tabellabase-query
description: >-
  Procedura obbligatoria per leggere dati da qualsiasi TabellaBase ProgestNOW con i tool
  pn_tabellabase_catalog, pn_tabellabase_descriptor, pn_tabellabase_list, pn_tabellabase_single,
  pn_tabellabase_aggregate, pn_tabellabase_list_view_create e pn_coge_partitario_search. Attivala
  PRIMA di cercare un record, elencare righe, filtrare per data o codice, calcolare totali, medie,
  conteggi o confronti tra periodi, estrarre dataset per Excel o sandbox, o creare una vista
  personalizzata delle colonne della lista. Evita gli errori piu costosi: filtri che ritornano 0 righe
  per nome campo sbagliato, liste grasse in contesto, paginazione a mano, sandbox usato per OR,
  ordinamenti, top N, duplicati o confronti tra campi che il search v2 fa da solo, freesql rifiutato.
---

> **Nel plugin (Claude, Codex).** Questa procedura nasce per il motore ProgestAI: dove differisce, vale questa nota.
> - `output=url` non va usato per scaricare dati: il tuo ambiente di esecuzione non raggiunge gli URL ProgestNOW. Restringi i filtri, aggrega lato server con `pn_tabellabase_aggregate`, oppure pagina con limiti piccoli; i calcoli locali li fai sui dati gia restituiti dai tool, nel tuo ambiente di esecuzione, al posto del "sandbox".
> - Questi tool qui non esistono: `pn_code_exec`, `pn_dataset_calculate`, `pn_dataset_merge`, `pn_excel_generate`, `pn_ai_delegate_job`, `pn_ai_job_complete`, `pn_ai_dataset_url_renew`. Se un passaggio li richiede, usa un equivalente disponibile (il tuo ambiente di esecuzione per calcoli e file, la chat per testi da inviare) oppure dichiara all'utente il limite; non inventare chiamate.

# TabellaBase: leggere, filtrare, aggregare

Le TabelleBase sono le liste configurate di ProgestNOW (anagrafiche, prima nota, documenti, viste `_qry*`). I tool `pn_tabellabase_*` le interrogano con i permessi dell'utente. Questa skill dice **quale tool usare, in che ordine, e come scrivere i filtri in modo che funzionino al primo colpo**.

Regola zero: **non leggere righe che una macchina puo aggregare.** Totali, conteggi, ranking e confronti si fanno con `pn_tabellabase_aggregate` o nel sandbox su un dataset esportato, mai leggendo pagine di record.

Regola uno: **mai `pn_tabellabase_list` con filtri ne' `pn_tabellabase_aggregate` su una TabellaBase di cui non hai letto il descriptor in questo job, salvo che una skill attiva ne indichi gia' i campi esatti.** Un nome campo indovinato costa un turno di errore e la rilettura del descriptor; leggerlo prima costa una chiamata, che puoi fare in parallelo con le altre.

## 1. Scegli il percorso (decision tree)

| Ti serve | Percorso | Mai |
|---|---|---|
| Non sai il nome tecnico della tabella (clienti, fornitori, articoli, impianti...) | `pn_tabellabase_catalog` (indice) → `pn_tabellabase_descriptor` della tabella scelta | indovinare il `table_name` |
| La scheda completa di poche tabelle note (sinonimi, decodifiche, trappole) | `pn_tabellabase_catalog` con `names=[...]` **oppure** `pn_tabellabase_descriptor` (campo `ai_instructions`) | `detail=full` su tutto il catalogo |
| Una riga o poche righe (lookup: "la causale X", "il sottoconto Y", "il cliente Z") | descriptor → `pn_tabellabase_list` con `search` mirato + `output_fields` 2-4 colonne + `page_size` ≤ 10 | lista senza filtri, `page_size` alto |
| Il dettaglio completo di UN record di cui conosci la chiave | `pn_tabellabase_single` | list filtrata sulla chiave |
| Ultimi / primi N record, il piu grande, il piu recente | descriptor → `pn_tabellabase_list` con `sort` + `page_size` N | `output=url` + ordinamento nel sandbox |
| Totali / medie / conteggi / ranking / per giorno-settimana-mese-trimestre-anno | descriptor → `pn_tabellabase_aggregate` con `search` + `dimensions` + `measures` (+ `date_buckets`) | list + somme "a mano" |
| Top N per totale (migliori clienti, articoli piu venduti) | `pn_tabellabase_aggregate` con `order_by` + `options.limit_groups` N | aggregare tutto e ordinare nel sandbox |
| Duplicati, gruppi sopra/sotto una soglia | `pn_tabellabase_aggregate` con `having` (es. `count > 1`) | sandbox |
| Confronto tra periodi (anno corrente vs precedente, dare/avere) in una tabella | `pn_tabellabase_aggregate` con misure condizionali `measures[].filter` | N chiamate + merge |
| Condizioni in OR, campo valorizzato, residui (qta evasa < ordinata), "ultimi 30 giorni" | `search` v2: `group_or`, `is_not_empty`, `field_number`, date relative (§4) | sandbox |
| Molte righe da elaborare (join tra tabelle, Excel, riconciliazioni, confronti riga per riga) | `pn_tabellabase_list` con **`output=url`** → `dataset_export_id` → `pn_code_exec` (Python) | paginare, incollare righe in chat |
| Righe del partitario contabile | `pn_coge_partitario_search` (stessa sintassi di list, `output=url` per estrazioni) | `pn_tabellabase_list` su `_partitario` senza descriptor |

### Il catalogo e a due livelli

`pn_tabellabase_catalog` di default **non** restituisce le schede complete: per ogni tabella ritorna `tabellabase_name`, `summary` (una riga), `weight` e `has_instructions`, ordinato per `weight` (importanza). Cosi l'indice resta piccolo anche con centinaia di tabelle.

- `has_instructions=true` significa che esiste una scheda ricca: vale la pena leggerla **prima** di costruire i filtri.
- Per la scheda completa di poche tabelle: `pn_tabellabase_catalog` con `names=["arccli","arcmovc"]` (max 30; forza il dettaglio completo e ignora `min_weight`).
- Per una sola tabella, su cui stai gia lavorando, la scheda arriva dal descriptor: `pn_tabellabase_descriptor(table_name)` include `ai_instructions` (e `ai_instructions_source`: `manual` o `auto`).
- `detail=full` sul catalogo restituisce tutte le schede in un colpo: usalo solo se serve davvero tutto.
- `weight=0` significa "fuori dal catalogo di default" (tabella dormiente o di servizio): la si trova con `min_weight=0` o chiedendola in `names`.

Se il risultato inline supera ~30 record o ~16k caratteri il server lo esporta da solo (`auto_export.applied=true`): la risposta contiene solo un'anteprima e un `dataset_export_id`. **Non richiedere le righe, non paginare**: usa il dataset o `aggregate`. Se vedi `_pn_truncated` il runtime ha tagliato il risultato: le parti omesse non esistono nel contesto, richiama con filtri piu stretti.

## 2. Procedura standard (sempre in quest'ordine)

1. **`pn_tabellabase_descriptor(table_name)`** (default `compact`), salvo che una skill attiva indichi gia' i campi esatti. Se la risposta ha `field_catalog.fields` (catalogo campi attivo) e' l'unica fonte dei nomi: righe `chiave|tipo|origine`; in `search`, `dimensions` e `measures` usa la chiave o l'origine; `fields` sono anche output, `filter_only` solo filtri, `not_filterable` solo output; gli operatori per tipo sono in `field_catalog.operators`; `aggregate_capability` compare solo se l'aggregate non e' supportato. Senza catalogo leggi `columns` (alias della lista), `output_fields_allowed` (gli unici nomi ammessi in `output_fields`), `single_fields` (campi fisici), `aggregate_capability.supported`.
2. **Leggi `ai_instructions`, se presente.** E la scheda della tabella: contiene i nomi fisici reali, i sinonimi, le decodifiche dei codici, i collegamenti e le trappole note del tenant. Vale piu di qualunque deduzione dal nome. Se manca e ti serve, prova `pn_tabellabase_catalog` con `names=[table_name]`.
3. **Decidi il nome campo per i filtri** (vedi §3: e la trappola numero uno). `ai_instructions` e `single_fields` vincono sull'alias di lista.
4. **Costruisci `search`** come array di oggetti `{field, op, type, value}`; i filtri sono in AND tra loro.
5. **Chiama il tool giusto** secondo il decision tree. Con `list` metti sempre `output_fields` e un `page_size` piccolo, oppure `output=url`.
6. **Verifica il risultato**: 0 righe con filtro su un valore che sai esistere = nome campo sbagliato (torna a §3), non "non ci sono dati".

## 3. Il nome del campo nel filtro (trappola numero uno)

Con `field_catalog` nel descriptor il problema e' risolto dal server: usa la chiave o l'origine di una riga del catalogo e il server la traduce nel riferimento SQL corretto, anche dentro `group_or`. Un errore `FIELD_UNKNOWN` o `FIELD_NOT_FILTERABLE` elenca i campi validi piu' simili: scegli tra quelli, non riprovare a indovinare. Il resto di questa sezione vale per le tabelle senza catalogo.

Il filtro `search` viene tradotto in `WHERE` sulla **query SQL della TabellaBase**. Quindi `field` deve essere:

- la **colonna fisica** della tabella/vista nel `FROM` della query, **non l'alias** mostrato nella lista;
- se qualificato, qualificato con il **nome della tabella/vista nel `FROM`**, che puo essere diverso dal `table_name`.

Esempio reale (`arcsott`, Sottoconti): la lista mostra la colonna `descrizione`, ma la query e `SELECT codice, descr as descrizione, ... FROM qrysottoconti`. Risultati misurati:

| `field` usato | Righe |
|---|---|
| `descrizione` (alias) | 0, nessun errore |
| `arcsott.descr` (qualificato con il table_name) | 0, nessun errore |
| `arcsott.codice` | 0, nessun errore |
| **`descr`** (colonna fisica, non qualificata) | corrette |

Come deciderlo senza tentativi:

- Se `ai_instructions` indica esplicitamente il campo fisico, usa quello.
- Se `columns[].field` e `single_fields[].name` coincidono per quel campo (es. `arcmovc`: `csott`, `datareg`, `caumovc`), usa quel nome; qualificalo con il `table_name` (`arcmovc.csott`) se la query ha join o il campo e ambiguo.
- Se differiscono (es. `descrizione` in `columns`, `descr` in `single_fields`), usa il nome di `single_fields` **non qualificato**.
- In caso di dubbio o di 0 righe inattese: `pn_tabellabase_descriptor(table_name, detail="full")` e leggi `dttable.query`: la `FROM` ti dice la sorgente reale, le espressioni `x as y` ti dicono che `y` e un alias da non usare nel filtro.

`output_fields` invece usa **gli alias** della lista (`output_fields_allowed`), non i nomi fisici. Nello stesso tool: filtro con `descr`, output con `descrizione`.

## 4. Sintassi dei filtri (contratto search v2)

Formato: `{"field": "...", "op": "...", "type": "...", "value": "..."}`. Stesso contratto per list, partitario, aggregate (anche `measures[].filter`) e missing_children. Dettaglio completo ed esempi in `references/filtri.md`.

| Caso | type | op | value | Note |
|---|---|---|---|---|
| Testo esatto | `string` | `=` | `X` | uguaglianza esatta, `%` e `_` letterali |
| Testo contiene / non contiene | `string` | `contains` / `not_contains` | `COLLAB` | senza `%` (alias `LIKE` / `NOT LIKE`) |
| Inizia / finisce per | `string` | `starts_with` / `ends_with` | `ART` | |
| Numero / id | `number` (o `int`) | `=`, `<>`, `>`, `>=`, `<`, `<=` | `190` | valore non numerico = errore |
| Intervallo | `number` / `date` | `between` | `01/01/2025,31/07/2025` | estremi inclusi |
| Data | `date` | confronti | `gg/mm/aaaa`, `aaaa-mm-gg`, `@today-30d` | date relative per i job pianificati |
| Uno tra N valori (IN) | `string` / `number` | `in` | `["AM","RI"]` o `AM,RI` | IN esatto |
| Nessuno tra N valori (NOT IN) | `string` / `number` | `not_in` | `AM,ex,RI` | un solo filtro |
| Campo vuoto / valorizzato | — | `is_empty` / `is_not_empty` | | |
| Confronto tra due campi | `field_number` / `field_date` / `field_string` | confronti | nome dell'altro campo | residui, ritardi |
| OR tra condizioni | `group_or` | — | `filters`: 2..10 filtri | un solo livello |
| Campo CSV multi-valore (`",3,7,"`) | `collection_or` | `=` / `<>` | `3,7` | solo per questi campi |

- Un filtro non valido torna `INVALID_SEARCH` con `path` e `hint`: **non viene mai ignorato**. Correggi il filtro indicato.
- La risposta contiene `search_effective`: controlla li i filtri applicati e le date relative risolte.
- `<>`, `not_in`, `not_contains` escludono anche le righe con il campo NULL; per includerle usa `group_or` con `is_empty`.
- Date `<` / `<=` includono le righe con data vuota (storico); `"nulls":"exclude"` le esclude.

**Vietato**: SQL nel valore, `freesql`, subquery, espressioni nei campi. Se un filtro non e esprimibile neanche con `group_or` / `field_*`, esporta con `output=url` e filtra nel sandbox.

### Ordinare la lista: `sort`

`pn_tabellabase_list` e `pn_coge_partitario_search` accettano `sort: [{"field": "datafattura", "dir": "desc"}]` (max 3). `field` e un alias di `output_fields_allowed` (come `output_fields`); le date sono ordinate per valore reale, i vuoti in fondo. Top N = `sort` + `page_size` N. Il link `urls.list` non riproduce l'ordinamento.

## 5. Aggregare: `pn_tabellabase_aggregate`

Server-side, autorevole su **tutti** i record che matchano (`scope: all_matching_records`), non sulla pagina. Prima verifica `aggregate_capability.supported=true` nel descriptor.

```json
{
  "table_name": "arcmovc",
  "search": [
    {"field": "arcmovc.csott", "op": "=", "type": "number", "value": "190"},
    {"field": "arcmovc.datareg", "op": "between", "type": "date", "value": "01/01/2025,31/07/2025"}
  ],
  "dimensions": ["arcmovc.caumovc"],
  "date_buckets": [{"name": "mese", "field": "arcmovc.datareg", "bucket": "month"}],
  "measures": [
    {"name": "tot_dare", "operation": "sum", "field": "impdare", "round": 2},
    {"name": "righe", "operation": "count"},
    {"name": "movimenti", "operation": "count_distinct", "field": "nmovc"}
  ],
  "options": {"limit_groups": 200}
}
```

- Le chiavi dei gruppi tornano come `tabella_campo` (`arcmovc_caumovc`) e con il `name` del bucket (`mese` = `2025-01`).
- `measures`: `sum|avg|min|max|count|count_distinct`, `field` obbligatorio tranne per `count`. Max 10 misure, 5 dimensioni, 3 bucket.
- `bucket`: `day` (`2025-01-31`), `week` (ISO, `2025-W05`), `month`, `quarter`, `year`.
- **Top N**: `"order_by": [{"name": "tot_dare", "dir": "desc"}]` + `"options": {"limit_groups": 10}` → i 10 gruppi maggiori, `truncated=true` se ce ne sono altri. `name` = misura, bucket o alias dimensione `tabella_campo`.
- **Soglie sulle misure / duplicati**: `"having": [{"name": "righe", "op": ">", "value": "1"}]` (solo nomi di misura, valore numerico, max 5 in AND).
- **Misure condizionali**: ogni misura puo avere `filter` (stesso contratto search) applicato solo a lei. Esempio anno corrente vs precedente per cliente in una chiamata:

```json
"measures": [
  {"name": "fatt_corr", "operation": "sum", "field": "imponibile", "filter": [{"field": "datafattura", "op": ">=", "type": "date", "value": "@start_of_year"}]},
  {"name": "fatt_prec", "operation": "sum", "field": "imponibile", "filter": [{"field": "datafattura", "op": "between", "type": "date", "value": "@start_of_year-1y,@today-1y"}]}
]
```

- Molti gruppi senza `order_by` → `TOO_MANY_GROUPS`: restringi, usa `order_by` per un top N oppure `output=url`. `limit_groups` max 1000.
- La misura ritorna come stringa decimale (`"…"`): non arrotondare mentalmente, riporta il valore.

## 6. Estrarre e lavorare per riferimento

`pn_tabellabase_list` con `output=url` ignora la paginazione ed esporta **tutto** il matching in un JSON su S3: ritorna `dataset_export_id` (`dsexp_...`), `url` (scade in ~20 minuti), `row_count`, `columns`. Poi:

- elaborazione: `pn_code_exec` (Python, `pandas.read_json(url)`); se l'URL e scaduto `pn_ai_dataset_url_renew(dataset_export_id)`;
- piu estrazioni da unire: `pn_dataset_merge`;
- somme sul dataset senza sandbox: `pn_dataset_calculate` con `source.type=dataset_export` (o `result_set`), max 10 misure; i `lookups` aggiungono colonne di un altro dataset usabili subito in `group_by`, `measures` e `order_by` della stessa chiamata; le date `0000-00-00` sono trattate come vuote;
- Excel: `pn_excel_generate` con `source.type=result_set` (mai copiare le righe in `records`);
- passaggio a un altro agente: `dataset_refs` in `pn_ai_delegate_job` / `pn_ai_job_complete`.

Usa `output_fields` anche con `output=url`: meno colonne = file piu piccolo e join piu semplice.

**Mai** incollare righe in conversazione, mai paginare per "vedere tutto", mai `page_size` 100 senza filtri stretti.

## 7. Prima nota e contabilita

Le tabelle contabili hanno pattern propri (partita doppia, causali, sottoconti clienti/fornitori). Se il task riguarda costi, ricavi, fornitori, clienti, scadenze o partitario leggi `references/prima-nota.md` prima di costruire le query.

## 8. Viste di lista personalizzate (colonne e raggruppamento)

Se l'utente chiede di vedere solo alcune colonne nella lista o di raggrupparla ("mostrami solo codice, ragione sociale e citta", "raggruppa per nazione"), usa `pn_tabellabase_list_view_create` e restituisci il link con `custom_dt_fields`. Quando usarla, come scegliere colonne e raggruppamento, come combinare con i filtri e le regole (mai costruire l'URL a mano, raggruppamento = tutte le righe) sono in `references/viste-lista.md`.

## 9. Errori e rimedi

Vedi `references/errori.md`. I piu frequenti: 0 righe con valore esistente (§3), `INVALID_SEARCH` (correggi il filtro in `path` seguendo `hint`), `freesql non ammesso` (§4), `INVALID_SORT` (usa un alias di `output_fields_allowed`), `DATASET_TOO_LARGE` (restringi i filtri o spezza per periodo), `DATASET_REF_NOT_FOUND`/`DATASET_GONE` (rigenera l'export), `aggregate_capability.supported=false` (usa `output=url` + sandbox).

## 10. Checklist prima di chiamare

- [ ] Ho letto il descriptor di **questa** tabella in **questo** job (o una skill attiva ne indica i campi esatti)?
- [ ] Ho letto `ai_instructions` (dal descriptor o da `catalog(names=[...])`), se `has_instructions=true`?
- [ ] I `field` dei filtri sono colonne fisiche della `FROM`, non alias di lista?
- [ ] Le date sono `gg/mm/aaaa`, `aaaa-mm-gg` o relative (`@today-30d`) nei job pianificati?
- [ ] Le esclusioni sono `not_in` (un filtro), non N filtri `<>` o `collection`?
- [ ] OR, "valorizzato", confronti tra campi, ordinamenti e top N li faccio con search v2 / `sort` / `order_by` / `having`, non nel sandbox?
- [ ] Se voglio un totale, sto usando `aggregate`?
- [ ] Se voglio molte righe, sto usando `output=url`?
- [ ] `output_fields` contiene solo chiavi di `field_catalog.fields`/`not_filterable` (con catalogo) o alias di `output_fields_allowed` (senza)?
