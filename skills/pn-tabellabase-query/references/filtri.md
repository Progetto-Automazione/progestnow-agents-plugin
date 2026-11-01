# Filtri `search`: contratto search v2 (spec 190)

Il parametro `search` e un **array JSON di oggetti**; i filtri sono combinati in **AND**. Lo stesso contratto vale per `pn_tabellabase_list`, `pn_coge_partitario_search`, `pn_tabellabase_aggregate` (anche `measures[].filter`) e `pn_tabellabase_missing_children`.

```json
{"field": "<colonna fisica>", "op": "<operatore>", "type": "<tipo>", "value": "<valore>"}
```

Un filtro non valido **non viene mai ignorato**: il tool risponde `code=INVALID_SEARCH` con `path` (es. `search[2].filters[1]`), `error`, `hint` e `allowed`, e la query non parte. Correggi il filtro indicato e riprova. Ogni risposta riporta `search_effective`: i filtri effettivamente applicati, con le date relative gia risolte (`value_input` = valore originale).

## Tipi e operatori

| type | op ammessi | value |
|---|---|---|
| `string` | `=`, `<>`, `>`, `>=`, `<`, `<=`, `contains`, `not_contains`, `starts_with`, `ends_with`, `in`, `not_in`, `is_empty`, `is_not_empty` | testo. `%` e `_` sono **letterali**: non servono jolly, `contains` aggiunge da solo il "contiene". `=` e uguaglianza esatta (maiuscole/minuscole indifferenti). |
| `number` (alias `int`) | `=`, `<>`, `>`, `>=`, `<`, `<=`, `between`, `in`, `not_in`, `is_empty`, `is_not_empty` | numero, es. `"190"`, `"…"` |
| `date` | `=`, `<>`, `>`, `>=`, `<`, `<=`, `between`, `is_empty`, `is_not_empty` | `gg/mm/aaaa`, `aaaa-mm-gg` o **data relativa** (sotto) |
| `time` | come `date` | `HH:MM` |
| `collection_or` / `collection_and` | `=`, `<>` | solo per **campi CSV multi-valore** (es. `sedi_ids` = `",3,7,"`). `<>` esclude. |
| `field_number` / `field_date` / `field_string` | `=`, `<>`, `>`, `>=`, `<`, `<=` | **nome di un altro campo** della stessa riga |
| `group_or` | — | `filters`: 2..10 filtri in OR |

Alias accettati: `LIKE` = `contains`, `LIKE0` = `starts_with`, `NOT LIKE` = `not_contains`, `!=` = `<>`, `eq/gt/gte/lt/lte`, `any_of` = `in`, `none_of` = `not_in`, `null-empty` + `=` / `<>` = `is_empty` / `is_not_empty`.

Senza `type`: per `>`, `>=`, `<`, `<=`, `between` il tipo viene dedotto dal valore (warning `TYPE_INFERRED`); altrimenti vale `string`. Indicalo sempre per numeri e date.

## Regole che evitano gli errori piu costosi

1. **`field` e la colonna fisica della `FROM`**, non l'alias mostrato nella lista. Vedi §3 della SKILL.md. In caso di dubbio, `ai_instructions` o `single_fields` battono l'alias; come ultima risorsa `descriptor(detail="full")` e leggi `dttable.query`.
2. **Un `=` che ritorna 0 righe con un valore che sai esistere** indica un nome campo sbagliato, non l'assenza di dati. Correggi il `field`.
3. **`in` / `not_in` sono IN esatti** sul valore del campo. Usa `collection_or` solo per campi che contengono liste separate da virgole.
4. **Esclusioni e vuoti**: `<>`, `not_in` e `not_contains` escludono anche le righe con il campo NULL (SQL standard). Se vuoi anche i vuoti, usa un `group_or` con `is_empty`.
5. **Date `<` / `<=`**: per compatibilita includono le righe con data vuota. Per escluderle aggiungi `"nulls":"exclude"` (es. scadenze passate con data valorizzata).
6. **Vietato** SQL nel valore, `freesql`, subquery ed espressioni nei campi. Se un filtro non e esprimibile neanche con `group_or` / `field_*`, estrai con `output=url` e filtra nel sandbox (`pn_code_exec`).

## Date relative (consigliate nei job pianificati)

`@today`, `@yesterday`, `@tomorrow`, `@start_of_week`, `@end_of_week`, `@start_of_month`, `@end_of_month`, `@start_of_quarter`, `@end_of_quarter`, `@start_of_year`, `@end_of_year`, con offset opzionale `+N` / `-N` e unita `d` (giorni), `w` (settimane), `m` (mesi), `q` (trimestri), `y` (anni). La data "oggi" e quella del database del tenant. Settimana ISO (lunedi-domenica).

| Serve | value |
|---|---|
| ultimi 30 giorni | `between` `"@today-30d,@today"` |
| mese corrente | `between` `"@start_of_month,@end_of_month"` |
| mese precedente | `between` `"@start_of_month-1m,@end_of_month-1m"` |
| anno precedente | `between` `"@start_of_year-1y,@end_of_year-1y"` |
| da inizio anno | `>=` `"@start_of_year"` |

Un job pianificato con date relative resta corretto a ogni esecuzione; con date fisse no.

## Esempi

### Testo esatto / contiene / inizia per

```json
{"field": "descr", "op": "=", "type": "string", "value": "COLLABORATORI"}
{"field": "descr", "op": "contains", "type": "string", "value": "COLLAB"}
{"field": "codice", "op": "starts_with", "type": "string", "value": "ART_"}
```

### Numero e intervallo di date

```json
[
  {"field": "arcmovc.csott", "op": "=", "type": "number", "value": "190"},
  {"field": "arcmovc.datareg", "op": "between", "type": "date", "value": "01/01/2025,31/07/2025"}
]
```

### Uno tra N valori / nessuno tra N valori

```json
{"field": "arcmovc.caumovc", "op": "in", "type": "string", "value": ["AM", "RI"]}
{"field": "arcmovc.caumovc", "op": "not_in", "type": "string", "value": "AM,ex,RI"}
```

### Campo vuoto / valorizzato

```json
{"field": "note", "op": "is_empty"}
{"field": "email", "op": "is_not_empty"}
```

### OR tra condizioni (anche su campi diversi)

```json
{"type": "group_or", "filters": [
  {"field": "citta", "op": "=", "type": "string", "value": "Milano"},
  {"field": "provincia", "op": "=", "type": "string", "value": "MI"}
]}
```

Un solo livello (niente `group_or` dentro `group_or`), 2..10 filtri per gruppo, massimo 5 gruppi e 40 condizioni totali. Il gruppo e in AND con gli altri filtri.

### Confronto tra due campi (residui, ritardi)

```json
{"field": "righe.qta_evasa", "op": "<", "type": "field_number", "value": "righe.qta_ordinata"}
{"field": "data_consegna", "op": ">", "type": "field_date", "value": "data_prevista"}
```

## Qualificazione del campo

- Se la query della TabellaBase e **senza join** e il campo non e ambiguo, il nome **non qualificato** della colonna fisica e la scelta piu sicura.
- Se la query ha join, o il nome e ambiguo, **qualifica con il nome della tabella/vista nel `FROM`** (che puo differire dal `table_name`).
- Non qualificare mai con l'alias di lista e non usare il `table_name` se la `FROM` usa una vista diversa.
- La stessa regola vale per il `value` dei `field_*` e per i filtri dentro `group_or`.

## Relazione con `output_fields`, `sort` e `descriptor`

- `search.field` → **colonna fisica** (`single_fields[].name`, `ai_instructions`).
- `output_fields` e `sort[].field` → **alias di lista** elencati in `output_fields_allowed`.
- Sono due spazi di nomi diversi nello stesso tool: filtra con `descr`, stampa e ordina per `descrizione`.
