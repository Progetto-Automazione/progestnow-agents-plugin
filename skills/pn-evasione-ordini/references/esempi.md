# Esempi di evasione

## A. DDT fornitore allegato → carico che evade l'ordine

Richiesta: "Il fornitore BREVI mi ha mandato questo DDT (n. 4817/26 del 03/10/2026), evadimi l'ordine".

1. Dal DDT: riferimento ordine "Vs. ordine N. 3 del 03/10/2026", fornitore BREVI → ricerca documenti → `ORFOR20263`.

2. Righe evadibili:

```json
{"name": "pn_document_evadable_rows", "input": {"source_document_codes": ["ORFOR20263"]}}
```

Risposta compatta (estratto):

```json
{"response_detail": "compact",
 "documents": [{"document_code": "ORFOR20263", "counterparty": {"type": "vendor", "code": "12124"}, "rows_count": 50,
  "rows_table_columns": "line_number | row_id | product_code | description | unit_of_measure | ordered_qty | evaded_qty | residual_qty | unit_price",
  "rows_table": [
    "10 | 2026-2459 | * | Headset | PZ | 8 | 0 | 8 | 59.9",
    "14 | 2026-2463 | * | Tastiera | PZ | 10 | 0 | 10 | 328.23",
    "21 | 2026-2470 | * | Scanner documenti | PZ | 1 | 0 | 1 | 210",
    "22 | 2026-2471 | * | Stampante etichette | PZ | 2 | 0 | 2 | 145"
  ]}],
 "warnings": ["rows_without_product_code: ..."]}
```

Le righe 21 e 22 sono adiacenti: e qui che si sbaglia di una riga se si ricostruisce l'elenco a mano. Copia `row_id` e `description` dalla stessa stringa.

3. Confronto con il DDT (codice, **descrizione**, quantita): Headset 9 (oltre l'ordinato), Tastiera 8 (consegna parziale), Stampante etichette 2, le altre righe come ordinato.

4. Sessione:

```json
{"name": "pn_document_new_start", "input": {"document_type_code": "CAR", "vendor_code": "12124", "document_date": "2026-10-03"}}
```

5. Una sola evasione con tutte le quantita del DDT e i dati del DDT:

```json
{"name": "pn_document_session_evade_rows", "input": {
  "session_code": "AIDOC_...",
  "source_document_code": "ORFOR20263",
  "selection_mode": "rows",
  "rows": [
    {"row_id": "2026-2459", "quantity": 9, "expected_description": "Headset"},
    {"row_id": "2026-2463", "quantity": 8, "expected_description": "Tastiera"},
    {"row_id": "2026-2471", "quantity": 2, "expected_description": "Stampante etichette"},
    {"row_id": "2026-2450", "expected_description": "Docking Station"}
  ],
  "original_document_number": "4817/26",
  "original_document_date": "2026-10-03"
}}
```

- `expected_description` = descrizione della riga d'ordine: se avessi scritto `2026-2470` (Scanner documenti) per la Stampante etichette, il tool rifiuta con `row_description_mismatch` e non aggiunge nulla.
- Riga senza `quantity` = residuo disponibile.
- Tastiera 8 su 10, senza `force_closure`: restano 2 aperte sull'ordine.
- Headset 9 su 8: warning `over_delivery`, da riportare.

6. Anteprima, riepilogo all'utente (quantita, eccedenze, residui aperti, warning), conferma, poi:

```json
{"name": "pn_document_new_save", "input": {"session_code": "AIDOC_...", "confirm_save": "yes"}}
```

## B. DDT che evade due ordini dello stesso fornitore

Stessa sessione, due chiamate:

```json
{"name": "pn_document_session_evade_rows", "input": {"session_code": "AIDOC_...", "source_document_code": "ORFOR20263", "selection_mode": "rows", "rows": [...], "original_document_number": "4817/26", "original_document_date": "2026-10-03"}}
{"name": "pn_document_session_evade_rows", "input": {"session_code": "AIDOC_...", "source_document_code": "ORFOR20271", "selection_mode": "rows", "rows": [...]}}
```

Ogni ordine aggiunge la propria riga descrittiva; la testata viene ereditata una volta per ordine; colli e pesi si sommano.

## C. Ordine cliente → DDT o fattura

Richiesta: "Spedisci le righe 1, 3 e 4 dell'ordine ORCLI2026294".

```json
{"name": "pn_document_evadable_rows", "input": {"source_document_codes": ["ORCLI2026294"]}}
```

Se le righe 1, 3 o 4 non compaiono o hanno `residual_qty` 0 (gia evase, es. gia fatturate): **fermati e chiedi**. Altrimenti:

```json
{"name": "pn_document_new_start", "input": {"document_type_code": "DDT", "customer_code": "1970"}}
{"name": "pn_document_session_evade_rows", "input": {"session_code": "AIDOC_...", "source_document_code": "ORCLI2026294", "selection_mode": "rows", "rows": [{"line_number": 1}, {"line_number": 3}, {"line_number": 4}]}}
```

Per un ordine cliente `original_document_number` di norma non serve.

## D. Correggere una quantita dopo l'evasione (prima del save)

Usa il `draft_row_id` restituito in `evasion.evaded_rows_table`, mai il numero di riga della sessione:

```json
{"name": "pn_document_new_row_update", "input": {"session_code": "AIDOC_...", "draft_row_id": "AIROW_DC3D2AACEC95BC4AD02F3146", "quantity": 7}}
```

Sulle righe di evasione l'articolo non e modificabile (`evasion_row_product_locked`): per un articolo diverso rimuovi la riga (`pn_document_new_row_remove`) e aggiungi una riga libera.

## E. Chiudere a saldo una consegna parziale

"Sono arrivate 3 tastiere su 10, il resto non lo mandano piu":

```json
{"row_id": "2026-2463", "quantity": 3, "expected_description": "Tastiera", "force_closure": "S"}
```
