# Data model notifiche in-app (DDL verificato su tenant progest, 2026-08-24)

## `pn_notifications` (DATA-NOT-001) — testata

DDL reale (tenant progest):

```
id int PK auto
title varchar(500) NULL
description longtext
link varchar(500) NULL
aknowldge_mode varchar(25) NOT NULL DEFAULT 'visione'  -- valori: visione/click
publish_datetime timestamp NULL DEFAULT NULL
pn_creation_date timestamp NULL DEFAULT CURRENT_TIMESTAMP
```

| Colonna | Descrittore | Scrivibile via TabellaBase | Note |
|---|---|---|---|
| `title` | text (caption Titolo) | SI | obbligatoria, max 500 |
| `description` | textarea (Descrizione) | SI | html ammesso |
| `link` | text (Link) | SI | path interno (es. `/shared/table/pn_tasks/single/123`); reso assoluto da `smartUrlComposer` |
| `publish_datetime` | readonly in UI | SI via POST | `loadFieldValuesInTable` lega ogni campo del descriptor dal body POST e `Table::save` esclude solo i readonly di tipo timestamp (`Table.php:2644-2647`): `publish_datetime` viene persistito. SEMPRE valorizzarlo (`Y-m-d H:i:s`): NULL o futuro = non visibile (`RULE-NOT-002`) |
| `aknowldge_mode` | ASSENTE dal descriptor | NO | default DB `visione`; `click`/`visione` decidono la marcatura letta (`RULE-NOT-005`). Via TabellaBase non è modificabile |
| `pn_creation_date` | readonly | NO | default DB CURRENT_TIMESTAMP |

## `pn_notifications_users` (DATA-NOT-002) — destinatari e lettura

DDL reale (tenant progest):

```
id int PK auto
notification_id int NULL
user_id int NULL
aknowledged_flag varchar(1) NOT NULL DEFAULT '0'
aknowledged_datetime timestamp NULL
pn_creation_date timestamp NULL DEFAULT CURRENT_TIMESTAMP
```

| Colonna | Descrittore | Scrivibile via TabellaBase | Note |
|---|---|---|---|
| `notification_id` | reference pn_notifications.id (selectize) | SI | testata collegata |
| `user_id` | reference fos_user.id (selectize) | SI | destinatario; la visibilità per-utente dipende da questa riga (`RULE-NOT-002`) |
| `aknowledged_flag` | referencemanual: '1'=Si (letta), '0'=No | SI | default '0'; '1' = letta |
| `aknowledged_datetime` | datetime | SI | valorizzare con NOW quando si marca letta |
| `pn_creation_date` | readonly | NO | default DB CURRENT_TIMESTAMP |

Lista: query con join su `pn_notifications` (title) e `fos_user`
(username). NESSUNA cascata e nessun hook nel descriptor: eliminare una
testata NON rimuove le righe utenti (vanno cancellate prima).

## Semantica delle primitive PnSharedFunctions (da replicare con TabellaBase)

`FunctionService.php:19658-19933`:

- **`notificationPublish(arrayData, users_id[], groups_id[], user_emails[])`**:
  1. risolve destinatari: id diretti + utenti con `fos_user.group_id`
     nel gruppo + utenti con `fos_user.email` uguale; dedup;
  2. se 0 destinatari o dati vuoti → `false`, nessuna scrittura;
  3. INSERT `pn_notifications` con `title`, `description`, `link`,
     `publish_datetime` (default NOW se assente), `aknowldge_mode`
     (solo se letterale `click` o `visione`, altrimenti non valorizzato
     → default DB `visione`);
  4. INSERT `pn_notifications_users` per ogni destinatario con check
     anti-duplicato sulla coppia (notification_id, user_id).
- **`notificationAssign(notification_id, users_id, groups_id, user_emails)`**:
  aggiunge destinatari a una notifica esistente (stessa risoluzione e
  stesso dedup).
- **`notificationAknowldge(notification_id, user_id=null)`**:
  `aknowledged_flag='1'` + `aknowledged_datetime`=NOW sulla riga
  (notification_id, user_id). Con `notification_id="all"` aggiorna SOLO
  le notifiche con `aknowldge_mode LIKE 'visione'` (`RULE-NOT-005`).
  Ramo tenant tenant B: acknowledge incrociata utenti 28/38 (`EXT-NOT-001`).
- **`notificationsGet`/`notificationsGetCount`** (lettura, `RULE-NOT-002/003`):
  INNER JOIN su `pn_notifications_users`, vincolo
  `publish_datetime IS NOT NULL AND publish_datetime <= NOW()`,
  filtro opzionale `aknowledged_flag` (LIKE senza jolly = uguaglianza),
  limite 500, ordine `publish_datetime DESC`, campo calcolato
  `time_diff`, link assolutizzato con `smartUrlComposer`.

## Endpoint del centro notifiche (non usabili come tool)

`NotificationsController.php`: `/shared/notifications/ai/latestnotifications`
(limit 1..500, default 500), `pendingnotifications`, `unreadcount`,
`aknowldge` (GET `notification_id`, anche "all"), `assign` (POST JSON
`users`+`groups`), `send` (consegna coda `pending_notifications`).

## Non confondere

| Tabella | Cos'è | Skill/dominio |
|---|---|---|
| `pn_notifications` + `pn_notifications_users` | centro notifiche in-app (campanella) | questa Skill |
| `pending_notifications` | coda email/push schedulati (`scheduleNotification`) | fuori scope (RULE-NOT-008) |
| `pn_tasks_alerts` | promemoria scadenze task via cron | Skill tasks-support |
| `pn_threads` | messaggi forum su record | Skill threads-support |
| `mail_sent_log` | registro email inviate | CAP-20260810-014 |

## Filtri tipici per `pn_tabellabase_list`

```json
{"table_name":"pn_notifications_users","search":[
  {"field":"pn_notifications_users.user_id","op":"=","value":"{user_id}","type":"string"},
  {"field":"pn_notifications_users.aknowledged_flag","op":"=","value":"0","type":"string"}
]}
```

```json
{"table_name":"pn_notifications","search":[
  {"field":"pn_notifications.publish_datetime","op":"<=","value":"2026-08-24 12:00:00","type":"string"}
]}
```
