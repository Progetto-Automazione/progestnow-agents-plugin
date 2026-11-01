# Decision tables diagnostiche — task e reminders

Proiezione operativa dei runbook `DIAG-TSK-001..004` (KB
CAP-20260810-023) sui tool realmente disponibili. Le query canoniche
`QRY-TSK-*` sono SQL su database tenant: nel runtime agentico NON si
esegue SQL raw; ogni controllo è riformulato con i tool
TabellaBase/agenda. Dove un controllo non è eseguibile è marcato
`NON_VERIFICABILE_VIA_TOOL` e va dichiarato.

## DIAG-TSK-001 — Task non in agenda (calendar_v3)

**Domanda**: "Perché il task X non si vede nell'agenda?"

1. **Leggi il task**: `pn_tabellabase_single` su `pn_tasks`.
2. **Controllo date** (RULE-TSK-006): `starting_date` e `due_date`
   entrambe nulle/`0000-00-00` → non mostrabile. Proponi valorizzazione
   date (`pn_tabellabase_update`, pending action).
3. **Controllo assegnatario/agenda**: il ramo pn_tasks della vista
   `qryagenda_events` fa INNER JOIN su `assigned_users` e su
   `fos_user.default_agenda_id`: assegnatario nullo/0 o senza agenda di
   default → il task NON compare. (`default_agenda_id`:
   `NON_VERIFICABILE_VIA_TOOL` via TabellaBase; dichiaralo.)
4. **Controllo finestra**: l'agenda applica ±2 mesi senza filtri date
   (`AgendaController.php:238-244`): fuori finestra = atteso.
5. **Controllo completamento**: DONE/`completed=100` resta visibile ma
   marcato `is_completed='si'`: non è "sparito".
6. **Lettura diretta della vista**: usa `pn_agenda_calendar_v3`
   (read-only, tool dedicato) con finestra esplicita se necessario:
   verifica la presenza del task e confronta con i controlli 2-4.
7. **Filtri UI e permessi** (filtro Tipologia "Attività", checkbox
   agenda): competenza UI/utente — guidare l'utente.

**Conclusioni ammesse**: date non valorizzate / assegnazione mancante o
senza agenda di default / fuori finestra (atteso) / completato ma
visibile / causa in permessi o configurazione agenda
(`DA CONFERMARE`).

## DIAG-TSK-002 — Reminder/promemoria non inviato

**Domanda**: "Perché non è arrivato il promemoria del task X?"

| Sintomo | Verifica | Causa probabile | Azione agente |
|---|---|---|---|
| Nessun alert per il task | `pn_tabellabase_list` su `pn_tasks_alerts` con `search` su `task_id` | Alert mai creato: assegnatario senza email, `user_id`/`assigned_users`=0, anticipo non calcolabile (RULE-TSK-003) | Spiegare la generazione automatica; proporre fix dati (assegnatario/email) |
| Assegnatario = creatore, nessuna email | `user_id` = `assigned_users` | Auto-assegnazione: nessuna email BY DESIGN (`_sendAlert`) | Dichiarare comportamento atteso |
| Alert con `sent_date` valorizzata | rilettura alert | Invio eseguito dal cron: problema di recapito, non di motore | Verificare lato email/utente; non riproporre l'invio |
| `sent_date` NULL con `sending_date` passata | rilettura alert | Cron `/cronjob/pntasksalerts` non attivo o invio fallito; `sent_date` marcata PRIMA dell'invio (FIND-IMP-006, nessun retry) | `NON_VERIFICABILE_VIA_TOOL` lo stato cron: dichiararlo |
| Orario errato/alert non dovuto | confronto `sending_date/time` vs `due_date/time` | Anticipo CFG-TSK-003 (default 60') o date errate | Correggere le date del task (via preferenziale: gli hook rigenerano) |

## DIAG-TSK-003 — Google Calendar non sincronizzato

Fuori MVP per il tenant progest (tipi task con
`google_calendar_autocreation='N'`, RULE-TSK-005).

1. `pn_tabellabase_list` su `pn_tasks_types` (se pubblicata) o verifica
   del flag per il `pn_type` del task: 'N' → nessun evento atteso.
2. Solo malerbainfissi/sviluppa (update) e progest (create) hanno il ramo
   attivo.
3. Token/secret utente: `NON_VERIFICABILE_VIA_TOOL` (`fos_user.google_token`,
   FIND-TSK-005): risposta knowledge-level con DIAG-TSK-003 canonico.

## DIAG-TSK-004 — Task scomparso o non collegato all'oggetto

| Sintomo | Verifica | Causa probabile | Azione agente |
|---|---|---|---|
| Task non in lista per l'oggetto | `pn_tabellabase_list` su `pn_tasks` con `task_table_name`+`task_table_key` (documenti: `testapiedefatture` normalizzato) | Collegamento mai creato o chiave divergente (`subject_unique_key` con separatore `___`) | Spiegare SCN-TSK; offrire creazione (step 3) |
| `task_table_key` = `DEL_...` | prefisso nel valore | Record padre cancellato (RULE-TSK-008): task solo storico | Dichiarare; nessuna modifica senza conferma |
| Task migrato su conversione/copia | cercare anche il cidfattura del documento convertito/destinazione (`pn_documents_search` per ricostruire la catena) | Migrazione task su conversione/copia/delete | Riportare la catena documentale |

## Gestione diretta reminders — rischi

| Operazione diretta | Esito atteso | Rischio da dichiarare |
|---|---|---|
| `pn_tabellabase_update` su `pn_tasks_alerts` (sending_date/time/email) | Reminder spostato/destinatario cambiato | Volatile: una modifica del task con cambio date DELETE+recreate lo sovrascrive |
| `pn_tabellabase_new` su `pn_tasks_alerts` | Reminder aggiuntivo | Doppioni se il task viene poi modificato (rigenerazione); valutare prima la via preferenziale |
| `pn_tabellabase_delete` su `pn_tasks_alerts` | Reminder cancellato | La modifica successiva del task può ricrearlo; se `sent_date` valorizzata l'invio era già partito |

## Controlli trasversali

- Mai concludere una causa senza almeno una lettura di verifica.
- Mai esporre indirizzi email (`pn_tasks_alerts.email`) fuori dal
  contesto autorizzato.
- "Non vedo il task in agenda" è la domanda più frequente: applicare
  DIAG-TSK-001 per intero prima di rispondere.
