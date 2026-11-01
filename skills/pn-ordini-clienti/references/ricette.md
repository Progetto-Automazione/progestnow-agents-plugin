# Ricette ordini clienti (payload completi)

Sintassi generale: skill `pn-tabellabase-query`. Date `gg/mm/aaaa` o relative (`@today`).

## Come sono stati verificati

- Filtri di tutte le ricette validati con il contratto search v2 (`TabellaBaseSearchContract::parse`).
- `qrystatistichedocumenti`: colonne fisiche di una vista senza join nella `FROM` della TabellaBase, quindi nomi **non qualificati**. Definizione della vista letta su progest: `riga_quantitadaevadere` = formula del residuo, `testa_evaso` = `qryordevasi.evaso`, `piede_tipologia_codice`/`descrizione` = `nidtipologiaordine` + `tipologieordine`.
- `qrystampafattura`: field catalog di progest (`tipocausale`, `quantita`, `quantitaevasa`, `levasioneasaldo`, `nidtipologiaordine`, `codage`, `idcliente`, `dataconsegna`, `importototale`, `idriga` filtrabili; `qtaresidua` calcolato, non filtrabile ma esportabile). `output_fields` presi da `tableColumns_new` del descriptor core.
- Valori attesi ricalcolati read-only su progest e tenant B il 2026-10-10 con la stessa logica.

Prima di usare una ricetta su un tenant nuovo leggi il descriptor della TabellaBase (`pn_tabellabase_descriptor`): se un campo non c'è, il tenant ha una versione personalizzata.

## Se un campo della causale dà errore (strada secondaria)

Dove il catalogo campi MCP è attivo (es. progest, bene), i filtri `search` accettano solo i campi del catalogo. I campi della causale in join (`cm.tipocausale`, `cm.flagidcliente_idfornitore`) spesso mancano e la chiamata risponde `FIELD_UNKNOWN` o `FIELD_NOT_FILTERABLE`. Può succedere anche a `testa_causale_tipo` / `tipocausale` sulle viste di riga.

Se succede:

1. prendi le causali O con `pn_document_types(document_macro_type="O")`. Per condizioni che `pn_document_types` non espone (flag, `no_evasione`), leggi `causalimagazzino` con `pn_tabellabase_list`, e se anche quel filtro fallisce leggila tutta;
2. rilancia la chiamata con il filtro sul codice causale:

   | Tabella | Filtro |
   |---|---|
   | `testapiedefatture` | `{"field": "tpf.idcausale", "op": "in", "type": "string", "value": [codici]}` |
   | `qrystatistichedocumenti` | `testa_causale_codice` |
   | `qrystampafattura` | `idcausale` |
3. se a fallire era una **dimensione** sulla causale, raggruppa per il codice causale e riconduci ogni codice alla sua tipologia.

Usa sempre `in` + `string` con un array. **Mai** `collection` / `collection_or`: hanno una semantica CSV con `LIKE`, e `collection` mette i valori in AND (job 874: 0 documenti).

## R1. Configurazione del tenant

a) Causali d'ordine non soggette a evasione:

```json
{
  "table_name": "causalimagazzino",
  "search": [
    {"field": "tipocausale", "op": "=", "type": "string", "value": "O"},
    {"field": "no_evasione", "op": "=", "type": "number", "value": "1"}
  ],
  "output_fields": ["idcausale", "descrizione", "tipocausale"],
  "page_size": 50
}
```

0 righe = nessuna causale esclusa. Se il filtro `no_evasione` dà `FIELD_UNKNOWN`, dichiara che il flag non è verificabile con i tool. Le causali O del tenant: `pn_document_types(document_macro_type="O")`.

b) Stati ordine (tabella piccola, leggila tutta):

```json
{
  "table_name": "tipologieordine",
  "search": [],
  "output_fields": ["nidtipologiaordine", "cdesctipologiaordine", "cbloccato", "cbloccaproduzione", "tipocausale"],
  "page_size": 100
}
```

`tipocausale` è un elenco delle tipologie a cui si applica lo stato ("O", "T,O", "P,O"; vuoto = tutte). Tieni quelli che contengono O o vuoti. Stati di annullamento: descrizione con ANNULL, CANCELL, ELIMIN, RIFIUT, STORN. In dubbio su altri stati terminali (FATTURATA, CHIUSO, NON FATTURARE): chiedi. Esempio tenant B: `3` ANNULLATO, `24` FATTURATA, `22` NON FATTURARE, `20` REINTEGRO, `21` SOSTITUZIONE. Su progest `0` = nessuno stato.

## R2. Portafoglio per stato e causale

```json
{
  "table_name": "qrystatistichedocumenti",
  "search": [
    {"field": "testa_causale_tipo", "op": "=", "type": "string", "value": "O"}
  ],
  "dimensions": ["piede_tipologia_codice", "piede_tipologia_descrizione", "testa_evaso", "testa_causale_codice"],
  "measures": [
    {"name": "ordini", "operation": "count_distinct", "field": "testa_cidfattura"},
    {"name": "ordini_aperti", "operation": "count_distinct", "field": "testa_cidfattura",
     "filter": [{"field": "riga_quantitadaevadere", "op": ">", "type": "number", "value": "0"}]},
    {"name": "ordini_con_evasioni", "operation": "count_distinct", "field": "testa_cidfattura",
     "filter": [{"field": "riga_quantitaevasa", "op": ">", "type": "number", "value": "0"}]},
    {"name": "righe_aperte", "operation": "count",
     "filter": [{"field": "riga_quantitadaevadere", "op": ">", "type": "number", "value": "0"}]},
    {"name": "qta_ordinata", "operation": "sum", "field": "riga_quantita", "round": 2},
    {"name": "qta_evasa", "operation": "sum", "field": "riga_quantitaevasa", "round": 2},
    {"name": "qta_residua", "operation": "sum", "field": "riga_quantitadaevadere", "round": 2},
    {"name": "righe_oltre_ordinato", "operation": "count",
     "filter": [{"field": "riga_quantitaevasa", "op": ">", "type": "field_number", "value": "riga_quantita"}]}
  ],
  "options": {"limit_groups": 500}
}
```

- **Totale prima, dettaglio poi**: per i totali lancia questa chiamata senza `dimensions` (un gruppo); quella con le dimensioni è il dettaglio e deve quadrare. Numero di ordini = `ordini` / `ordini_aperti` (`count_distinct`), mai `total_matching_records`, che su questa vista conta le righe.
- Nei gruppi con `testa_evaso = N` (sempre aperti), `ordini_con_evasioni` = **parzialmente evasi**. Con `P` (tenant J, tenant C) usa `ordini_aperti` e `ordini_con_evasioni` dello stesso gruppo e dichiaralo.
- Gruppo con `testa_evaso` nullo e `qta_ordinata` nulla = **ordini senza righe**.
- Per un periodo di emissione aggiungi `{"field": "testa_anno", "op": "=", "type": "string", "value": "2026"}` e, se serve, `testa_mese` (`between`, `number`). Per mese aggiungi `testa_anno` e `testa_mese` alle dimensioni.



## R3. Per agente (con "senza agente")

```json
{
  "table_name": "qrystatistichedocumenti",
  "search": [
    {"field": "testa_causale_tipo", "op": "=", "type": "string", "value": "O"},
    {"field": "riga_quantitadaevadere", "op": ">", "type": "number", "value": "0"},
    {"type": "group_or", "filters": [
      {"field": "piede_tipologia_codice", "op": "not_in", "type": "number", "value": ["3"]},
      {"field": "piede_tipologia_codice", "op": "is_empty"}
    ]}
  ],
  "dimensions": ["testa_agente_codice", "testa_agente_nome"],
  "measures": [
    {"name": "ordini_aperti", "operation": "count_distinct", "field": "testa_cidfattura"},
    {"name": "righe_aperte", "operation": "count"},
    {"name": "qta_residua", "operation": "sum", "field": "riga_quantitadaevadere", "round": 2}
  ],
  "order_by": [{"name": "ordini_aperti", "dir": "desc"}],
  "options": {"limit_groups": 200}
}
```

- `["3"]` = id degli stati da escludere letti in R1 (qui ANNULLATO di tenant B). Senza stati da escludere togli il `group_or`.
- Il gruppo con `testa_agente_codice` vuoto o nullo è "senza agente": riportalo sempre come riga e calcola la sua quota sul totale degli ordini aperti.
- Valore per agente: R5.


## R4. Per cliente (conteggi)

Come R3 con `"dimensions": ["testa_cliente_codice", "testa_clifor_nome"]`, `order_by` su `ordini_aperti` e `limit_groups` 30 per un top. Le quantità di articoli diversi non si sommano in modo significativo: per un top clienti **per valore** usa R5.

## R5. Valore del backlog (export + sandbox)

1. Export delle righe aperte (gli ordini in stato escluso si filtrano già qui):

```json
{
  "table_name": "qrystampafattura",
  "search": [
    {"field": "tipocausale", "op": "=", "type": "string", "value": "O"},
    {"field": "quantitaevasa", "op": "<", "type": "field_number", "value": "quantita"},
    {"type": "group_or", "filters": [
      {"field": "levasioneasaldo", "op": "<>", "type": "string", "value": "S"},
      {"field": "levasioneasaldo", "op": "is_empty"}
    ]},
    {"type": "group_or", "filters": [
      {"field": "nidtipologiaordine", "op": "not_in", "type": "number", "value": ["3"]},
      {"field": "nidtipologiaordine", "op": "is_empty"}
    ]}
  ],
  "output_fields": ["cidfattura", "numerofattura", "datafattura", "idcausale", "idcliente", "nome", "codage", "idriga", "idmagazzino", "descrizionearticolo", "quantita", "quantitaevasa", "qtaresidua", "levasioneasaldo", "importototale", "dataconsegna"],
  "output": "url"
}
```

2. Nel sandbox (`pn_code_exec`, `pandas.read_json(url)`):

```python
df = df.drop_duplicates(subset="idriga")          # la query fa join con lotti: possibili doppioni
df = df[(df.quantita > 0) & (df.qtaresidua > 0)]
df["valore_residuo"] = df.qtaresidua * df.importototale / df.quantita
totale = df.valore_residuo.sum()
per_cliente = df.groupby(["idcliente", "nome"]).valore_residuo.sum().sort_values(ascending=False)
per_agente = df.assign(codage=df.codage.fillna("").replace("", "(senza agente)")).groupby("codage").valore_residuo.sum()
ordini_aperti = df.cidfattura.nunique()
```


## R6. Consegne in ritardo

```json
{
  "table_name": "qrystatistichedocumenti",
  "search": [
    {"field": "testa_causale_tipo", "op": "=", "type": "string", "value": "O"},
    {"field": "riga_quantitadaevadere", "op": ">", "type": "number", "value": "0"},
    {"type": "group_or", "filters": [
      {"field": "piede_tipologia_codice", "op": "not_in", "type": "number", "value": ["3"]},
      {"field": "piede_tipologia_codice", "op": "is_empty"}
    ]}
  ],
  "dimensions": ["testa_cliente_codice", "testa_clifor_nome"],
  "measures": [
    {"name": "righe_aperte", "operation": "count"},
    {"name": "righe_senza_data", "operation": "count",
     "filter": [{"type": "group_or", "filters": [
       {"field": "riga_dataconsegna", "op": "is_empty"},
       {"field": "riga_dataconsegna", "op": "<", "type": "date", "value": "02/01/1900", "nulls": "exclude"}
     ]}]},
    {"name": "righe_in_ritardo", "operation": "count",
     "filter": [
       {"field": "riga_dataconsegna", "op": ">=", "type": "date", "value": "02/01/1900"},
       {"field": "riga_dataconsegna", "op": "<", "type": "date", "value": "@today", "nulls": "exclude"}
     ]},
    {"name": "ordini_in_ritardo", "operation": "count_distinct", "field": "testa_cidfattura",
     "filter": [
       {"field": "riga_dataconsegna", "op": ">=", "type": "date", "value": "02/01/1900"},
       {"field": "riga_dataconsegna", "op": "<", "type": "date", "value": "@today", "nulls": "exclude"}
     ]},
    {"name": "qta_in_ritardo", "operation": "sum", "field": "riga_quantitadaevadere", "round": 2,
     "filter": [
       {"field": "riga_dataconsegna", "op": ">=", "type": "date", "value": "02/01/1900"},
       {"field": "riga_dataconsegna", "op": "<", "type": "date", "value": "@today", "nulls": "exclude"}
     ]}
  ],
  "order_by": [{"name": "righe_in_ritardo", "dir": "desc"}],
  "options": {"limit_groups": 50}
}
```

- Senza dimensioni ottieni i totali. Il filtro `>= 02/01/1900` esclude le date nulle "0000-00-00", che altrimenti risulterebbero in ritardo.
- Riporta sempre `righe_senza_data` / `righe_aperte`: se la quota è alta, il ritardo è calcolato su una minoranza delle righe.
- Giorni di ritardo, elenco righe: export come R5 con filtro `dataconsegna` < `@today` e calcolo nel sandbox.


## R7. Singolo ordine

1. Testata: `pn_document_read(document_code="<cidfattura>")` oppure `pn_tabellabase_single` su `testapiedefatture_O`: stato (`tipologia_ordine`), `evaso`, `descrizione_stato`, `perc_evasione` se esposti dal descriptor del tenant, `n_doc_orig` (offerta d'origine), `codage`, `datafattura`.
2. Righe e residui: `pn_document_evadable_rows(source_document_codes=["<cidfattura>"], include_closed="yes")` se l'agente lo ha; altrimenti

```json
{
  "table_name": "qrystampafattura",
  "search": [{"field": "cidfattura", "op": "=", "type": "string", "value": "ORCLI2026294"}],
  "output_fields": ["numeroriga", "idriga", "idmagazzino", "descrizionearticolo", "quantita", "quantitaevasa", "qtaresidua", "levasioneasaldo", "importototale", "dataconsegna"],
  "sort": [{"field": "numeroriga", "dir": "asc"}],
  "page_size": 200
}
```

3. Chi ha evaso: `pn_document_linked_documents(document_code="<cidfattura>")`. Mostra DDT (D) e fatture (F) come evasori, distingui le fatture che evadono **tramite DDT** (`invoice_evades_source_document_through_ddt`) e cita i documenti interni (I) come collegamenti, non come evasioni. **Non sommare** le quantità dei documenti collegati per ricalcolare l'evasione.
4. Offerta d'origine: `n_doc_orig` → `pn_document_read` dell'offerta (dettaglio commerciale: skill `pn-offerte-crm`).

## R8. Ordinato del periodo

```json
{
  "table_name": "testapiedefatture",
  "search": [
    {"field": "tpf.datafattura", "op": ">=", "type": "date", "value": "01/01/2026"},
    {"field": "tpf.datafattura", "op": "<=", "type": "date", "value": "30/09/2026", "nulls": "exclude"},
    {"field": "tpf.idcausale", "op": "in", "type": "string", "value": ["ORCLI"]}
  ],
  "dimensions": ["cm.tipocausale", "tpf.nidtipologiaordine"],
  "measures": [
    {"name": "ordini", "operation": "count"},
    {"name": "ordinato", "operation": "sum", "field": "tpf.totaleimponibile", "round": 2}
  ],
  "options": {"limit_groups": 300}
}
```

- `["ORCLI"]` è l'elenco di tenant B: sostituiscilo con **tutte** le causali O del tenant, da `pn_document_types(document_macro_type="O")`. Senza questo filtro `testapiedefatture` restituisce tutti i documenti del periodo (fatture, DDT, ordini fornitore…), e `cm.tipocausale` non si può usare come filtro perché non è nel catalogo campi.
- **Totale e dettaglio**: il totale si legge da una chiamata con `"dimensions": ["cm.tipocausale"]` soltanto, che dà un solo gruppo O; il dettaglio per stato (come sopra), mese o agente è una seconda chiamata, che deve quadrare con il totale entro 1 €.
- **Numero di ordini** = misura `ordini` del gruppo O, mai `total_matching_records`.
- Togli gli stati di annullamento e dichiaralo. Per mese aggiungi `"date_buckets": [{"name": "mese", "field": "tpf.datafattura", "bucket": "month"}]`; per agente `tpf.codage`. Se il descriptor di `testapiedefatture_O` del tenant non ha `group_by`, puoi usare quella (filtra già O).

