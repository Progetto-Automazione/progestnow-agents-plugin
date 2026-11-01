---
name: notifications-support
description: Creazione, invio, lettura, assegnazione, marcatura letta e diagnosi delle notifiche interne in-app di ProgestNOW (pn_notifications + pn_notifications_users). Attiva quando l'utente chiede di notificare utenti/gruppi dentro il gestionale (campanella del header), di pubblicare un avviso visibile a utenti specifici, di elencare/leggere notifiche, assegnare destinatari, segnare come lette, o diagnosticare notifiche che non compaiono nella barra o contatore non lette che non si azzera.
metadata:
  knowledge_refs:
    - CAP-20260812-014
    - DATA-NOT-001..004
    - RULE-NOT-001..008
    - CFG-NOT-001..002
    - SCN-NOT-001..006
    - DIAG-NOT-001..003
    - QRY-NOT-001..005
    - EXT-NOT-001
---

> **Nel plugin (Claude, Codex).** Questa procedura nasce per il motore ProgestAI: dove differisce, vale questa nota.
> - Questi tool qui non esistono: `pn_email_send`, `pn_document_send_by_email`. Se un passaggio li richiede, usa un equivalente disponibile (il tuo ambiente di esecuzione per calcoli e file, la chat per testi da inviare) oppure dichiara all'utente il limite; non inventare chiamate.

# Supporto notifiche interne in-app (pn_notifications)

## Concetto

Il centro notifiche in-app di ProgestNOW (campanella nel header,
polling di `/shared/notifications/ai/latestnotifications`) si basa su
DUE tabellabase:

- **`pn_notifications`** = testata: una riga per notifica (titolo,
  descrizione, link, quando diventa visibile, come si marca letta).
- **`pn_notifications_users`** = destinatari e stato lettura: una riga
  per ogni coppia (notifica, utente). Una notifica è visibile a un
  utente SOLO se esiste la sua riga (`RULE-NOT-002`); il campo
  `aknowledged_flag` ('0'/'1') e `aknowledged_datetime` tracciano la
  lettura.

Regola d'oro: TUTTE le operazioni passano dalle primitive TabellaBase
(`pn_tabellabase_list/single/new/update/delete`). I servizi backend
`notificationPublish`/`notificationAssign`/`notificationAknowldge`
(PnSharedFunctions) NON sono tool MCP: questa Skill replica la loro
semantica con le primitive sulle due tabelle (dettagli in
`references/data-model.md`). Mai SQL raw.

## Prerequisiti

- Tool TabellaBase read/write disponibili nel job; se assenti, delega a
  PNOWTABELLABASE.
- Knowledge: CAP-20260812-014 via Knowledge MCP.
- Superfici: `pn_notifications` e `pn_notifications_users` (descrittori
  standard `app/config/tabelle/*.json`). Se assenti dal catalogo, usa
  i `table_name` espliciti e segnala la lacuna di catalogo.

## Sequenza operativa

1. **Classifica**: invio/pubblicazione → step 2; lettura/elenco → step
   3; nuovi destinatari → step 4; marca letta → step 5; modifica → step
   6; eliminazione → step 7; anomalia → step 8.
2. **Inviare una notifica** (il lavoro principale):
   a. Risolvi i destinatari con TabellaBase su `fos_user`: id singoli;
      gruppi → utenti con `group_id` = id gruppo; email → utenti con
      quella `email`. Deduplica gli id.
   b. `pn_tabellabase_new` su `pn_notifications` con:
      - `title` (obbligatorio, max 500);
      - `description` (opzionale, html ammesso);
      - `link` (opzionale, path interno assoluto: es.
        `/shared/table/pn_tasks/single/123`; il motore lo renderà
        assoluto);
      - **`publish_datetime` SEMPRE valorizzato** (formato
        `YYYY-MM-DD HH:MM:SS`): ora = visibile subito; futuro =
        programmata; assente/NULL = la notifica NON comparirà MAI
        (`RULE-NOT-002`: serve `publish_datetime IS NOT NULL AND <=
        NOW()`). Nel descriptor il campo è mostrato readonly in UI, ma
        la route di salvataggio usata da `pn_tabellabase_new/update`
        persiste i campi inviati: inviarlo e verificare.
      - NON inviare `pn_creation_date` (gestita dal motore).
   c. Per OGNI destinatario: `pn_tabellabase_new` su
      `pn_notifications_users` con `notification_id` = id creato e
      `user_id`. NON valorizzare `aknowledged_flag` (default '0' =
      non letta) né `aknowledged_datetime`.
      Prima verifica con `pn_tabellabase_list` che la coppia
      (notification_id, user_id) non esista già (dedup, come fanno i
      servizi).
   d. Verifica con rilettura: testata con `publish_datetime`
      valorizzato + una riga utenti per destinatario.
   e. DICHIARA PRIMA: la notifica NON invia email (solo canale in-app);
      `aknowldge_mode` delle righe create via TabellaBase resta il
      default DB `visione` (il campo non è esposto nel descriptor, vedi
      Vincoli).
3. **Leggere/elencare**: `pn_tabellabase_list` su
   `pn_notifications_users` (la query porta titolo notifica e username)
   filtrando per `user_id` e/o `notification_id` e
   `aknowledged_flag`; oppure `pn_tabellabase_list` su
   `pn_notifications` per le testate. Ricorda la regola di visibilità:
   `publish_datetime` <= NOW, altrimenti esiste ma non è visibile.
   Dettaglio: `pn_tabellabase_single`.
4. **Assegnare nuovi destinatari** a una notifica esistente: come step
   2c (una riga per destinatario, evitando doppioni).
5. **Marcare letta**: `pn_tabellabase_update` su
   `pn_notifications_users` (primary key `id` della riga):
   `aknowledged_flag`='1' + `aknowledged_datetime` = NOW. Il "segna
   tutte lette" lato UI aggiorna SOLO le notifiche con
   `aknowldge_mode='visione'` (`RULE-NOT-005`); via TabellaBase si
   marcano singole righe: dichiarare la differenza se l'utente chiede
   un azzeramento globale.
6. **Modificare una notifica**: `pn_tabellabase_update` su
   `pn_notifications` (title/description/link/publish_datetime).
   Attenzione: cambiare `publish_datetime` sposta la visibilità.
7. **Eliminare**: il descrittore non ha `delete_also` né hook: NON
   esiste cascata automatica. Prima `pn_tabellabase_delete` delle
   righe `pn_notifications_users` della notifica, poi delete della
   testata. Confermare sempre (operazione distruttiva, nessun
   ripristino).
8. **Diagnosi**: `references/diagnostic-tables.md` (DIAG-NOT-001..003
   proiettati sui tool TabellaBase). Verifica le ipotesi con letture
   prima di concludere; cita runbook e regole canoniche.

## Decision point

- "invia una email a X" → NON è una notifica in-app: usa `pn_email_send`
  (o `pn_document_send_by_email`); questa Skill non invia email.
- "email/push programmati per dopo" → canale separato
  `pending_notifications` (RULE-NOT-008): fuori scope, NON toccarlo.
- "la notifica non compare" → controlla in ordine: `publish_datetime`
  (NULL o futuro), riga in `pn_notifications_users` per l'utente,
  `feature_ai_notifications` (CFG-NOT-001).
- "segna tutte lette" non azzera il contatore → notifiche con
  `aknowldge_mode='click'` si marcano solo aprendole singolarmente
  (RULE-NOT-005).
- Promemoria scadenze task (`pn_tasks_alerts`) → Skill tasks-support,
  non questa.

## Fallback

- Superficie non in catalogo: usa `table_name` espliciti e segnala la
  lacuna; permesso negato dalla route → dichiararlo, non aggirare.
- Config `feature_ai_notifications`/`base_url` non leggibili via tool:
  dichiarare `NON_VERIFICABILE_VIA_TOOL` e indicare la verifica UI.
- Descriptor tenant personalizzato (config_personalizzati /
  config_tabellabase_single_permissions): rileggere SEMPRE il
  descriptor effettivo prima di scrivere campi.

## Vincoli

- Sempre pending action per le write (mode execute); mai scrivere
  righe `pn_notifications_users` per destinatari non confermati.
- `publish_datetime` sempre valorizzato: NULL = notifica invisibile.
- `aknowldge_mode` NON è esposto nel descriptor: le notifiche create
  via TabellaBase valgono `visione` (default DB); se serve `click`,
  dichiarare il gap di descriptor (config_personalizzati) senza
  scrivere SQL raw.
- Eliminazione: prima le righe utenti, poi la testata (nessuna
  cascata).
- Mai chiamare gli endpoint `/shared/notifications/*` al posto delle
  primitive (non sono tool MCP); mai SQL raw.
- Il canale `pending_notifications` (email/push schedulati) è fuori
  scope.

## Criteri di completamento

- Invio: testata verificata (id, publish_datetime valorizzato) + N
  righe `pn_notifications_users` verificate, con elenco destinatari.
- Lettura: elenco con stato lettura per utente richiesto.
- Diagnosi: causa conclusa con runbook + regola canonica citati,
  oppure `DA CONFERMARE` motivato.

## Quando fermarsi / delegare

- Permesso negato o superficie assente → fermati e segnala.
- Serve contesto documento/commerciale complesso → delega a PNOWDOC /
  PNOWTABELLABASE.
- Serve il canale email/push schedulato → dichiara il limite di scope.
