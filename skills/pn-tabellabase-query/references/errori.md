# Errori frequenti e rimedi

## 1. Il filtro ritorna 0 righe ma il valore esiste

- **Causa**: `field` e un **alias di lista** invece della colonna fisica della `FROM`, oppure e qualificato con il nome sbagliato.
- **Rimedio**: torna a §3 della SKILL.md. Leggi `ai_instructions` del descriptor (se presente), poi `single_fields[].name`. In dubbio `descriptor(detail="full")` e leggi `dttable.query` (la `FROM` e le espressioni `x as y`).
- **Non** concludere "non ci sono dati".

## 2. `Filtro search freesql non ammesso`

- **Causa**: nel `value` c'e SQL, una subquery, un'espressione, o e stato usato un parametro `freesql`.
- **Rimedio**: esprimi il filtro solo con gli oggetti `{field, op, type, value}`: OR con `group_or`, confronti tra campi con `field_number`/`field_date`/`field_string`, liste con `in`/`not_in`, vuoti con `is_empty`/`is_not_empty`, date relative. Solo se non e esprimibile neanche cosi, estrai con `pn_tabellabase_list` + `output=url` e filtra nel sandbox (`pn_code_exec`).

## 2b. `INVALID_SEARCH` (contratto search v2)

- **Causa**: un filtro non rispetta il contratto: operatore o tipo sconosciuto, combinazione non ammessa (es. `contains` su `number`, `null-empty` con `LIKE`), numero o data non validi, lista vuota, `between` senza due estremi, `group_or` con meno di 2 o piu di 10 figli o annidato, chiave non ammessa.
- **Rimedio**: leggi `path` (es. `search[1].filters[0]`), `hint` e `allowed` e correggi **solo quel filtro**. La query non e stata eseguita: non c'e un risultato parziale da interpretare.
- Esempio: `null-empty` + `<>` va scritto `{"field":"email","op":"is_not_empty"}`.

## 2c. `INVALID_SORT` / `SORT_UNSUPPORTED` / `INVALID_ORDER_BY` / `INVALID_HAVING`

- **`INVALID_SORT`**: `sort[].field` non e una colonna della lista. Usa un alias di `output_fields_allowed`.
- **`SORT_UNSUPPORTED`**: la query della TabellaBase contiene un `LIMIT` e non puo essere riordinata. Estrai con `output=url` e ordina nel sandbox.
- **`INVALID_ORDER_BY`**: `order_by[].name` deve essere il nome di una misura, di un bucket o l'alias dimensione `tabella_campo` (vedi `allowed` nella risposta).
- **`INVALID_HAVING`**: `having[].name` deve essere il nome di una misura e `value` un numero.

## 2d. `TOO_MANY_GROUPS`

- **Causa**: l'aggregazione supera `options.limit_groups` senza `order_by`.
- **Rimedio**: restringi i filtri o le dimensioni; se ti servono i primi N gruppi aggiungi `order_by` su una misura (risposta con `truncated=true`); se ti servono tutti i gruppi usa `output=url`.

## 3. `DATASET_TOO_LARGE`

- **Causa**: l'estrazione con `output=url` supera il limite del dataset.
- **Rimedio**: restringi i filtri (periodo, sottoconto, causale) e/o riduci `output_fields`; oppure spezza l'estrazione per periodo e unisci con `pn_dataset_merge`. In alternativa usa `pn_tabellabase_aggregate` se ti servono solo totali/conteggi.

## 4. `DATASET_REF_NOT_FOUND` / `DATASET_GONE`

- **Causa**: l'URL del dataset e scaduto (~20 minuti) o l'export non esiste piu.
- **Rimedio**: rigenera l'export con una nuova chiamata `output=url`; se hai solo perso l'URL, `pn_ai_dataset_url_renew(dataset_export_id)`.

## 5. La risposta contiene un'anteprima e `dataset_export_id`

- **Causa**: il risultato inline ha superato la soglia (~30 record o ~16k caratteri): `auto_export.applied=true`.
- **Rimedio**: **non** richiedere le righe e **non** paginare. Usa `dataset_export_id` (sandbox/Excel) oppure `pn_tabellabase_aggregate`.

## 6. Vedo `_pn_truncated`

- **Causa**: il runtime ha tagliato il risultato per dimensione.
- **Rimedio**: le parti omesse **non sono nel contesto**. Richiama con filtri piu stretti o `page_size` piu piccolo; non ricostruire a memoria cio che manca.

## 7. `aggregate_capability.supported=false`

- **Causa**: quella TabellaBase non supporta l'aggregazione server-side.
- **Rimedio**: non forzare `aggregate`. Estrai con `output=url` e aggrega nel sandbox.

## 8. `description_snapshot` / scheda assente

- **Causa**: la tabella non ha una riga con scheda in `pn_ai_tabellebase` (nessun `ai_instructions`).
- **Rimedio**: procedi con `descriptor` (`columns`, `single_fields`, `output_fields_allowed`); se serve la scheda, chiedila al catalogo con `names=[table_name]` (potrebbe non esistere ancora). Segnala il gap invece di inventare nomi campo.

## 9. `page_size` alto o lista senza filtri

- **Causa**: pattern sbagliato, non errore del server.
- **Rimedio**: lookup mirato → `output_fields` 2-4 colonne + `page_size` ≤ 10; molte righe → `output=url`; totali → `aggregate`. Mai `page_size` 100 senza filtri stretti.

## Regola generale

Prima di interpretare un esito come "dato assente", verifica **il nome del campo** e **il livello di lettura** (indice/scheda/descriptor). La maggior parte degli errori costosi nasce da un filtro costruito sull'alias di lista.
