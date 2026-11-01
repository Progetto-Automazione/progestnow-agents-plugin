# Offerte e pipeline: ricette operative

Tutte le ricette presuppongono:

- il descriptor `testapiedefatture_R` letto in questo job, con query `FROM testapiedefatture tpf` (verificata su progest: core e override hanno la stessa query; vedi `modello-dati.md` §1);
- gli id di stato letti da `leads_statuses` del tenant;
- il filtro `tpf.idcausale` `in` [causali con flag C] in **ogni** `search`: le causali R su `testapiedefatture_R`, le O su `testapiedefatture_O` (elenchi da R0). La tipologia R comprende anche le richieste di offerta a fornitore (tenant A: `RICHO`, flag `F`) e la tipologia O gli ordini a fornitore: senza il filtro finiscono nella pipeline e nella conversione. Negli esempi gli elenchi sono quelli di progest (`["OFF"]`, `["ORCLI"]`): sostituiscili con quelli del tenant.
- **mai** `cm.flagidcliente_idfornitore` come filtro. Non è nel catalogo campi: dove il catalogo è attivo (progest, bene) la chiamata viene rifiutata con `FIELD_UNKNOWN` (verificato sul catalogo di progest per `testapiedefatture_R`). Come dimensione invece funziona, perché i campi qualificati passano;
- i totali si leggono dalla prima chiamata, e il numero di offerte dal `count` dei gruppi, mai da `total_matching_records` (Regola sui totali, SKILL.md §3).

Negli esempi gli id sono quelli di progest: `1` Aperto, `2` Chiuso Positivo, `3` Chiuso Negativo, `4` On hold. Su un altro tenant sostituiscili con quelli letti. Sintassi: skill `pn-tabellabase-query`.

Note valide per tutte le ricette:

- `field` / `dimensions` / `date_buckets` → `tpf.<colonna fisica>`; `output_fields` / `sort` → alias di lista (`datafattura` = stringa `gg-mm-aaaa`, `leads_status`, `leads_funnel_status`, `leads_conversion_score`, `operatore_username`).
- Le chiavi dei gruppi tornano come `tabella_campo`: `tpf_leads_status_code`, `leads_statuses_description`, `tpf_codage`, ecc.
- I numeri "atteso su progest" sono il risultato SQL equivalente, eseguito read-only su `progest` il 2026-10-10 sulle offerte con `datafattura` ≥ 2025-01-01. Servono per controllare la plausibilità, non sono valori da riportare.

## Se un campo della causale dà errore (strada secondaria)

Dove il catalogo campi MCP è attivo (progest, bene), i filtri accettano solo i campi del catalogo. `cm.flagidcliente_idfornitore`, `cm.tipocausale` e gli altri campi della causale in join possono mancare: la chiamata risponde `FIELD_UNKNOWN` o `FIELD_NOT_FILTERABLE`. Di solito le dimensioni qualificate passano lo stesso, ma non è garantito.

Se succede:

1. leggi le causali con R0a. Se anche il filtro su `causalimagazzino.tipocausale` desse errore, togli il `search` e filtra l'elenco completo, che è di poche decine di righe;
2. tieni i codici che soddisfano la condizione (es. tipologia R con flag C);
3. rilancia la chiamata con `{"field": "tpf.idcausale", "op": "in", "type": "string", "value": [codici]}` al posto del filtro sulla causale;
4. se a fallire era una **dimensione** (`cm.idcausale`, `cm.flagidcliente_idfornitore`), raggruppa per `tpf.idcausale` e riconduci ogni codice a tipologia e flag con l'elenco del passo 1.

Usa sempre `in` + `string` con un array. **Mai** `collection` / `collection_or`: hanno una semantica CSV con `LIKE` (`_` e `%` diventano jolly), e `collection` mette i valori in AND (su progest, job 874, ha restituito 0 documenti).

## R0. Causali e decodifiche (sempre, una volta per job)

**a) Causali R e O con il flag**, con `pn_tabellabase_list`:

```json
{"table_name": "causalimagazzino",
 "search": [{"field": "causalimagazzino.tipocausale", "op": "in", "type": "string", "value": ["R", "O"]}],
 "output_fields": ["idcausale", "descrizione", "tipocausale", "flagidcliente_idfornitore"],
 "page_size": 100}
```

- Da qui ricavi gli elenchi delle **causali R con flag C** (le offerte) e delle **causali O con flag C** (gli ordini cliente).
- `pn_document_types` non restituisce il flag: non basta.

**b) Decodifiche**: tre `pn_tabellabase_list`, senza filtri e con `page_size` 50 (sono tabelle di poche righe):

| table_name | output_fields |
|---|---|
| `leads_statuses` | `id`, `description`, `show_in_kanban`, `ordering` |
| `leads_funnel_statuses` | `code`, `title`, `ordering`, `kanban_exclude`, `leads_statuses_id` |
| `leads_conversion_score` | `code`, `title`, `percentage`, `is_default` |

Se queste TabelleBase non hanno colonne di lista, `output_fields_allowed` può essere vuoto: in quel caso ometti `output_fields`. In alternativa usa `pn_document_offer_crm_options`.

Da qui ricavi:

- id di Aperto, Chiuso Positivo, Chiuso Negativo, On hold;
- se esiste almeno una `percentage > 0` (pipeline pesata ammessa);
- l'elenco dei codici fase validi, per riconoscere le fasi orfane in R7.

## R1. Pipeline per stato, con attive / ferme / senza data

`pn_tabellabase_aggregate`:

```json
{
  "table_name": "testapiedefatture_R",
  "search": [
    {"field": "tpf.idcausale", "op": "in", "type": "string", "value": ["OFF"]},
    {"field": "tpf.datafattura", "op": ">=", "type": "date", "value": "01/01/2025"}
  ],
  "dimensions": ["tpf.leads_status_code", "leads_statuses.description"],
  "measures": [
    {"name": "offerte", "operation": "count"},
    {"name": "valore", "operation": "sum", "field": "totaleimponibile", "round": 2},
    {"name": "n_attive", "operation": "count",
     "filter": [{"field": "tpf.expected_conversion_date", "op": ">=", "type": "date", "value": "@today"}]},
    {"name": "valore_attive", "operation": "sum", "field": "totaleimponibile", "round": 2,
     "filter": [{"field": "tpf.expected_conversion_date", "op": ">=", "type": "date", "value": "@today"}]},
    {"name": "n_ferme", "operation": "count",
     "filter": [{"field": "tpf.expected_conversion_date", "op": "between", "type": "date", "value": "01/01/1990,@yesterday"}]},
    {"name": "valore_ferme", "operation": "sum", "field": "totaleimponibile", "round": 2,
     "filter": [{"field": "tpf.expected_conversion_date", "op": "between", "type": "date", "value": "01/01/1990,@yesterday"}]},
    {"name": "n_senza_data", "operation": "count",
     "filter": [{"type": "group_or", "filters": [
       {"field": "tpf.expected_conversion_date", "op": "is_empty"},
       {"field": "tpf.expected_conversion_date", "op": "<", "type": "date", "value": "01/01/1990", "nulls": "exclude"}
     ]}]},
    {"name": "n_data_prima_offerta", "operation": "count",
     "filter": [{"field": "tpf.expected_conversion_date", "op": "<", "type": "field_date", "value": "tpf.datafattura"}]}
  ]
}
```

- Le "ferme" usano `between 01/01/1990,@yesterday` invece di `< @today`. Così si escludono le date vuote, che `<` includerebbe, e le `0000-00-00`, che finiscono in "senza data".
- Questa è la chiamata del **totale**: pochi gruppi, uno per stato.
  - **Valore pipeline** = la riga dello stato Aperto (più On hold se richiesto), riportata come `valore_attive` / `valore_ferme` / senza data. Mai solo `valore`.
  - **Numero di offerte** = misura `offerte` dei gruppi, non `total_matching_records`.
- Il **dettaglio** per fase, agente o mese è una **seconda chiamata**: stesso `search`, altre dimensioni. La sua somma, fatta con `pn_dataset_calculate` o nel sandbox, deve coincidere con questa chiamata entro 1 €.
- `n_data_prima_offerta` = date previste ereditate dalla copia (trappola §3.3 di SKILL.md): vanno nel blocco qualità.

## R2. Pipeline aperta per agente, con riga "senza agente"

```json
{
  "table_name": "testapiedefatture_R",
  "search": [
    {"field": "tpf.idcausale", "op": "in", "type": "string", "value": ["OFF"]},
    {"field": "tpf.leads_status_code", "op": "=", "type": "string", "value": "1"}
  ],
  "dimensions": ["tpf.codage"],
  "measures": [
    {"name": "offerte", "operation": "count"},
    {"name": "valore", "operation": "sum", "field": "totaleimponibile", "round": 2},
    {"name": "valore_attive", "operation": "sum", "field": "totaleimponibile", "round": 2,
     "filter": [{"field": "tpf.expected_conversion_date", "op": ">=", "type": "date", "value": "@today"}]},
    {"name": "valore_ferme", "operation": "sum", "field": "totaleimponibile", "round": 2,
     "filter": [{"field": "tpf.expected_conversion_date", "op": "between", "type": "date", "value": "01/01/1990,@yesterday"}]}
  ],
  "order_by": [{"name": "valore", "dir": "desc"}],
  "options": {"limit_groups": 100}
}
```

Poi decodifica gli agenti con una sola `pn_tabellabase_list`:

```json
{"table_name": "agenti",
 "search": [{"field": "agenti.idagente", "op": "in", "type": "string", "value": ["FE", "3", "sca"]}],
 "output_fields": ["idagente", "nome"], "page_size": 50}
```

`agenti` ha self-join (`capoarea`, `capogruppo`): qualifica sempre con `agenti.`.

- I gruppi con `tpf_codage` vuoto o `null` vanno uniti in una riga **"senza agente"**, sempre presente e mai esclusa.
- Un codice che non si trova in `agenti` va riportato come "agente non in anagrafica (<codice>)".
- Se il nome decodificato non è una persona, segnalalo: su progest `FE` = "Invio fatt. a mezzo email", `FP` = "Invio fatt. a mezzo posta", `CO` = "Crediti Obsoleti". Mai sostituire l'agente con `cidoperatore` / `operatore_username`.
- Per un periodo, aggiungi il filtro su `tpf.datafattura`. Per vinte per agente, usa lo stato Chiuso Positivo oppure R3 con il raggruppamento per `codage` nel sandbox.

## R3. Conversione mensile (offerte → ordini)

Passo 1, offerte del periodo (`pn_tabellabase_list`, `output=url`):

```json
{
  "table_name": "testapiedefatture_R",
  "search": [
    {"field": "tpf.idcausale", "op": "in", "type": "string", "value": ["OFF"]},
    {"field": "tpf.datafattura", "op": "between", "type": "date", "value": "01/01/2026,@today"}],
  "output_fields": ["cidfattura", "datafattura", "totaleimponibile", "leads_status_code", "leads_status",
                    "codage", "expected_conversion_date", "n_doc_orig", "nome"],
  "output": "url"
}
```

Passo 2, ordini che citano un documento d'origine (`pn_tabellabase_list`, `output=url`). Non restringere per data: un ordine può arrivare mesi dopo l'offerta.

```json
{
  "table_name": "testapiedefatture_O",
  "search": [
    {"field": "tpf.idcausale", "op": "in", "type": "string", "value": ["ORCLI"]},
    {"field": "tpf.n_doc_orig", "op": "is_not_empty"},
    {"field": "tpf.n_doc_orig", "op": "<>", "type": "string", "value": "NULL"},
    {"field": "tpf.datafattura", "op": ">=", "type": "date", "value": "01/01/2026"}
  ],
  "output_fields": ["cidfattura", "datafattura", "totaleimponibile", "n_doc_orig"],
  "output": "url"
}
```

Il filtro data sugli ordini è ammesso solo dalla data della prima offerta in poi. Su progest il tempo di chiusura arriva a −28 giorni (ordine prima dell'offerta): per sicurezza anticipa di 2 mesi.

Passo 3, `pn_code_exec`:

```python
import pandas as pd
off = pd.read_json(URL_OFFERTE); ordi = pd.read_json(URL_ORDINI)
off["data"] = pd.to_datetime(off["datafattura"], dayfirst=True)
ordi["data_ord"] = pd.to_datetime(ordi["datafattura"], dayfirst=True)
ordi = ordi[ordi["n_doc_orig"].isin(off["cidfattura"])]          # solo ordini nati da offerte del perimetro
first = ordi.sort_values("data_ord").groupby("n_doc_orig", as_index=False).first()
m = off.merge(first[["n_doc_orig", "cidfattura", "data_ord"]].rename(columns={"n_doc_orig": "cidfattura", "cidfattura": "ordine"}),
              on="cidfattura", how="left")
m["con_ordine"] = m["ordine"].notna()
m["giorni_chiusura"] = (m["data_ord"] - m["data"]).dt.days
ID_VINTA = "2"   # da R0
m["vinta"] = m["leads_status_code"].astype(str) == ID_VINTA
m["mese"] = m["data"].dt.to_period("M").astype(str)
g = m.groupby("mese").agg(offerte=("cidfattura", "count"), valore=("totaleimponibile", "sum"),
                          con_ordine=("con_ordine", "sum"),
                          valore_ordinato=("totaleimponibile", lambda s: s[m.loc[s.index, "con_ordine"]].sum()),
                          vinte=("vinta", "sum"))
g["conv_num_%"] = (g["con_ordine"] / g["offerte"] * 100).round(1)
g["conv_val_%"] = (g["valore_ordinato"] / g["valore"] * 100).round(1)
incoerenti = {"vinte_senza_ordine": m[m.vinta & ~m.con_ordine]["cidfattura"].tolist(),
              "ordine_non_vinte": m[~m.vinta & m.con_ordine]["cidfattura"].tolist(),
              "chiusura_negativa": m[m.giorni_chiusura < 0]["cidfattura"].tolist()}
```

- Riporta per mese: offerte, valore, con ordine, % per numero e per valore, vinte da stato, tempo medio di chiusura. Dichiara che la base è "ordine collegato" e che il denominatore sono **tutte** le offerte del mese.
- I mesi recenti hanno conversione bassa anche perché le offerte non hanno ancora avuto il tempo di chiudersi: dillo.
- Oltre ~500 offerte, spezza per anno. Per un periodo piccolo puoi sostituire il passo 2 con un filtro `tpf.n_doc_orig` `in` sui `cidfattura` delle offerte.

## R4. Offerte ferme (aperte con data prevista passata)

`pn_tabellabase_list`:

```json
{
  "table_name": "testapiedefatture_R",
  "search": [
    {"field": "tpf.idcausale", "op": "in", "type": "string", "value": ["OFF"]},
    {"field": "tpf.leads_status_code", "op": "=", "type": "string", "value": "1"},
    {"field": "tpf.expected_conversion_date", "op": "between", "type": "date", "value": "01/01/1990,@yesterday"}
  ],
  "output_fields": ["cidfattura", "numerofattura", "datafattura", "nome", "totaleimponibile",
                    "expected_conversion_date", "leads_funnel_status", "codage", "n_doc_orig"],
  "sort": [{"field": "totaleimponibile", "dir": "desc"}],
  "page_size": 20
}
```

- Per il totale usa R1. Questa lista serve per il top N da mostrare. Per l'elenco completo usa `output=url`.
- Per ogni riga segnala se la data prevista è anteriore a `datafattura` (data ereditata dalla copia) e se l'offerta è già stata revisionata (R6).
- È solo un elenco da proporre. Chiudere le offerte si fa una alla volta e su conferma (SKILL.md §5).

## R5. Una singola offerta: ha un ordine?

`pn_document_linked_documents` **non** trova l'ordine di un'offerta (vedi `modello-dati.md` §4). Usa invece:

```json
{
  "table_name": "testapiedefatture_O",
  "search": [
    {"field": "tpf.idcausale", "op": "in", "type": "string", "value": ["ORCLI"]},
    {"field": "tpf.n_doc_orig", "op": "=", "type": "string", "value": "OFF2026213"}],
  "output_fields": ["cidfattura", "numerofattura", "datafattura", "totaleimponibile", "descrizione_stato"],
  "page_size": 5
}
```


## R6. Aperte già revisionate (da togliere dalla pipeline attiva)

Usa il dataset del passo 1 di R3, esteso a tutte le offerte da cui possono nascere revisioni (stesso perimetro o più ampio), e poi `pn_code_exec`:

```python
rev = off[off["n_doc_orig"].isin(off["cidfattura"])]                  # offerte copiate da un'altra offerta
superate = off[off["cidfattura"].isin(rev["n_doc_orig"]) & (off["leads_status_code"].astype(str) == "1")]
```

Riporta il numero e il valore di `superate` e toglile dal valore attivo della pipeline, dichiarandolo. Atteso su progest: 31 aperte, 709.380 €.

## R7. Vinte senza ordine e aperte con ordine (incoerenze stato/ordine)

Usa la `m` di R3 oppure, per una verifica rapida su un solo stato:

1. offerte Chiuso Positivo del periodo, `output_fields` `["cidfattura"]` con `output=url`;
2. ordini con `tpf.n_doc_orig` `in` su quei codici (R5 in versione multipla);
3. differenza nel sandbox.

Fai la stessa cosa con lo stato Aperto per trovare le aperte con ordine.

- Riporta i `cidfattura` (numero, data, cliente, valore) e proponi la correzione dello stato offerta per offerta. Non correggere in blocco.

## R8. Quota fasi orfane (controllo qualità)

Dalla R1 con la dimensione fase: somma i gruppi con `leads_funnel_statuses_title` nullo. Quota = orfane / totale. Riporta i codici trovati (es. `OFF`) e spiega che quelle offerte non compaiono in nessuna colonna del kanban.

## Errori tipici

| Sintomo | Causa | Rimedio |
|---|---|---|
| 0 righe filtrando per data | filtro sull'alias `datafattura` (stringa) | `tpf.datafattura` |
| Tasso di vincita ~96% | vinte / (vinte + perse), le perse non vengono chiuse | vinte o ordini / tutte le offerte |
| Pipeline enorme | aperte ferme, revisionate o con data ereditata sommate alle attive | R1 + R6, sempre in tre parti |
| Offerta vinta, ma nessun ordine trovato | cercato con `pn_document_linked_documents` | R5 (`n_doc_orig`) |
| Ordini "collegati" a offerte inesistenti | `n_doc_orig = 'NULL'` o che punta ad altri documenti | filtro `<> 'NULL'` + join sui `cidfattura` delle offerte |
| Analisi per agente con un solo "agente" grande | codici `agenti` usati per altro (`FE`, `FP`) | decodifica e segnala |
| Stato invariato dopo aver spostato la card | RULE-CRM-013: per le offerte la card cambia solo la fase | imposta lo stato esplicitamente |
