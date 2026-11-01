---
name: threads-support
description: Ricerca, lettura, creazione, modifica ed eliminazione dei messaggi/discussioni (pn_threads) in ProgestNOW, e diagnosi delle anomalie (messaggi non visibili, notifiche non arrivate). Attiva quando la domanda riguarda messaggi, discussioni o scambi in stile forum tra utenti collegati a un record (task, ticket, pratica, documento...), commenti su una scheda, notifiche email di nuovi messaggi, o messaggi da aggiungere/modificare/eliminare su un record specifico. Attiva anche quando l'utente chiede di "aggiungere un messaggio/commento/nota su un record" e va chiarito se intende un messaggio forum (pn_threads) o un campo del record stesso.
metadata:
  knowledge_refs:
    - CAP-20260811-003
    - CAP-20260810-012
    - DATA-AIA-011
    - DATA-TBL-010
    - RULE-AIA-010
    - RULE-TBL-017
    - SCN-AIA-008
---

> **Nel plugin (Claude, Codex).** Questa procedura nasce per il motore ProgestAI: dove differisce, vale questa nota.
> - `output=url` non va usato per scaricare dati: il tuo ambiente di esecuzione non raggiunge gli URL ProgestNOW. Restringi i filtri, aggrega lato server con `pn_tabellabase_aggregate`, oppure pagina con limiti piccoli; i calcoli locali li fai sui dati gia restituiti dai tool, nel tuo ambiente di esecuzione, al posto del "sandbox".

# Supporto discussioni e messaggi tra utenti (pn_threads)

## Concetto trasversale

`pn_threads` è il meccanismo generico e trasversale di messaggistica in
stile forum di ProgestNOW: su QUALSIASI record di QUALSIASI tabellabase
gli utenti del gestionale possono scambiarsi messaggi. Un "thread" NON è
una riga a sé: è l'insieme dei messaggi che condividono la stessa coppia
`thread_table_name` + `thread_table_id`. Ogni riga di `pn_threads` è UN
messaggio.

| Campo | Tipo | Note |
|---|---|---|
| `id` | int PK | id messaggio |
| `user_id` | reference fos_user | autore ("Pubblicato da", default `%%CURRENT_USER_ID%%`) |
| `message` | textarea (html) | testo del messaggio |
| `thread_table_name` | varchar(100) | tabellabase del record padre |
| `thread_table_id` | varchar(100) | id/chiave del record padre — varchar: accetta anche chiavi NON numeriche (es. `code` delle pratiche) |
| `pn_creation_date` | timestamp | pubblicazione (auto) |
| `pn_update_date` | timestamp | ultima modifica |

La superficie è `pn_threads` (descrittore `app/config/tabelle/pn_threads.json`,
`manutenzione=true`): lista ordinata per `pn_creation_date DESC` con
edit/delete control; `single_record` con i campi sopra. Le primitive
TabellaBase coprono l'intero ciclo: leggere i messaggi di un record,
aggiungerne, modificarli, eliminarli.

Comportamenti collaterali da conoscere PRIMA di scrivere:

- **Notifiche automatiche** (`PnThreadsController::postInsert`): alla
  creazione di un messaggio, l'hook invia email + notifica in-app SOLO
  quando `thread_table_name` è:
  - `pn_tickets` → avvisa l'apritore del ticket e i partecipanti;
  - `pn_tasks` → avvisa creatore e assegnatario del task + partecipanti
    (creatore in cc se non già destinatario);
  - `zz_sped_pratiche` → verticale spedizionieri (email da
    teama@tenant G.com), avvisa apritore e partecipanti.
  Per qualsiasi ALTRA tabellabase: nessuna notifica automatica nel ramo
  standard (verifica comunque sul tenant: i config_personalizzati
  possono cablare hook diversi).
- **Cancellazione del record padre**: il motore re-marca
  `thread_table_id` con prefisso `DEL_` (RULE-TBL-017, DATA-TBL-010):
  i messaggi restano come storico del record cancellato.
- L'hook gira anche sulle scritture via MCP (stessa route
  `webprogest_shared_table_single`): dichiarare sempre le conseguenze
  notifiche prima di creare un messaggio.

## Messaggio vs nota vs allegato (LEZIONE job 454)

È il fallimento più frequente: l'utente dice "aggiungi un messaggio/una
nota su questo record" e l'agente scrive nel campo `note` del record
padre invece di creare un messaggio forum. Incidente reale (tenant
progest, job 454/455, 2026-08-24): richiesto un "messaggio 'prova' sul
cliente tenant A", l'agente ha aggiornato `arccli.note`; l'utente ha
corretto "intendevo come pn_thread, non come nota".

Regola di disambiguazione PRIMA di scrivere:

| Intenzione dell'utente | Destinazione corretta |
|---|---|
| scambio di messaggi/comunicazione tra utenti visibile sulla scheda (stile forum/chat) | riga in `pn_threads` con `thread_table_name`/`thread_table_id` |
| nota interna che appartiene al record stesso (es. campo `note`/`notes` dell'anagrafica) | campo del record padre via `pn_tabellabase_update` sulla tabella del padre |
| file da allegare | `attachments` (Skill attachments-support) |

In caso di dubbio chiedi PRIMA di scrivere: "intendi un messaggio nella
discussione del record o una nota interna sul record?". Se il record
padre non ha discussioni esistenti e l'utente parla di comunicare con
altri utenti, è `pn_threads`.

## Obiettivo procedurale

Rispondere in modo affidabile a domande e lavori sulle discussioni:
trovare e leggere i messaggi di un record, aggiungerne, modificarli,
eliminarli in sicurezza e diagnosticare anomalie (messaggi non visibili,
notifiche non arrivate), senza mai simulare operazioni prive di
primitiva MCP.

## Prerequisiti

- Tool disponibili nel job: TabellaBase read
  (`pn_tabellabase_catalog`, `pn_tabellabase_descriptor`,
  `pn_tabellabase_list`, `pn_tabellabase_single`); per le scritture
  `pn_tabellabase_new/update/delete`. Se assenti, delega a
  PNOWTABELLABASE.
- Knowledge: CAP-20260811-003 (DATA-AIA-011, RULE-AIA-010, SCN-AIA-008)
  e CAP-20260810-012 (DATA-TBL-010, RULE-TBL-017) via Knowledge MCP.
- Superficie: `pn_threads`. Se assente dal catalogo
  (`pn_tabellabase_catalog`), usa comunque `table_name=pn_threads` in
  descriptor/list e segnala la lacuna di catalogo.

## Sequenza operativa

1. **Classifica la domanda**:
   - ricerca/lettura messaggi di un record → step 2;
   - aggiunta messaggio → step 3;
   - modifica → step 4;
   - eliminazione → step 5;
   - anomalia/troubleshooting → step 6.
2. **Ricerca/lettura**:
   a. risolvi il record padre (documento: `pn_documents_search` →
      cidfattura; task: `pn_tabellabase_single` su `pn_tasks`; ticket:
      id ticket; altrimenti la chiave del record della tabellabase);
   b. `pn_tabellabase_list` su `pn_threads` con `search`:
      `thread_table_name` + `thread_table_id` (entrambi obbligatori: la
      coppia identifica il thread; `thread_table_id` è stringa, NON
      forzarla a numero);
   c. ordine cronologico: la lista è già per `pn_creation_date DESC`
      (più recente in cima); per volumi grandi `output=url`;
   d. dettaglio: `pn_tabellabase_single` su `pn_threads` per il singolo
      messaggio.
3. **Aggiunta messaggio**:
   a. DICHIARA PRIMA le conseguenze: se il padre è `pn_tasks`/
      `pn_tickets`/`zz_sped_pratiche` l'hook post-insert invia email e
      notifiche a creatore/assegnatario/partecipanti; per le altre
      tabellabase nessuna notifica standard;
   b. `pn_tabellabase_new` su `pn_threads` con `thread_table_name`,
      `thread_table_id`, `message` (`user_id` default utente corrente);
   c. pending action in mode execute; verifica con rilettura.
4. **Modifica messaggio**:
   a. identifica il messaggio (step 2) e conferma con l'utente;
   b. `pn_tabellabase_update` su `pn_threads` (es. correzione del testo
      `message`); nessun vincolo di ownership noto lato superficie: per
      prudenza confermare sempre il record;
   c. pending action; verifica con rilettura. `pn_update_date` aggiornata
      dal motore.
5. **Eliminazione messaggio**:
   a. identifica il messaggio e conferma con l'utente record e
      conseguenze (non ci sono notifiche per la cancellazione; il
      messaggio sparisce dal thread);
   b. `pn_tabellabase_delete` su `pn_threads` (pending action);
   c. verifica post-delete con rilettura del thread.
6. **Diagnosi**: applica `references/diagnostic-tables.md`. Verifica le
   ipotesi con letture mirate prima di concludere; cita runbook e regole
   canoniche nella risposta.

## Decision point

- L'utente parla di conversazioni AI/chatbot → NON è `pn_threads`:
  sono `pn_ai_assistants_threads`(+`_messages`) e `pn_ai_agents_sessions`
  (CAP-20260811-003); se chiede thread di un assistente AI, non usare
  questa Skill.
- L'utente dice "aggiungi un messaggio/commento/nota su questo record":
  applica la tabella "Messaggio vs nota vs allegato" sopra; quando
  ambiguo, chiedi prima di scrivere (lezione job 454).
- `thread_table_id` con prefisso `DEL_` → record padre cancellato:
  messaggi solo storico; chiedi conferma prima di operare.
- Record padre con chiave NON numerica (es. `code` pratica): usa la
  chiave stringa esatta, non cercare un id numerico.
- Creare un messaggio su un task con assegnatario = utente corrente:
  l'email automatica all'assegnatario non parte (coincide con chi
  scrive), ma possono essere avvisati creatore/partecipanti.

## Fallback

- Superficie non in catalogo: usa `table_name=pn_threads` esplicito e
  segnala la lacuna; se il permesso è negato dalla route, dichiaralo
  (non aggirare).
- `pn_tabellabase_descriptor` assente dal toolset: NON fermarti e NON
  passare al campo `note` del padre — le primitive essenziali sono
  `pn_tabellabase_list`/`single`/`new`/`update`/`delete` su
  `pn_threads`, i cui campi sono noti (thread_table_name,
  thread_table_id, user_id, message).
- Hook di notifica tenant-specifico (config_personalizzati): non
  assumere il comportamento standard; dichiara "verificare sul tenant"
  se non verificabile via tool.
- Knowledge MCP non raggiungibile: basati solo su dati verificati a
  database e dichiaralo.

## Vincoli

- Mai leggere/scrivere `pn_threads` senza la coppia completa
  `thread_table_name`+`thread_table_id`.
- Tutte le write richiedono mode execute e pending action; la delete è
  definitiva e va confermata.
- Riservatezza: il contenuto dei messaggi può contenere dati personali o
  sensibili: non esportarlo in sedi non autorizzate.
- NON confondere con gli allegati (`attachments`): i file si gestiscono
  con la Skill attachments-support.

## Criteri di completamento

- Lettura: messaggi del thread restituiti con autore, data e id.
- Scrittura: pending action creata (execute) e, dopo esecuzione, record
  verificato con link.
- Diagnosi: causa conclusa con runbook + regola canonica citati, oppure
  dichiarata `DA CONFERMARE` con motivazione.

## Quando fermarsi / delegare

- Permesso negato o superficie assente → fermati e segnala.
- Serve contesto documento complesso → delega/rinvia a PNOWDOC.
- Volumi grandi o analisi aggregata → PNOWTABELLABASE.
