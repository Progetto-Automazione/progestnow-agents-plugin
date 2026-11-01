# Data model attività e reminders (verificato su descrittori, 2026-08-24)

## `pn_tasks` (DATA-TSK-001)

Colonne reali verificate sui descrittori `app/config/tabelle/pn_tasks.json`
e `pn_tasks_structures.json`:

| Colonna | Tipo | Note |
|---|---|---|
| `id` | int PK | id task |
| `user_id` | reference fos_user | creatore ("Creato da") |
| `assigned_users` | reference fos_user | assegnatario ("Assegnato a"); chiave anche della comparsa in agenda |
| `pn_status` | reference pn_tasks_statuses.code | stato (default TODO) |
| `title` | text | titolo |
| `description` | textarea | descrizione ("Dettagli") |
| `notes` | textarea | note (nascosta nella superficie base) |
| `pn_type` | reference pn_tasks_types.code | tipologia; colonna DB sempre presente ma ESPOSTA solo su superfici tenant (es. `pn_tasks_structures` sul tenant progest, default `IN ASSISTENZA`) |
| `due_date` / `due_time` | date / time | previsto completamento (obbligatori per agenda e reminders) |
| `starting_date` / `starting_time` | date / time | pianificazione (opzionali) |
| `completed` | referencemanual 0-100 | percentuale completamento |
| `completion_date` / `completion_time` | date / time | valorizzati dagli hook al DONE |
| `minutes` | num | minuti lavorati (app) |
| `tags` | collection_reference | tag (`pn_tasks_tags`) |
| `father_task_id` | reference | task padre |
| `task_table_name` | varchar | tabella del record collegato (documenti: `testapiedefatture`) |
| `task_table_key` | varchar | id/chiave del record collegato; prefisso `DEL_` = padre cancellato |
| `pn_creation_date` | timestamp | data di creazione (gestita dal motore, in query ma non nel form) |
| `pn_update_date` | timestamp | ultima modifica |

Lista (`pn_tasks.json`): la query fa JOIN owner/assignee/status
(`owner_user_username`, `assignee_user_username`, `status_title`) e
ordina per `pn_creation_date DESC`. Colonne visibili di default:
Assegnatario, Creato da, Scadenza (`due_date_ita`), Titolo, Descrizione,
Stato, `% Completamento`.

### Trasversalità reale

La coppia `task_table_name`/`task_table_key` punta a QUALSIASI record:
oltre ai documenti (`testapiedefatture*`), esempi concreti nel codice:
`leads_companies`/`leads`/`leads_companies_people` (CRM), `structures`
(structures con `pn_client_unique_code`), `pratiche` (dashboard tenant
con JOIN su `pn_tasks.task_table_name='pratiche'`). Alla cancellazione
del record padre il motore re-marca la chiave con `DEL_` (RULE-TSK-008,
DATA-TBL-010).

### Variazioni tenant (config_personalizzati)

La struttura portante è sempre quella sopra. Su tenant diversi la tabella
figura nei config_personalizzati/superfici dedicate per aggiungere o
nascondere campi: es. `pn_tasks_structures` (tenant progest) espone
`pn_type` (default `IN ASSISTENZA`), tab reminders e attachments,
viewmode calendar/kanban; il descrittore base non espone `pn_type`.
Regola operativa: SEMPRE `pn_tabellabase_descriptor` sulla superficie
effettiva del tenant prima di leggere/scrivere campi.

## `pn_tasks_alerts` (DATA-TSK-002) — reminders

Colonne reali:

| Colonna | Tipo | Note |
|---|---|---|
| `id` | int PK | id alert |
| `task_id` | reference pn_tasks.id | task collegato |
| `sending_date` / `sending_time` | date / time | quando inviare |
| `email` | varchar(100) | destinatario (default `%%CURRENT_USER_EMAIL%%`; di norma l'email dell'assegnatario) |
| `sent_date` | timestamp | marcata dal cron a invio eseguito; NON nel descrittore |

ATTENZIONE: nel descrittore `pn_tasks_alerts.json` i campi legacy
`tableColumns`/`listFields` (Agenda, Data di inizio, Ora fine, ...) sono
residui di un descriptor riciclato da una superficie agenda: IGNORARLI.
Fonte di verità: `tableColumns_new` (titolo task, sending_date,
sending_time, email) e `single_record.fields` (id, task_id,
sending_date, sending_time, email).

Chi scrive il dato (RULE-TSK-003):
- `_createAlert` alla creazione del task (INSERT; anticipo da
  CFG-TSK-003 `pn_tasks_alert_standard`, default 60 minuti; override
  utente `fos_user.default_pn_tasks_alert_time`);
- `postUpdate` del task: DELETE + ricreazione se cambiano
  `due_date`/`due_time`;
- `postDelete` del task: DELETE di tutti gli alert;
- cron `/cronjob/pntasksalerts`: invio (email + MagicBell) e UPDATE
  `sent_date` — marcata PRIMA dell'invio (FIND-IMP-006: nessun retry).
- Assegnatario senza email o `user_id`/`assigned_users` = 0 → nessun alert.

Conseguenza operativa: i CRUD manuali via TabellaBase sono supportati
dalla superficie (edit/delete/new) ma VOLATILI rispetto agli hook.

## Tabelle di supporto

- `pn_tasks_statuses` (DATA-TSK-003): `code` (TODO, DONE, ...), `title`,
  `ordering`.
- `pn_tasks_types` (DATA-TSK-004): `code`, `description`, e a livello DB
  `google_calendar_autocreation` (non nei JSON) per i tenant con
  autocreazione eventi Google Calendar (RULE-TSK-005; sul tenant progest
  i tipi hanno flag 'N' → nessun evento atteso).
- `pn_tasks_tags` (tag), `pn_tasks_sessions`/`pn_tasks_favorites`
  (app PN Workstation, gestite via `/shared/app/task/*`).

## Filtri tipici per `pn_tabellabase_list`

```json
{"table_name":"pn_tasks","search":[
  {"field":"pn_tasks.task_table_name","op":"=","value":"testapiedefatture","type":"string"},
  {"field":"pn_tasks.task_table_key","op":"=","value":"{cidfattura}","type":"string"}
]}
```

```json
{"table_name":"pn_tasks","search":[
  {"field":"pn_tasks.assigned_users","op":"=","value":"{user_id}","type":"string"},
  {"field":"pn_tasks.pn_status","op":"=","value":"TODO","type":"string"},
  {"field":"pn_tasks.due_date","op":"<=","value":"2026-08-31","type":"date"}
]}
```

```json
{"table_name":"pn_tasks_alerts","search":[
  {"field":"pn_tasks_alerts.task_id","op":"=","value":"{task_id}","type":"string"}
]}
```
