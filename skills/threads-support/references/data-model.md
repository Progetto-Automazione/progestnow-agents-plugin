# Data model discussioni (verificato su descrittori e controller, 2026-08-24)

## `pn_threads` (DATA-AIA-011, DATA-TBL-010)

Colonne reali verificate con il descrittore
`app/config/tabelle/pn_threads.json`:

| Colonna | Tipo | Note |
|---|---|---|
| `id` | int PK | id messaggio |
| `thread_table_name` | varchar(100) | tabellabase del record padre |
| `thread_table_id` | varchar(100) | id/chiave del record padre; prefisso `DEL_` = padre cancellato |
| `user_id` | int | autore (reference fos_user, default `%%CURRENT_USER_ID%%`) |
| `message` | textarea/html | testo del messaggio |
| `pn_creation_date` | timestamp | pubblicazione (ordinamento lista DESC) |
| `pn_update_date` | timestamp | ultima modifica |

La lista fa LEFT JOIN `fos_user` (username, show_name); colonne visibili:
Pubblicato da (username), Messaggio (html), Pubblicato il
(pn_creation_date). I campi `user_id`/`thread_table_name`/
`thread_table_id` sono nascosti in lista ma presenti nel single_record
(tab "Avanzate" per `thread_table_name`).

Un "thread" = tutte le righe con la stessa coppia
(`thread_table_name`, `thread_table_id`). Non esiste una tabella
contenitore separata: la tabella È piatta (un messaggio per riga).

## Hook post-insert (`PnThreadsController::postInsertAction`)

Alla creazione di un messaggio (anche via MCP, stessa route
`webprogest_shared_table_single`), l'hook `WebprogestTabelleTabelleBundle:PnThreads:postInsert`
notifica via email (+ MagicBell per pn_tickets/pn_tasks):

| `thread_table_name` | Destinatari email | Nota |
|---|---|---|
| `pn_tickets` | apritore del ticket (se diverso da chi scrive) + tutti i partecipanti alla discussione | email "Nuovo Messaggio sulla Richiesta di Assistenza Rif #..."; link alla scheda ticket |
| `pn_tasks` | creatore del task (se diverso da chi scrive) + assegnatario (se diverso) + partecipanti; creatore in cc se non già destinatario | email "... ha aggiunto un nuovo messaggio sull'Attività: {title}" |
| `zz_sped_pratiche` | creatore della pratica (cc se non già destinatario) + partecipanti | verticale spedizionieri; email da `teama@tenant G.com` |
| qualunque altra | nessuna notifica nel ramo standard | verificare i config_personalizzati del tenant |

Nota: l'hook NON filtra i messaggi dell'utente corrente oltre alla
regola "non avvisare chi scrive".

## Cancellazione del record padre (RULE-TBL-017)

`Table::delete` (Table.php:3073-3088) re-marca i riferimenti applicativi:
`pn_threads.thread_table_id` riceve il prefisso `DEL_` (come
`attachments.tableid` e `pn_tasks.task_table_key`). I messaggi restano
come storico leggibile ma non sono più agganciati al record vivo.

## Confini (tabelle simili, NON questa Skill)

| Tabella | Cos'è | Skill/dominio |
|---|---|---|
| `pn_ai_assistants_threads` (+ `_messages`) | thread delle conversazioni con gli assistenti AI | CAP-20260811-003, dominio AI |
| `pn_ai_agents_sessions` | messaggi del modello nei job agentici (JSON) | CAP-20260811-003, dominio AI |
| `pn_tickets` | ticket help-desk (con tab `pn_threads`) | dominio ticket/help-desk |
| `attachments` | file allegati ai record | Skill attachments-support |

## Filtri tipici per `pn_tabellabase_list`

```json
{"table_name":"pn_threads","search":[
  {"field":"pn_threads.thread_table_name","op":"=","value":"pn_tasks","type":"string"},
  {"field":"pn_threads.thread_table_id","op":"=","value":"{task_id}","type":"string"}
]}
```

```json
{"table_name":"pn_threads","search":[
  {"field":"pn_threads.thread_table_name","op":"=","value":"zz_sped_pratiche","type":"string"},
  {"field":"pn_threads.thread_table_id","op":"=","value":"26-043875","type":"string"},
  {"field":"pn_threads.pn_creation_date","op":">=","value":"2026-08-01","type":"date"}
]}
```
