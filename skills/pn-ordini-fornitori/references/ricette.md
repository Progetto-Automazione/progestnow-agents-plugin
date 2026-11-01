# Ordini a fornitore: ricette operative

## Prerequisiti

- Descriptor della tabella letto in questo job (`pn_tabellabase_descriptor`) + `ai_instructions`.
- Configurazione del tenant letta con R1.
- Sintassi: skill `pn-tabellabase-query`.

## Nomi dei campi verificati sui descrittori core e sugli override di tenant A

| Tabella | FROM | Campi da filtrare | Note |
|---|---|---|---|
| `qrystatistichedocumenti` | `FROM qrystatistichedocumenti`, senza join | `qrystatistichedocumenti.<campo>` | `testa_data` è una stringa `aaaa-mm-gg` (il filtro `date` funziona) |
| `qrystampafattura` | `FROM qrystampafattura LEFT JOIN arccli LEFT JOIN lotti` | `qrystampafattura.<campo>` | `idmagazzino` esiste anche in `lotti`: qualifica sempre. Alias calcolati in output: `qtaresidua`, `datadoc`, `datacons` (stringhe formattate) |
| `testapiedefatture_T` | `FROM testapiedefatture tpf INNER JOIN causalimagazzino cm` | `tpf.<campo>`; `cm.<campo>` solo come dimensione (nei filtri può dare `FIELD_UNKNOWN`, vedi sotto) | `qryordevasi` e `tipologieordine` in join; `arccli` è `arcfor` (fornitore) |

## Numeri "atteso su tenant A"

- Sono il risultato SQL equivalente eseguito read-only su `tenant A` il 2026-10-10, sugli ordini con `datafattura` ≥ 2025-01-01 (2026 per la puntualità).
- Servono per controllare la plausibilità, non sono valori da riportare.

## Filtro "riga aperta" (search v2)

Si usa in R3, R4 e R7:

```json
[
  {"field": "qrystampafattura.tipocausale", "op": "=", "type": "string", "value": "T"},
  {"field": "qrystampafattura.idmagazzino", "op": "<>", "type": "string", "value": "*"},
  {"type": "group_or", "filters": [
    {"field": "qrystampafattura.levasioneasaldo", "op": "is_empty"},
    {"field": "qrystampafattura.levasioneasaldo", "op": "<>", "type": "string", "value": "S"}
  ]},
  {"field": "qrystampafattura.quantitaevasa", "op": "<", "type": "field_number", "value": "qrystampafattura.quantita"}
]
```

- Il `group_or` serve perché `<>` esclude le righe con `levasioneasaldo` NULL (su tenant A vale `''` o `S`, ma su altri tenant può essere NULL).
- Su `qrystatistichedocumenti` basta `riga_quantitadaevadere > 0`, che applica la stessa formula.

## Se un filtro sulla causale dà errore (strada secondaria)

Dove il catalogo campi MCP è attivo (es. progest, bene), i filtri `search` accettano solo i campi del catalogo. I campi della causale in join (`cm.tipocausale`, `cm.flagidcliente_idfornitore`, ecc.) spesso non ci sono e la chiamata risponde `FIELD_UNKNOWN` o `FIELD_NOT_FILTERABLE`. Lo stesso può succedere a `testa_causale_tipo` o `tipocausale` sulle viste di riga.

Se succede, non cambiare tabella e non ripiegare su un codice causale scritto a mano:

1. leggi le causali con la stessa condizione su `causalimagazzino` (tabella piccola, una chiamata):

   ```json
   {"table_name": "causalimagazzino",
    "search": [{"field": "causalimagazzino.tipocausale", "op": "=", "type": "string", "value": "T"}],
    "output_fields": ["idcausale", "descrizione", "tipocausale", "flagidcliente_idfornitore"],
    "page_size": 100}
   ```

   Se anche questo filtro desse errore, togli il `search` e filtra l'elenco completo (poche decine di righe);
2. tieni i codici che soddisfano la condizione (qui tipologia T con flag F);
3. rilancia la chiamata originale sostituendo il filtro sulla causale con il filtro sul codice:

   | Tabella | Filtro |
   |---|---|
   | `testapiedefatture_T` / `testapiedefatture` | `{"field": "tpf.idcausale", "op": "in", "type": "string", "value": [codici]}` |
   | `qrystatistichedocumenti` | `testa_causale_codice` |
   | `qrystampafattura` | `qrystampafattura.idcausale` |
4. se a dare errore è una **dimensione** sulla causale, raggruppa per il codice causale e riconduci ogni codice alla sua tipologia con l'elenco del passo 1.

Usa `"op": "in"` con `"type": "string"` e un array. **Non** usare `collection` / `collection_or`: hanno una semantica CSV con `LIKE` (`_` e `%` diventano jolly) e `collection` mette i valori in AND (su progest, job 874, ha restituito 0 documenti).

## R1. Configurazione del tenant (sempre, una volta per job)

**a) Causali T**, con `pn_tabellabase_list` su `causalimagazzino`:

```json
{"table_name": "causalimagazzino",
 "search": [{"field": "causalimagazzino.tipocausale", "op": "in", "type": "string", "value": ["T", "R", "M"]}],
 "output_fields": ["idcausale", "descrizione", "tipocausale", "flagidcliente_idfornitore", "movimentaquantitacaricata"],
 "page_size": 100}
```

- Da qui ricavi:
  - le causali **T + F**, cioè gli ordini fornitore;
  - le R + F, richieste d'offerta, da **escludere**;
  - le M + F con `+`, che sono carichi ma anche produzione, rettifiche e inventario.
- Se esiste una causale T con flag C, escludila nelle ricette con `testa_causale_codice` / `idcausale` `not_in` e dichiaralo.
- Da qui viene l'elenco **[causali T con flag F]** usato nel filtro `tpf.idcausale` `in` di R1d e di ogni chiamata su `testapiedefatture_T` / `testapiedefatture`. Negli esempi è `["ORFOR"]` (tenant A): sostituiscilo con quello del tenant.
- Una causale T può non essere un acquisto. Su progest ci sono `ORFOR` "ORDINE FORNITORE" e `ORDPR` "ORDINE PRODUZIONE" (1 documento, 2020), entrambe con flag F: mostrala separata e chiedi se includerla.

**b) Causali T non soggette a evasione**: stessa chiamata filtrata su T, con in più `{"field": "causalimagazzino.no_evasione", "op": "=", "type": "number", "value": "1"}`. `no_evasione` non è tra gli `output_fields_allowed`, ma è filtrabile. Atteso su tenant A: 0 righe.

**c) Stati**, con `pn_tabellabase_list` su `tipologieordine`:

```json
{"table_name": "tipologieordine",
 "search": [{"field": "tipologieordine.tipocausale", "op": "contains", "type": "string", "value": "T"}],
 "output_fields": ["nidtipologiaordine", "cdesctipologiaordine", "cbloccato", "tipocausale"],
 "page_size": 50}
```

- Gli stati di annullamento si riconoscono dalla descrizione: dichiarali esclusi. In caso di dubbio chiedi.

**d) Valute, evasione e stati in uso**, con `pn_tabellabase_aggregate` su `testapiedefatture_T`:

```json
{
  "table_name": "testapiedefatture_T",
  "search": [
    {"field": "tpf.idcausale", "op": "in", "type": "string", "value": ["ORFOR"]},
    {"field": "tpf.datafattura", "op": ">=", "type": "date", "value": "01/01/2025"}
  ],
  "dimensions": ["tpf.idvaluta", "qryordevasi.evaso", "tpf.nidtipologiaordine"],
  "measures": [
    {"name": "ordini", "operation": "count"},
    {"name": "cambio_anomalo", "operation": "count",
     "filter": [{"field": "tpf.cambio", "op": "<>", "type": "number", "value": "1"}]},
    {"name": "imponibile", "operation": "sum", "field": "totaleimponibile", "round": 2}
  ]
}
```

- Il numero di ordini è la somma della misura `ordini` dei gruppi, da fare con `pn_dataset_calculate` o nel sandbox, mai `total_matching_records`. Qui coincide solo perché il `search` filtra le causali T.
- `cambio_anomalo` sulle righe EUR va segnalato.
- Se il descriptor è personalizzato con `GROUP BY` e l'aggregate viene rifiutato, usa `qrystatistichedocumenti` con `count_distinct testa_cidfattura` e dimensione `testa_evaso`. La valuta lì non c'è: in quel caso prendila da R3.

**e) Temporanea WMS**: `pn_tabellabase_catalog(names=["qrywms_tmp_carichi_ordfor"])`.

- Se esiste, conta le righe per gli ordini analizzati:

```json
{"table_name": "qrywms_tmp_carichi_ordfor",
 "search": [{"field": "qrywms_tmp_carichi_ordfor.ordf_cidfattura", "op": "is_not_empty"}],
 "dimensions": ["qrywms_tmp_carichi_ordfor.ordf_cidfattura", "qrywms_tmp_carichi_ordfor.user_id"],
 "measures": [{"name": "righe", "operation": "count"},
              {"name": "qta_in_sospeso", "operation": "sum", "field": "carico_quantita"}]}
```

- Solo lettura.

## R2. Ordinato aperto per fornitore (quantità e conteggi)

`pn_tabellabase_aggregate` su `qrystatistichedocumenti`:

```json
{
  "table_name": "qrystatistichedocumenti",
  "search": [
    {"field": "qrystatistichedocumenti.testa_causale_tipo", "op": "=", "type": "string", "value": "T"},
    {"field": "qrystatistichedocumenti.riga_quantitadaevadere", "op": ">", "type": "number", "value": "0"},
    {"field": "qrystatistichedocumenti.riga_articolo_idmagazzino", "op": "<>", "type": "string", "value": "*"},
    {"field": "qrystatistichedocumenti.testa_data", "op": ">=", "type": "date", "value": "01/01/2025"}
  ],
  "dimensions": ["qrystatistichedocumenti.testa_fornitore_codice", "qrystatistichedocumenti.testa_clifor_nome"],
  "measures": [
    {"name": "ordini_aperti", "operation": "count_distinct", "field": "testa_cidfattura"},
    {"name": "righe_aperte", "operation": "count"},
    {"name": "qta_residua", "operation": "sum", "field": "riga_quantitadaevadere", "round": 2},
    {"name": "ordini_parziali", "operation": "count_distinct", "field": "testa_cidfattura",
     "filter": [{"field": "qrystatistichedocumenti.riga_quantitaevasa", "op": ">", "type": "number", "value": "0"}]},
    {"name": "righe_in_ritardo", "operation": "count",
     "filter": [{"field": "qrystatistichedocumenti.riga_dataconsegna", "op": "between", "type": "date", "value": "01/01/1990,@yesterday"}]},
    {"name": "righe_senza_data", "operation": "count",
     "filter": [{"type": "group_or", "filters": [
       {"field": "qrystatistichedocumenti.riga_dataconsegna", "op": "is_empty"},
       {"field": "qrystatistichedocumenti.riga_dataconsegna", "op": "<", "type": "date", "value": "01/01/1990", "nulls": "exclude"}
     ]}]}
  ],
  "order_by": [{"name": "righe_aperte", "dir": "desc"}],
  "options": {"limit_groups": 100}
}
```

- **Per buyer**: dimensioni `["qrystatistichedocumenti.piede_utente_codice", "qrystatistichedocumenti.piede_utente_username"]`.
- **Per mese dell'ordine**: `date_buckets: [{"name": "mese", "field": "qrystatistichedocumenti.testa_data", "bucket": "month"}]`.
- **Per stato**: dimensioni `piede_tipologia_codice` / `piede_tipologia_descrizione`. Per escludere un annullamento usa `piede_tipologia_codice` `not_in` [id] **in `group_or` con `is_empty`**, altrimenti spariscono gli ordini senza stato.
- **Totale prima, dettaglio poi.** La chiamata del totale è questa senza `dimensions`: un solo gruppo, con ordini aperti, righe, quantità e ritardi. Quella per fornitore è il dettaglio, e la sua somma deve quadrare con il totale. Il numero di ordini è sempre `ordini_aperti` (`count_distinct`), mai `total_matching_records`, che qui conta le righe.
- `ordini_parziali` conta gli ordini aperti con almeno una riga **aperta** già parzialmente ricevuta. Per includere gli ordini con righe chiuse e altre aperte serve R7.

## R3. Merce in arrivo: valore per valuta

Passo 1: `pn_tabellabase_list` su `qrystampafattura` con il **filtro riga aperta** + `{"field": "qrystampafattura.datafattura", "op": ">=", "type": "date", "value": "01/01/2025"}`:

```json
{
  "table_name": "qrystampafattura",
  "search": ["<filtro riga aperta>", {"field": "qrystampafattura.datafattura", "op": ">=", "type": "date", "value": "01/01/2025"}],
  "output_fields": ["cidfattura", "numerofattura", "datafattura", "idfornitore", "nome", "idmagazzino", "descrizionearticolo",
                    "quantita", "quantitaevasa", "importototale", "idvaluta", "cambio", "dataconsegna", "idriga", "cidoperatore", "idcausale"],
  "output": "url"
}
```

`"<filtro riga aperta>"` va sostituito con i quattro filtri della sezione sopra. È un segnaposto, non un valore.

Passo 2: `pn_code_exec`:

```python
import pandas as pd
r = pd.read_json(URL)
r = r[r["quantita"] > 0]
r["residuo"] = r["quantita"] - r["quantitaevasa"]
r["valore_residuo"] = r["residuo"] * r["importototale"] / r["quantita"]
per_valuta = r.groupby("idvaluta").agg(ordini=("cidfattura", "nunique"), righe=("idriga", "count"),
                                        valore=("valore_residuo", "sum")).round(2)
per_forn = r.groupby(["idvaluta", "idfornitore", "nome"]).agg(ordini=("cidfattura", "nunique"),
                                                               valore=("valore_residuo", "sum")).round(2) \
            .sort_values("valore", ascending=False)
```

- **Mai un totale unico tra valute diverse.** Se l'utente vuole il controvalore in EUR, chiedi o verifica la regola del `cambio` (descriptor o KB) e dichiarala.
- Righe con `quantita = 0` hanno residuo 0: escluse.
- Codici valuta non normalizzati (`''`, `EURO`, `US$` negli ordini storici di tenant A): riportali come gruppi distinti. Accorpali (es. `''` → valuta di default di `tabvalute`) solo dichiarandolo.

## R4. Righe in ritardo

- **Conteggi per fornitore**: R2 con in più il filtro `qrystatistichedocumenti.riga_dataconsegna` `between` `"01/01/1990,@yesterday"`.
- **Elenco** (top N per ritardo): `pn_tabellabase_list` su `qrystampafattura`:

```json
{
  "table_name": "qrystampafattura",
  "search": ["<filtro riga aperta>",
             {"field": "qrystampafattura.dataconsegna", "op": "between", "type": "date", "value": "01/01/1990,@yesterday"}],
  "output_fields": ["cidfattura", "numerofattura", "datafattura", "nome", "idmagazzino", "descrizionearticolo",
                    "quantita", "quantitaevasa", "qtaresidua", "dataconsegna", "idvaluta"],
  "sort": [{"field": "dataconsegna", "dir": "asc"}],
  "page_size": 30
}
```

- Giorni di ritardo = oggi − `dataconsegna`. Per i totali e la media usa `output=url` e il sandbox.
- Dichiara sempre la quota di righe aperte senza data (R2, `righe_senza_data`).

## R5. Puntualità per fornitore

Passo 1, righe d'ordine del periodo con data di consegna (`output=url`):

```json
{
  "table_name": "qrystampafattura",
  "search": [
    {"field": "qrystampafattura.tipocausale", "op": "=", "type": "string", "value": "T"},
    {"field": "qrystampafattura.idmagazzino", "op": "<>", "type": "string", "value": "*"},
    {"field": "qrystampafattura.datafattura", "op": ">=", "type": "date", "value": "01/01/2026"},
    {"field": "qrystampafattura.dataconsegna", "op": ">=", "type": "date", "value": "01/01/1990"}
  ],
  "output_fields": ["idriga", "cidfattura", "idfornitore", "nome", "dataconsegna", "quantita", "quantitaevasa", "levasioneasaldo"],
  "output": "url"
}
```

Passo 2, righe di **carico** (M) che puntano a una riga d'ordine (`output=url`). Il periodo parte dalla data del primo ordine:

```json
{
  "table_name": "qrystampafattura",
  "search": [
    {"field": "qrystampafattura.tipocausale", "op": "=", "type": "string", "value": "M"},
    {"field": "qrystampafattura.riferimentorigaordine", "op": "is_not_empty"},
    {"field": "qrystampafattura.riferimentorigaordine", "op": "not_in", "type": "string", "value": ["NULL", "0"]},
    {"field": "qrystampafattura.datafattura", "op": ">=", "type": "date", "value": "01/01/2026"}
  ],
  "output_fields": ["riferimentorigaordine", "cidfattura", "idcausale", "datafattura", "quantita"],
  "output": "url"
}
```

Passo 3, `pn_code_exec`:

```python
import pandas as pd
o = pd.read_json(URL_ORDINI); c = pd.read_json(URL_CARICHI)
o["dc"] = pd.to_datetime(o["dataconsegna"]).dt.normalize()
c["dcar"] = pd.to_datetime(c["datafattura"]).dt.normalize()
c = c[c["riferimentorigaordine"].astype(str).isin(o["idriga"].astype(str))]      # solo carichi delle righe T del perimetro
agg = c.groupby("riferimentorigaordine").agg(prima=("dcar", "min"), ultima=("dcar", "max"),
                                             n_carichi=("cidfattura", "nunique"), qta=("quantita", "sum")).reset_index()
m = o.merge(agg, left_on=o["idriga"].astype(str), right_on=agg["riferimentorigaordine"].astype(str), how="inner")
m["ritardo_gg"] = (m["ultima"] - m["dc"]).dt.days
m["puntuale"] = m["ritardo_gg"] <= 0
p = m.groupby(["idfornitore", "nome"]).agg(righe=("idriga", "count"), puntuali=("puntuale", "sum"),
                                          ritardo_medio=("ritardo_gg", "mean"),
                                          in_piu_carichi=("n_carichi", lambda s: (s > 1).sum()))
p["puntualita_%"] = (p["puntuali"] / p["righe"] * 100).round(1)
```

- Solo carichi **M**: le fatture d'acquisto (A) o le richieste (I) che puntano alla stessa riga non sono consegne.
- La quantità dei carichi serve a segnalare eccedenze; la fonte del ricevuto resta la riga d'ordine.
- Puntuale = ultimo carico entro `dataconsegna`. Riporta anche la versione "primo carico" se l'utente chiede la reattività.
- Dichiara che `dataconsegna` è la data richiesta e la quota di righe evase senza data (tenant A 2026: 2.223 su 7.874).

## R6. Singolo ordine con carichi e origine

1. **Righe e residui.**
   - `pn_document_evadable_rows` con `source_document_codes: ["<cidfattura>"]` e `include_closed: "yes"`, se l'agente ha il tool.
   - Altrimenti `pn_tabellabase_list` su `qrystampafattura` con `qrystampafattura.cidfattura` `=` `<cidfattura>` e gli output di R3.
2. **Carichi**: `pn_document_linked_documents(document_code=<cidfattura>)`, che restituisce i documenti M che evadono le righe.
   - Se l'agente non ha il tool, usa `qrystampafattura` con `riferimentorigaordine` `in` [idriga dell'ordine] e `tipocausale = M`.
3. **Origine**:
   - leggi `n_doc_orig` e `riferimento` della testata (`testapiedefatture_T`, `output_fields` `["cidfattura", "n_doc_orig", "riferimento"]`);
   - verifica ognuno con `pn_tabellabase_list` su `testapiedefatture_O` (ordine cliente) o `testapiedefatture_R` (richiesta d'offerta), filtrando `tpf.cidfattura` `=` valore;
   - se non esiste, **non** è un collegamento: dillo, ad esempio "`n_doc_orig` contiene un testo che non corrisponde a nessun documento".
4. **WMS**: se R1e ha trovato la temporanea, cerca `ordf_cidfattura = <cidfattura>`.


## R7. Ordini fermi e parziali

`pn_tabellabase_aggregate` su `qrystatistichedocumenti`, un gruppo per ordine:

```json
{
  "table_name": "qrystatistichedocumenti",
  "search": [
    {"field": "qrystatistichedocumenti.testa_causale_tipo", "op": "=", "type": "string", "value": "T"},
    {"field": "qrystatistichedocumenti.riga_articolo_idmagazzino", "op": "<>", "type": "string", "value": "*"},
    {"field": "qrystatistichedocumenti.testa_data", "op": "<", "type": "date", "value": "@today-180d", "nulls": "exclude"}
  ],
  "dimensions": ["qrystatistichedocumenti.testa_cidfattura", "qrystatistichedocumenti.testa_clifor_nome", "qrystatistichedocumenti.testa_data"],
  "measures": [
    {"name": "qta_residua", "operation": "sum", "field": "riga_quantitadaevadere", "round": 2},
    {"name": "qta_evasa", "operation": "sum", "field": "riga_quantitaevasa", "round": 2}
  ],
  "having": [{"name": "qta_residua", "op": ">", "value": "0"}],
  "order_by": [{"name": "qta_residua", "dir": "desc"}],
  "options": {"limit_groups": 200}
}
```

- **Fermi** = gruppi con `qta_evasa = 0`, cioè nessun ricevimento. Gli altri sono aperti da oltre 180 giorni ma parzialmente ricevuti.
- Aggiungi gli ordini in stato `cbloccato = 'S'` (R1c), se esistono.
- Dichiara la soglia usata.

## R8. Controlli di qualità (blocco "Qualità del dato")

Da R3, aggiungendo all'export le righe **chiuse** (togli il filtro riga aperta) e le righe dei carichi di R5, calcola nel sandbox:

| Controllo | Regola | Atteso tenant A 2026 |
|---|---|---|
| Evasione oltre l'ordinato | `quantitaevasa > quantita` | ~50 righe |
| Chiuse a saldo senza carico | `levasioneasaldo = 'S'` e nessuna riga M con `riferimentorigaordine = idriga` | 132 righe |
| Chiuse a saldo con ricevuto inferiore all'ordinato | `levasioneasaldo = 'S'` e `quantitaevasa < quantita` | 148 righe |
| Quantità evasa senza carico | `quantitaevasa > 0` e nessun documento collegato | 6 righe |
| Cambio anomalo | EUR con `cambio ≠ 1` | 1 ordine dal 2025 |
| Righe `*` aperte | — | 11 dal 2025 |

## Errori tipici

| Sintomo | Causa | Rimedio |
|---|---|---|
| Richieste d'offerta tra gli ordini | filtro su "fornitore" invece che su tipologia T | `tipocausale = 'T'` |
| Resi da cliente o rettifiche tra i carichi | carichi presi per flag F/`+` | carichi = righe M collegate a righe T |
| Ricevuto = ordinato su ordini mai arrivati | usato `totqtaevasa` o `quantitaevasa` di righe chiuse a saldo | `totqtaevasa_reale` / somma dei carichi |
| Evasione doppia | sommati carichi e fatture d'acquisto con `riferimentorigaordine` | solo `quantitaevasa` della riga d'ordine |
| Ordini aperti per sempre | righe `*` di spese o note mai caricate | escludere le `*`, segnalarle |
| Totale "merce in arrivo" senza senso | sommate valute diverse | per valuta |
| 0 righe filtrando per articolo | `idmagazzino` non qualificato (ambiguo con `lotti`) | `qrystampafattura.idmagazzino` |
| "Ordine cliente d'origine" inesistente | `n_doc_orig` o `riferimento` con testo libero | verificare che il documento esista |
