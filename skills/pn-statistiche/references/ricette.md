# Ricette `pn_statistiche_query`

Valori di riferimento: tenant `progest`, calcolati read-only il 2026-10-14 (mesi chiusi gennaio-settembre 2026). Servono a riconoscere un risultato plausibile, non vanno riportati su altri tenant. Prima di ogni ricetta: `pn_statistiche_catalog` una volta nel job.

## R1 — Fatturato per mese

```json
{"tipo_statistica": "F", "groups": ["mese"], "filters": {"date_from": "2026-01-01", "date_to": "2026-09-30"}, "measures": ["qta", "valore"]}
```

Controlla: 9 righe (`group1_code` 01..09, `group1_label` gennaio..settembre); totale da `totals.valore`.

## R2 — Top clienti con riga "altri"

```json
{"tipo_statistica": "F", "groups": ["cliente"], "filters": {"anno": ["2026"]}, "measures": ["valore"], "top_n": 5}
```

Controlla: righe con `group1_code` + `group1_label`, `others` e `totals` dal server.

## R3 — Confronto con lo stesso periodo dell'anno precedente

```json
{"tipo_statistica": "F", "groups": ["agente"], "filters": {"date_from": "2026-01-01", "date_to": "2026-09-30"}, "measures": ["valore"], "compare": {"mode": "previous_year"}, "order_by": {"field": "delta_valore", "direction": "desc"}}
```

Controlla: per riga `valore`, `valore_cmp`, `delta_valore`, `delta_valore_pct`; un gruppo presente in un solo periodo vale 0 nell'altro.

## R4 — Margine per categoria merceologica con copertura del costo

```json
{"tipo_statistica": "F", "groups": ["catmerc"], "filters": {"date_from": "2026-01-01", "date_to": "2026-09-30"}, "measures": ["valore", "costo", "margine", "margine_pct", "valore_senza_costo"], "order_by": {"field": "valore", "direction": "desc"}}
```

Controlla: `data_quality.copertura_costo_pct` e i warning `COST_MISSING` / `COST_IS_CURRENT_LAST_COST`.

## R5 — Agente, poi cliente, poi articolo

```json
{"tipo_statistica": "F", "groups": ["agente", "cliente", "articolo"], "filters": {"anno": ["2026"]}, "measures": ["qta", "valore"], "page_size": 50}
```

Controlla: 3 livelli con codice e descrizione; `total_groups` (progest 2026: 640) e `has_more`. Per l'elenco completo usa il `result_set_id` (R8), non paginare. Codice agente vuoto = "senza agente".

## R6 — Acquistato separato tra ordini a fornitore e carichi

```json
{"tipo_statistica": "A", "groups": ["tipocausale", "idfornitore"], "filters": {"anno": ["2026"]}, "measures": ["qta", "valore"]}
```

Controlla: righe T (Ordine fornitore) e M (Movimento/carico) separate, mai sommate.

## R7 — Ordinato per cliente

```json
{"tipo_statistica": "O", "groups": ["cliente"], "filters": {"date_from": "2026-01-01", "date_to": "2026-09-30"}, "measures": ["qta", "valore"], "top_n": 10}
```

Controlla: solo causali con tipo statistica O (progest: ORCLI); l'ordinato non e fatturato.

## R8 — Export Excel della statistica

1. Esegui la query (es. R5) e prendi `result_set_id`.
2. `pn_excel_generate` con `"source": {"type": "result_set", "result_set_id": "<rs_...>"}`.
3. Per ricalcoli (somme, quote): `pn_dataset_calculate` sullo stesso `result_set_id`.

Non ricopiare le righe nel payload. Se la risposta contiene `auto_export`, il dataset completo e gia esportato: segui le sue istruzioni.
