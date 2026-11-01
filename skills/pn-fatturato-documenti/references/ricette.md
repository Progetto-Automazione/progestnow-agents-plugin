# Ricette fatturato (payload completi)

Tutte le ricette usano `pn_tabellabase_aggregate`; sintassi generale nella skill `pn-tabellabase-query`. Date in `gg/mm/aaaa`. Le date relative (`@start_of_month-1m` ecc.) vanno bene nei job pianificati.

## Come sono stati verificati i nomi

- Field catalog MCP di `progest` (spec 181) per `testapiedefatture`, `testapiedefatture_F`, `testapiedefatture_C`: `datafattura_eng` → `tpf.datafattura` (filtrabile, accetta anche `tpf.datafattura`); `datafattura` non filtrabile (e `DATE_FORMAT`, data formattata); `totaleimponibile`, `totaledocumento`, `codage`, `idcausale`, `idvaluta`, `cambio` → `tpf.<campo>`; su `testapiedefatture` `idcliente` → `tpf.idcliente`, su `_F`/`_C` il cliente e `codice_cliente` (`idcliente` non filtrabile).
- Query core: `FROM testapiedefatture tpf INNER JOIN causalimagazzino cm ... LEFT JOIN tabpag ... LEFT JOIN arccli`. Dimensioni e misure **qualificate** (`cm.tipocausale`, `arccli.nome`, `tpf.totaleimponibile`) passano anche se non sono nel catalogo; nei **filtri** `search` sono ammessi solo campi del catalogo (per questo `cm.tipocausale` si usa come dimensione, non come filtro).
- Pattern gia eseguito con successo su progest (job 875): `testapiedefatture`, filtro `tpf.datafattura` `gg/mm/aaaa`, dimensione `tpf.idcausale`, misure `count` e `sum tpf.totaleimponibile`, bucket mensile su `tpf.datafattura`.
- Risultati attesi ricalcolati con la stessa SQL che il tool genera (verifica read-only sul DB di tenant J).

Trappole sui filtri per codice causale (solo R4): usa `"op": "in", "type": "string"` con un array. **Mai** `"type": "collection"`: su progest (job 874) `idcausale` + `collection` ha restituito 0 documenti in un mese con 106 documenti.

## Se un campo della causale dà errore (strada secondaria)

Il catalogo campi MCP è attivo su progest e tenant J. `cm.tipocausale` non è nel catalogo, quindi come **filtro** viene rifiutato. Come dimensione qualificata passa, ma se una chiamata rispondesse `FIELD_UNKNOWN` o `FIELD_NOT_FILTERABLE` su `cm.tipocausale` o su un altro campo `cm.*`:

1. tieni il filtro `tpf.idcausale` `in` [causali F e C di R0];
2. sostituisci la dimensione `cm.tipocausale` con `tpf.idcausale`;
3. assegna ogni codice a F o C con l'elenco di `pn_document_types`, che restituisce `code` e `macro_type`;
4. somma F e C con `pn_dataset_calculate` o nel sandbox, non a mente.

Per un'altra condizione sulla causale non coperta da `pn_document_types`, leggi `causalimagazzino` con `pn_tabellabase_list` e filtra per i codici restituiti.

Filtri sempre con `"op": "in", "type": "string"` e un array. **Mai** `collection` / `collection_or`: hanno una semantica CSV con `LIKE` (`_` e `%` diventano jolly), e `collection` mette i valori in AND (job 874: 0 documenti).

## R0. Causali F e C (obbligatorio, una volta per job)

`pn_document_types(document_macro_type="F")` e `pn_document_types(document_macro_type="C")`: prendi **tutti** i `code`. Sono l'elenco del filtro `tpf.idcausale` `in` di R1, R2, R3 e R4. Negli esempi c'e l'elenco di tenant J (F: ND, NF, NFA, NFB, NFPA, NFPAS, NFS; C: NC, NCPA, NCPAS, NCS): **sostituiscilo** con quello del tenant.

Il filtro serve perche `testapiedefatture` contiene tutti i documenti (ordini, proforma, DDT...) e `cm.tipocausale` non e filtrabile (non e nel catalogo campi): solo cosi nel calcolo entrano esclusivamente F e C.

## R1. Fatturato di un periodo, con elenco causali

**Due chiamate** (Regola sui totali della SKILL.md):

- **chiamata 1, totale**: il payload qui sotto con `"dimensions": ["cm.tipocausale"]` soltanto. Restituisce due gruppi, F e C, ed e il totale da riportare;
- **chiamata 2, dettaglio**: lo stesso payload con `"dimensions": ["cm.tipocausale", "tpf.idcausale"]`. Serve all'elenco delle causali e al controllo "una sola causale". La somma dei suoi gruppi F e dei suoi gruppi C deve coincidere con la chiamata 1 entro 1 €.

Payload della chiamata 2:

```json
{
  "table_name": "testapiedefatture",
  "search": [
    {"field": "tpf.datafattura", "op": ">=", "type": "date", "value": "01/02/2026"},
    {"field": "tpf.datafattura", "op": "<=", "type": "date", "value": "28/02/2026", "nulls": "exclude"},
    {"field": "tpf.idcausale", "op": "in", "type": "string", "value": ["ND", "NF", "NFA", "NFB", "NFPA", "NFPAS", "NFS", "NC", "NCPA", "NCPAS", "NCS"]}
  ],
  "dimensions": ["cm.tipocausale", "tpf.idcausale"],
  "measures": [
    {"name": "documenti", "operation": "count"},
    {"name": "imponibile", "operation": "sum", "field": "tpf.totaleimponibile", "round": 2},
    {"name": "totale_documento", "operation": "sum", "field": "tpf.totaledocumento", "round": 2}
  ],
  "options": {"limit_groups": 300}
}
```


Il numero di documenti da riportare e il `count` dei gruppi F e C (863 e 32), mai `total_matching_records`. Qui coincide con 895 solo perche il `search` filtra le causali F e C: senza quel filtro conterebbe anche ordini, proforma e DDT del periodo.


F = …; C = …; **netto = …**. Lordo (solo se richiesto) = … − … = ….

## R2. Fatturato mensile, miglior mese

```json
{
  "table_name": "testapiedefatture",
  "search": [
    {"field": "tpf.datafattura", "op": ">=", "type": "date", "value": "01/01/2026"},
    {"field": "tpf.datafattura", "op": "<=", "type": "date", "value": "30/09/2026", "nulls": "exclude"},
    {"field": "tpf.idcausale", "op": "in", "type": "string", "value": ["ND", "NF", "NFA", "NFB", "NFPA", "NFPAS", "NFS", "NC", "NCPA", "NCPAS", "NCS"]}
  ],
  "dimensions": ["cm.tipocausale", "tpf.idcausale"],
  "date_buckets": [{"name": "mese", "field": "tpf.datafattura", "bucket": "month"}],
  "measures": [
    {"name": "documenti", "operation": "count"},
    {"name": "imponibile", "operation": "sum", "field": "tpf.totaleimponibile", "round": 2}
  ],
  "options": {"limit_groups": 1000}
}
```

Questa e la chiamata di **dettaglio**. Il totale del periodo si prende da R1 chiamata 1 (stesso intervallo, solo `cm.tipocausale`), non dalla somma dei mesi. La somma dei mesi va fatta con `pn_dataset_calculate` o nel sandbox e deve coincidere con il totale entro 1 €.

La dimensione `tpf.idcausale` serve al controllo "una sola causale" (§5 della SKILL.md). Con `TOO_MANY_GROUPS` toglila e rilancia solo sul mese anomalo.


Miglior mese: settembre 2026 (…). Nessun mese a zero. Il "miglior mese" si decide sul **netto**, non sulle sole F.

### Confronto tra periodi in una chiamata

Misure condizionali sulla data, stessa base (anno corrente vs precedente, fino alla stessa data):

```json
{
  "table_name": "testapiedefatture",
  "search": [
    {"field": "tpf.datafattura", "op": ">=", "type": "date", "value": "@start_of_year-1y"},
    {"field": "tpf.datafattura", "op": "<=", "type": "date", "value": "@today", "nulls": "exclude"},
    {"field": "tpf.idcausale", "op": "in", "type": "string", "value": ["ND", "NF", "NFA", "NFB", "NFPA", "NFPAS", "NFS", "NC", "NCPA", "NCPAS", "NCS"]}
  ],
  "dimensions": ["cm.tipocausale"],
  "measures": [
    {"name": "imp_corrente", "operation": "sum", "field": "tpf.totaleimponibile", "round": 2,
     "filter": [{"field": "tpf.datafattura", "op": ">=", "type": "date", "value": "@start_of_year"}]},
    {"name": "imp_precedente", "operation": "sum", "field": "tpf.totaleimponibile", "round": 2,
     "filter": [{"field": "tpf.datafattura", "op": "between", "type": "date", "value": "@start_of_year-1y,@today-1y"}]}
  ],
  "options": {"limit_groups": 50}
}
```

Netto per periodo = misura del gruppo F − misura del gruppo C.

## R3. Per agente

```json
{
  "table_name": "testapiedefatture",
  "search": [
    {"field": "tpf.datafattura", "op": ">=", "type": "date", "value": "01/01/2026"},
    {"field": "tpf.datafattura", "op": "<=", "type": "date", "value": "30/09/2026", "nulls": "exclude"},
    {"field": "tpf.idcausale", "op": "in", "type": "string", "value": ["ND", "NF", "NFA", "NFB", "NFPA", "NFPAS", "NFS", "NC", "NCPA", "NCPAS", "NCS"]}
  ],
  "dimensions": ["tpf.codage", "cm.tipocausale"],
  "measures": [
    {"name": "documenti", "operation": "count"},
    {"name": "imponibile", "operation": "sum", "field": "tpf.totaleimponibile", "round": 2}
  ],
  "options": {"limit_groups": 1000}
}
```

Il totale si riporta da R1 chiamata 1 (stesso periodo); la somma degli agenti, calcolata con `pn_dataset_calculate` o nel sandbox, deve coincidere con il totale entro 1 €. Netto per agente = F − C sullo stesso `tpf_codage`. `tpf_codage` vuoto = documenti senza agente: riportali come riga a parte. Nomi agenti: `pn_tabellabase_list` su `agenti` con filtro `idagente` `in` i codici trovati, `output_fields` `idagente`, `nome`.

## R4. Per cliente / top clienti

I clienti sono migliaia (tenant J: 3.986 nel 2026): `cm.tipocausale` come dimensione supererebbe `limit_groups`. Serve un top N con misure condizionali sulle causali.

1. Causali F e C da R0: **tutte**, non un sottoinsieme.
2. Aggregate (esempio tenant J; sostituisci gli elenchi con quelli del tenant):

```json
{
  "table_name": "testapiedefatture",
  "search": [
    {"field": "tpf.datafattura", "op": ">=", "type": "date", "value": "01/02/2026"},
    {"field": "tpf.datafattura", "op": "<=", "type": "date", "value": "28/02/2026", "nulls": "exclude"},
    {"field": "tpf.idcausale", "op": "in", "type": "string", "value": ["ND", "NF", "NFA", "NFB", "NFPA", "NFPAS", "NFS", "NC", "NCPA", "NCPAS", "NCS"]}
  ],
  "dimensions": ["tpf.idcliente", "arccli.nome"],
  "measures": [
    {"name": "fatture", "operation": "sum", "field": "tpf.totaleimponibile", "round": 2,
     "filter": [{"field": "tpf.idcausale", "op": "in", "type": "string", "value": ["ND", "NF", "NFA", "NFB", "NFPA", "NFPAS", "NFS"]}]},
    {"name": "note_credito", "operation": "sum", "field": "tpf.totaleimponibile", "round": 2,
     "filter": [{"field": "tpf.idcausale", "op": "in", "type": "string", "value": ["NC", "NCPA", "NCPAS", "NCS"]}]},
    {"name": "documenti", "operation": "count"}
  ],
  "order_by": [{"name": "fatture", "dir": "desc"}],
  "options": {"limit_groups": 30}
}
```

3. Netto per cliente = `fatture` − `note_credito` (null = 0); riordina per netto e riporta i primi N richiesti. Il top per `fatture` puo escludere un cliente con forti note di credito solo in casi limite: con `limit_groups` 30 per un top 10 il margine basta.


Se `arccli.nome` da errore (query del tenant senza join `arccli`), toglilo e leggi i nomi con `pn_tabellabase_list` su `arccli` (`codice` `in` [...], `output_fields` `codice`, `nome`).

Fatturato di **un** cliente: R1 chiamata 1 con un filtro in piu `{"field": "tpf.idcliente", "op": "=", "type": "number", "value": "<codice>"}`. Il filtro sulle causali F e C resta.

## R5. Per articolo, famiglia, categoria

`qrystatistichedocumenti`: una riga per riga di documento, nessun join. Usa `riga_importototale` (non firmato) con misure condizionali sulla tipologia: evita il segno di `segno_statistica`, configurato in modo incoerente tra tenant.

```json
{
  "table_name": "qrystatistichedocumenti",
  "search": [
    {"field": "testa_anno", "op": "=", "type": "string", "value": "2026"},
    {"field": "testa_mese", "op": "between", "type": "number", "value": "1,9"},
    {"field": "testa_causale_tipo", "op": "in", "type": "string", "value": ["F", "C"]}
  ],
  "dimensions": ["riga_articolo_idmagazzino"],
  "measures": [
    {"name": "venduto_f", "operation": "sum", "field": "riga_importototale", "round": 2,
     "filter": [{"field": "testa_causale_tipo", "op": "=", "type": "string", "value": "F"}]},
    {"name": "resi_c", "operation": "sum", "field": "riga_importototale", "round": 2,
     "filter": [{"field": "testa_causale_tipo", "op": "=", "type": "string", "value": "C"}]},
    {"name": "quantita_f", "operation": "sum", "field": "riga_doc_quantita", "round": 2,
     "filter": [{"field": "testa_causale_tipo", "op": "=", "type": "string", "value": "F"}]}
  ],
  "order_by": [{"name": "venduto_f", "dir": "desc"}],
  "options": {"limit_groups": 30}
}
```

- Netto per articolo = `venduto_f` − `resi_c`. Per famiglia o categoria usa come dimensione `riga_articolo_tipologia_descrizione`, `riga_articolo_categoria_descrizione`, `riga_articolo_reparto_descrizione` o `riga_articolo_marca_descr`.
- Descrizioni articolo: `pn_tabellabase_list` su `articoli` per i codici trovati.
- Numero documenti: `count_distinct` su `testa_cidfattura`, mai `count` (conta le righe).
- **Mai sommare `piede_*`**: sono ripetuti su ogni riga (tenant J, febbraio, NFS: `piede_totali_imponibile_stat` = … contro … reali). I `piede_*` si leggono solo con un documento per riga.
- Le spese di piede (trasporto, bancarie) e gli sconti di piede non sono nelle righe: dichiaralo. Controllo incrociato su tenant J, febbraio 2026: righe F … e righe C …, identiche all'imponibile di testata; su gennaio-settembre le righe F danno … contro … di testata (18,00 di spese di piede).
- Alternativa: `qrystampafattura` (righe, campi `importototale` e `tipocausale`), stesso schema F − C.

## R6. Fallback se `testapiedefatture` non e aggregabile

Se R1 risponde `UNSUPPORTED_QUERY_SHAPE`, `AGGREGATE_SQL_ERROR` o "campo ambiguo":

1. `pn_tabellabase_descriptor("testapiedefatture_F")` e `("testapiedefatture_C")`: se `dttable.group_by` e vuoto, due aggregate con lo stesso `search` su `tpf.datafattura` e le stesse dimensioni (`date_buckets` mensile, `codice_cliente` per il cliente, `codage`), misure `sum totaleimponibile` e `count`; netto = F − C per gruppo. Queste due viste filtrano gia `cm.tipocausale` = F o C.
2. Altrimenti R5 senza dimensione articolo (righe di `qrystatistichedocumenti`), dichiarando che le spese di piede sono escluse.
3. Mai ripiegare su una lista di documenti sommata a mano, ne su `pn_code_exec` con migliaia di righe, ne su un filtro per singola causale.

## Calcolo F − C e arrotondamenti

- Le misure tornano come stringhe decimali (`"…"`): sottrai con due decimali e non arrotondare prima.
- Una tipologia assente nel gruppo vale 0 (nessuna riga C = nessuna nota di credito).
- Riporta F, C e netto sempre insieme: il netto da solo non permette all'utente di controllare.
