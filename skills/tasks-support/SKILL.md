---
name: tasks-support
description: Ricerca, lettura, creazione, modifica, completamento, eliminazione e diagnosi delle attività/task (pn_tasks) e dei relativi promemoria/reminders (pn_tasks_alerts) in ProgestNOW. Attiva quando la domanda riguarda attività, task, ToDo, cose da fare collegate a un record, scadenze e promemoria di un task, task collegati a documenti/clienti/strutture, task non in agenda, promemoria non arrivati, modifica/aggiunta/eliminazione dei reminders di un task specifico.
metadata:
  knowledge_refs:
    - CAP-20260810-023
    - SCN-TSK-001..010
    - RULE-TSK-001..010
    - CFG-TSK-001..004
    - DATA-TSK-001..008
    - DIAG-TSK-001..004
    - QRY-TSK-001..003
    - EXT-TSK-001
---

> **Nel plugin (Claude, Codex).** Questa procedura nasce per il motore ProgestAI: dove differisce, vale questa nota.
> - `output=url` non va usato per scaricare dati: il tuo ambiente di esecuzione non raggiunge gli URL ProgestNOW. Restringi i filtri, aggrega lato server con `pn_tabellabase_aggregate`, oppure pagina con limiti piccoli; i calcoli locali li fai sui dati gia restituiti dai tool, nel tuo ambiente di esecuzione, al posto del "sandbox".

# Supporto attività/task di piattaforma (pn_tasks) e promemoria

## Concetto trasversale

`pn_tasks` è un concetto trasversale a TUTTE le entità ProgestNOW: su
qualsiasi record di qualsiasi tabellabase si può collegare uno o più task
("cose da fare"). Il collegamento è la coppia `task_table_name` +
`task_table_key` (per i documenti SEMPRE `testapiedefatture` + cidfattura;
altri oggetti reali: `leads_companies`, `structures`, `pratiche` ecc.).

Struttura portante (sempre la stessa su ogni tenant):

| Ruolo | Campo |
|---|---|
| creatore | `user_id` (reference fos_user) |
| assegnatario | `assigned_users` (reference fos_user) |
| data di creazione | `pn_creation_date` (gestita dal motore) |
| previsto completamento | `due_date` + `due_time` |
| titolo | `title` |
| descrizione | `description` |
| note | `notes` |
| tipologia | `pn_type` (catalogo `pn_tasks_types`) |
| stato | `pn_status` (catalogo `pn_tasks_statuses`, default TODO) + `completed` 0-100 |
| pianificazione | `starting_date` + `starting_time` (opzionali) |

È la tipica tabella che su tenant diversi figura nei config_personalizzati
(superfici dedicate, es. `pn_tasks_structures` sul tenant progest) per
aggiungere o nascondere campi: la struttura portante è sempre lei, ma i
campi ESPOSTI o EDITABILI variano per tenant. Regola: PRIMA di ogni
operazione leggi `pn_tabellabase_descriptor` su `pn_tasks` (o sulla
superficie tenant) e lavora sui campi realmente presenti; un campo assente
dal descrittore è una variazione di superficie, non un errore del dato.

Ogni task può avere uno o più **reminders/promemoria**, gestiti in una
tabellabase ad-hoc: `pn_tasks_alerts` (step 6).

## Obiettivo procedurale

Rispondere in modo affidabile a domande e lavori su task e promemoria:
trovarli, leggerli, crearli, modificarli, completarli, eliminarli in
sicurezza, gestire i reminders di un task specifico e diagnosticare le
anomalie (task non in agenda, promemoria non inviati, task scomparso),
senza mai simulare operazioni prive di primitiva MCP.

## Prerequisiti

- Tool disponibili nel job: TabellaBase read
  (`pn_tabellabase_catalog`, `pn_tabellabase_descriptor`,
  `pn_tabellabase_list`, `pn_tabellabase_single`); per le scritture
  `pn_tabellabase_new/update/delete`; per l'agenda
  `pn_agenda_calendar_v3`; per il contesto documento
  `pn_documents_search`/`pn_document_read`. Se assenti, delega a
  PNOWTABELLABASE / PNOWAGENDA / PNOWDOC.
- Knowledge: CAP-20260810-023 via Knowledge MCP
  (`get_capability_context`/`get_canonical_query`).
- Superfici: `pn_tasks` (attività), `pn_tasks_alerts` (reminders).
  Se `pn_tasks_alerts` non è nel catalogo (`pn_tabellabase_catalog`),
  la gestione reminders è limitata: dichiaralo (CATALOG_GAP).

## Sequenza operativa

1. **Classifica la domanda**:
   - ricerca/elenco/dettaglio → step 2;
   - creazione → step 3;
   - modifica/completamento → step 4;
   - eliminazione → step 5;
   - reminders di un task (leggere/aggiungere/modificare/eliminare) → step 6;
   - anomalia/troubleshooting → step 7;
   - operazioni senza tool → step 8 (MAI eseguire).
2. **Ricerca/lettura**:
   a. `pn_tabellabase_descriptor` su `pn_tasks` (campi esposti possono
      variare per tenant);
   b. `pn_tabellabase_list` con `search`:
      - oggetto collegato: `task_table_name` + `task_table_key`
        (documenti: `testapiedefatture` + cidfattura, mai la variante con
        suffisso causale);
      - stato: `pn_status` (TODO/DONE) e/o `completed`;
      - assegnatario: `assigned_users`; date: `due_date`/`starting_date`;
      - la colonna data di creazione è `pn_creation_date`;
   c. dettaglio: `pn_tabellabase_single` con `table_name=pn_tasks` e
      `table_id`; interpreta `task_table_name`/`task_table_key` per
      risalire all'oggetto (se documento, `pn_document_read`);
   d. volumi grandi: `output=url`; conteggi via `pn_tabellabase_aggregate`
      (prima verifica `aggregate_capability` nel descriptor).
3. **Creazione**:
   a. risolvi l'oggetto collegato (documento → cidfattura via
      `pn_documents_search`; anagrafica → codice; ecc.);
   b. raccogli: `title`, `due_date`+`due_time`, eventuali
      `starting_date`/`starting_time`, `assigned_users`, `description`,
      `notes`, `pn_type` (SOLO se il descrittore del tenant lo espone;
      il valore deve esistere in `pn_tasks_types`);
   c. DICHIARA PRIMA: la creazione genera AUTOMATICAMENTE il reminder
      (o i reminders) in `pn_tasks_alerts` e può inviare email/notifiche e,
      sui tenant abilitati, creare eventi Google Calendar (RULE-TSK-005);
   d. `pn_tabellabase_new` su `pn_tasks` (pending action in execute);
   e. verifica con rilettura e conferma id + link.
4. **Modifica/completamento**:
   a. leggi il task (`pn_tabellabase_single`);
   b. DICHIARA PRIMA: il completamento allinea `completed=100` +
      `pn_status=DONE` (e viceversa, RULE-TSK-002) e può inviare email a
      owner/assegnatario se chi modifica è diverso; un cambio di
      `due_date`/`due_time` RIGENERA i reminders (DELETE+recreate);
   c. `pn_tabellabase_update` impostando SOLO `pn_status=DONE` oppure
      `completed=100`, mai entrambi insieme;
   d. verifica con rilettura.
5. **Eliminazione**:
   a. identifica il task e conferma con l'utente record e conseguenze;
   b. DICHIARA PRIMA: l'eliminazione rimuove anche reminders
      (`pn_tasks_alerts`) e messaggi/thread collegati (operazione
      distruttiva, hook postDelete);
   c. `pn_tabellabase_delete` su `pn_tasks` (pending action);
   d. verifica post-delete con rilettura.
6. **Reminders di un task (`pn_tasks_alerts`)**:
   a. **Leggere**: `pn_tabellabase_list` su `pn_tasks_alerts` con
      `search` su `task_id` (la query del descrittore porta già il
      `title` del task). Campi reali: `sending_date`, `sending_time`,
      `email`, `sent_date` (valorizzata dal cron a invio eseguito).
   b. **Via preferenziale**: il reminder è DERIVATO dal task — data/ora
      di invio = `due_date`+`due_time` − anticipo (CFG-TSK-003
      `pn_tasks_alert_standard`, default 60 minuti; override utente
      `fos_user.default_pn_tasks_alert_time`). Per cambiare quando arriva
      il promemoria MODIFICA le date del task (step 4): gli hook
      rigenerano gli alert. L'email del reminder è quella
      dell'assegnatario.
   c. **Gestione diretta** (solo su richiesta esplicita dell'utente,
      sempre con pending action): la superficie `pn_tasks_alerts`
      supporta CRUD via TabellaBase:
      - **modificare**: `pn_tabellabase_update` su `pn_tasks_alerts`
        (es. `sending_date`/`sending_time`, o `email` alternativa);
      - **aggiungere**: `pn_tabellabase_new` su `pn_tasks_alerts`
        (`task_id` = id del task, `sending_date`+`sending_time`, `email`;
        es. un secondo reminder aggiuntivo a un altro orario);
      - **eliminare**: `pn_tabellabase_delete` su `pn_tasks_alerts`
        (cancella un reminder specifico senza toccare il task).
      DICHIARA SEMPRE i limiti: le modifiche dirette sono VOLATILI — una
      successiva modifica del task con cambio date le sovrascrive
      (DELETE+recreate), l'eliminazione del task le rimuove tutte; un
      alert con `sent_date` valorizzata è già stato processato (il cron
      marca PRIMA dell'invio, FIND-IMP-006: non ci sono retry). MAI
      creare alert manuali al posto di configurare il task: se il
      risultato si ottiene modificando date/assegnazione, usa la via
      preferenziale.
   d. Verifica sempre con rilettura post-operazione.
7. **Diagnosi**: applica `references/diagnostic-tables.md`
   (DIAG-TSK-001..004). Verifica le ipotesi con letture mirate prima di
   concludere; cita il runbook e la regola canonica nella risposta.
8. **Operazioni senza tool** — NON eseguire e NON simulare:
   - inizializzazione task da template;
   - sincronizzazione/diagnosi operativa Google Calendar;
   - lettura del cron `/cronjob/pntasksalerts` (scheduling esterno).
   Spiega il comportamento documentato (KB) e indica la UI corretta
   (pannello Attività del documento, scheda task
   `/shared/table/pn_tasks/single/{id}` con tab reminders).

## Decision point

- L'utente parla di "appuntamento/evento in agenda" → non è un task:
  superficie `agenda_event`/tool `pn_agenda_calendar_v3`, non questa Skill.
- L'utente chiede di un "ticket/assistenza" → fuori scope (pn_tickets_*).
- L'utente chiede di "aggiungere un messaggio/commento sul task" → è una
  discussione: righe `pn_threads` con `thread_table_name='pn_tasks'` e
  `thread_table_id` = id task (Skill threads-support, che notifica
  creatore/assegnatario). Il campo `notes` del task è una nota interna
  del task stesso, NON un messaggio: non confonderli.
- `task_table_key` con prefisso `DEL_` → record padre cancellato: i task
  sono solo storico (RULE-TSK-008); chiedi conferma prima di operare.
- Reminder da cambiare → prima valuta la modifica del task (via
  preferenziale, step 6b); CRUD diretto solo se richiesto.
- "Task non in agenda" → non concludere senza DIAG-TSK-001 completo
  (date + assegnatario + agenda di default + finestra ±2 mesi).

## Fallback

- Superficie non in catalogo: `pn_tabellabase_catalog` per verificare; se
  assente dichiaralo e usa comunque `table_name` esplicito se il permesso
  è concesso; non inventare nomi.
- `pn_tasks_alerts` non raggiungibile → dichiara diagnosi/gestione
  reminders limitata (CATALOG_GAP), non aggirare.
- `pn_agenda_calendar_v3` assente dal toolset → dichiara il TOOLING_GAP
  e guida alla UI agenda; non simulare la lettura della vista.
- Knowledge MCP non raggiungibile: basati solo su dati verificati con i
  tool e dichiaralo.

## Vincoli

- Mai aggiornare insieme `completed` e `pn_status`.
- Mai creare/eliminare alert `pn_tasks_alerts` senza esplicita richiesta
  utente e pending action; la via normale è la modifica del task.
- Mai dichiarare che un task "manca dall'agenda" senza aver verificato
  date + assegnatario + agenda di default + finestra.
- Le write richiedono mode execute e pending action; la delete del task è
  distruttiva (reminders + thread) e va confermata.
- Riservatezza: il campo `email` di `pn_tasks_alerts` contiene indirizzi:
  non esportarlo in sedi non autorizzate.

## Criteri di completamento

- Lettura: record restituito con evidenze e riferimenti.
- Scrittura: pending action creata (execute) e, dopo esecuzione, record
  verificato con link.
- Reminders: stato del task e dei suoi alert riportato con `task_id`,
  `sending_date/time`, `sent_date`; ogni CRUD diretto dichiara la
  volatilità rispetto agli hook.
- Diagnosi: causa conclusa con runbook + regola canonica citati, oppure
  dichiarata `DA CONFERMARE` con motivazione.

## Quando fermarsi / delegare

- Permesso negato o superficie assente → fermati e segnala.
- Serve contesto documento complesso → delega/rinvia a PNOWDOC.
- Serve analisi aggregata/export o diagnosi agenda → PNOWTABELLABASE /
  PNOWAGENDA.
