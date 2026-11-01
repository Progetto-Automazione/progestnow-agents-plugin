# Data model allegati (verificato su db `progest`, 2026-08-18)

## `attachments` (DATA-ATT-001)

Colonne reali verificate con DESCRIBE (db `progest`):

| Colonna | Tipo | Note |
|---|---|---|
| `id` | int PK | id allegato |
| `tablename` | varchar(255) | tabella del record padre (per documenti: `testapiedefatture`) |
| `tableid` | varchar(255) | chiave con cui la superficie di origine registra il record padre (NON sempre la PK: vedi sotto); prefisso `DEL_` = padre cancellato |
| `title` | varchar(255) | titolo/nome file |
| `description` | mediumtext | descrizione |
| `type` | varchar(20) | `image` / `pdf` / `video` / `other` / vuoto |
| `category` | varchar(10) | codice categoria (`attachments_categories.code`) |
| `url` | varchar(500) | URL S3; valore `false` = upload fallito |
| `fos_user_id` | int | utente che ha caricato |
| `date` | timestamp | data inserimento — **la colonna si chiama `date`, NON `creation_date`** (le QRY-ATT-001/002 canoniche citano `creation_date`: KNOWLEDGE_GAP-001) |
| `tags` | varchar(255) | tag legacy |
| `attachments_tags` | mediumtext | tag (collection_reference) |

Volume su db `progest`: 745 record (2017-11-23 → 2026-08-08), uso attivo.

### Descrittore `attachments.json`

- `query`: `SELECT attachments.*, attachments_categories.title AS
  category_title FROM attachments LEFT JOIN attachments_categories ON
  attachments_categories.code=attachments.category LEFT JOIN
  attachment_tag ON attachment_tag.attachment_id=attachments.id WHERE 1`
  con `GROUP BY attachments.id`.
- Colonne lista: `tablename`, `tableid`, `title`, `description`,
  `category_title`, `type` — **tutte `editable=false`**: la superficie è di
  consultazione; `pn_tabellabase_new`/`update` non possono scriverla.
- Azioni: edit-control, delete-control, url-control (`%%RECORD_URL%%`).
- `manutenzione=true`; pulsanti extra verso `attachments_tags` e
  `attachments_categories`.
- `aggregate_capability`: il `group_by` presente rende probabile
  `supported=false` — verificare con `pn_tabellabase_descriptor`
  (`detail=compact`) prima di usare `pn_tabellabase_aggregate`.

## `attachments_categories` (DATA-ATT-002)

`code`, `title`. LEFT JOIN: allegati senza categoria restano in lista con
`category_title` nullo.

## `attachment_tag` (DATA-ATT-003)

`attachment_id` + colonna tag (nome esatto DA CONFERMARE su db tenant,
QRY-ATT-004).

## Storage S3 (DATA-ATT-004)

- Bucket: `amazon_s3_bucket_name` (tenant `progest`: `progestnow`).
- Regione: `eu-west-1` (fissa nel codice).
- Key: `attachments/{client_unique_code}/{filename}` per allegati
  persistenti; `temp/` per file transazionali (ZIP inclusi).
- ACL: `public-read` se `attachments_public_private` assente o `public`
  (default; tenant `progest`: non configurato → public); `private` se
  `private`.
- Formato URL osservato su db `progest`:
  `https://progestnow.s3.eu-west-1.amazonaws.com/attachments/progest/...`
  → compatibile con l'allowlist di `pn_ai_fetch_file`
  (`progestnow.s3.eu-west-1.amazonaws.com`).

## `pn_app_attachments_tables` (DATA-ATT-005)

Elenco tabelle abilitate agli allegati da app mobile (`tabella`,
`descrizione`).

## `testapiedefatture.has_attachments` (DATA-ATT-007)

Flag mantenuto dal salvataggio documenti (CAP-20260810-002); indicatore UI.

## Chiave di collegamento (`tableid`) — convenzioni verificate

Il `tableid` è la chiave con cui la **superficie di origine** registra il
record padre; **non è sempre la PK** del record. Convenzioni verificate:

| Padre (`tablename`) | `tableid` | Fonte |
|---|---|---|
| documenti (`testapiedefatture`) | `{cidfattura}` | RULE-ATT-004 (normalizzazione `testapiedefatture_*`); `Table::addAttachment` (`Table.php:1437-1477`, `tableid = getId()` = PK) |
| prima nota (`arcmovc`) | `{cidesercizio}-{nmovc}` (es. `2026-63179`), TESTATA | `ContabilitaBundle/.../primanota/single.html.twig` bottone Allegati (filtro `tableid = <idesercizio>-<nmovc>`); `ContabilitaService.php:2159` (`$new_attachment['tableid'] = cidesercizio."-".$nmovc`) |
| altre superfici | da verificare | leggere 2-3 record reali di `attachments` per quel `tablename` e incrociare i valori con `main_field` e PK del descrittore della tabella padre |

Evidenza job 659 (2026-09-16, tenant progest): l'uso dell'`id` di riga
dettaglio `arcmovc` nel `tableid` ha prodotto un falso negativo ("0 su 204
registrazioni con allegato"); la chiave corretta `cidesercizio-nmovc` ha
dato 165/204 registrazioni con allegato. Prima di concludere "nessun
allegato" su un insieme di record, fare un **controllo positivo** su una
registrazione nota per avere allegati.

## Filtri tipici per `pn_tabellabase_list`

```json
{"table_name":"attachments","search":[
  {"field":"attachments.tablename","op":"=","value":"testapiedefatture","type":"string"},
  {"field":"attachments.tableid","op":"=","value":"{cidfattura}","type":"string"}
]}
```

```json
{"table_name":"attachments","search":[
  {"field":"attachments.type","op":"=","value":"video","type":"string"},
  {"field":"attachments.date","op":">=","value":"2026-08-01","type":"date"}
]}
```
