# Decision tables diagnostiche — discussioni (pn_threads)

Proiezione operativa delle regole canoniche (DATA-AIA-011, DATA-TBL-010,
RULE-AIA-010, RULE-TBL-017) sui tool realmente disponibili. Nessun SQL
raw: ogni controllo è riformulato con i tool TabellaBase.

## THR-000 — "Messaggio/nota su un record": dove va scritto (lezione job 454)

Incidente reale (tenant progest, job 454/455, 2026-08-24): richiesto
"aggiungi un messaggio 'prova' al cliente tenant A", l'agente ha scritto
nel campo `note` di `arccli`; l'utente ha corretto "intendevo come
pn_thread, non come nota".

| Richiesta utente | Lettura corretta | Verifica | Azione |
|---|---|---|---|
| "messaggio/commento/nota su questo record" | comunicazione tra utenti stile forum sulla scheda → `pn_threads` | chiedere conferma se ambiguo PRIMA di scrivere | `pn_tabellabase_new` su `pn_threads` con `thread_table_name`+`thread_table_id` |
| "nota interna sul record" | dato che appartiene al record (es. `arccli.note`) | campo presente nel descriptor del padre | `pn_tabellabase_update` sul padre |
| "allegare un file" | file → `attachments` | — | Skill attachments-support |

Il campo `note`/`notes` del record padre NON è mai un messaggio forum:
se l'utente parla di "messaggio", default a `pn_threads` e conferma.

## THR-001 — Messaggi non visibili per il record

| Sintomo | Verifica | Causa probabile | Azione agente |
|---|---|---|---|
| Nessun messaggio in lista | `pn_tabellabase_list` su `pn_threads` con la coppia `thread_table_name`+`thread_table_id` corretta | Thread mai iniziato (nessun messaggio) | Dichiararlo; offrire creazione messaggio (pending action) |
| Messaggi presenti ma con `thread_table_id` = `DEL_...` | prefisso nel valore | Record padre cancellato: motore ha re-marcato (RULE-TBL-017) | Messaggi solo storico; spiegare |
| Chiave non numerica (es. `code` pratica) cercata come numero | valore effettivo della chiave del record | `thread_table_id` è varchar: chiavi alfanumeriche legittime | Rilfiltrare con la chiave stringa esatta |
| Lista vuota ma messaggi esistono | `thread_table_name` errato (es. variante causale del documento) | La coppia identifica il thread: nome tabella diverso = thread diverso | Verificare il nome tabellabase del padre (documenti: `testapiedefatture`) |
| Messaggi visibili in UI ma non via tool | permessi TabellaBase dell'utente MCP sulla superficie `pn_threads` | Route/permessi (RULE-AIA-010) | Segnalare che i permessi vanno verificati; non aggirare |

## THR-002 — Notifica email non arrivata dopo un messaggio

| Sintomo | Verifica | Causa probabile | Azione agente |
|---|---|---|---|
| Padre = `pn_tasks`/`pn_tickets`/`zz_sped_pratiche` e nessuna email | destinatari attesi (creatore/assegnatario/partecipanti) vs mittente | Hook invia SOLO se esistono destinatari diversi da chi scrive; auto-risposta non inviata BY DESIGN | Spiegare la regola (PnThreadsController) |
| Padre = altra tabellabase | ramo hook per quella `thread_table_name` | Nessuna notifica standard per tabellabase generiche | Dichiararlo; verificare eventuali hook tenant (config_personalizzati) come `DA CONFERMARE` |
| Email attesa ma assente | config mail tenant (`platform_email_from` per ticket) | Problema recapito/infrastruttura mail | Dichiarare limite: la consegna non è verificabile via tool |
| Notifica in-app attesa | `notificationPublish` solo nei rami pn_tickets/pn_tasks | Ramo non coperto | Dichiararlo |

## THR-003 — Messaggio da modificare/eliminare: conseguenze

| Operazione | Effetto collaterale | Da dichiarare |
|---|---|---|
| `pn_tabellabase_new` su `pn_threads` | hook post-insert: email/notifiche (solo pn_tasks/pn_tickets/zz_sped_pratiche) | Elencare destinatari attesi prima di creare |
| `pn_tabellabase_update` su `pn_threads` | `pn_update_date` aggiornata; nessuna notifica di modifica | Nessun vincolo di ownership noto: confermare il record |
| `pn_tabellabase_delete` su `pn_threads` | messaggio rimosso definitivamente dal thread; nessuna notifica | Delete distruttiva: confermare |

## Controlli trasversali

- Mai concludere una causa senza almeno una lettura di verifica.
- Sempre la coppia completa `thread_table_name`+`thread_table_id`: un
  solo campo non identifica il thread.
- Il contenuto dei messaggi può contenere dati personali: citare solo
  quanto necessario nella risposta.
- Non confondere `pn_threads` con i thread AI (`pn_ai_assistants_threads`)
  né con gli allegati (`attachments`).
