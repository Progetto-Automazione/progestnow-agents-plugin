# Decision tables diagnostiche — notifiche in-app

Proiezione operativa dei runbook `DIAG-NOT-001..003` (KB
CAP-20260812-014) sui tool realmente disponibili. Le query canoniche
`QRY-NOT-*` sono SQL su database tenant: nel runtime agentico NON si
esegue SQL raw; ogni controllo è riformulato con i tool TabellaBase.
Dove un controllo non è eseguibile è marcato `NON_VERIFICABILE_VIA_TOOL`.

## DIAG-NOT-001 — La notifica non compare nella barra

**Domanda**: "Ho pubblicato una notifica ma non la vedo / l'utente non la vede"

| Controllo | Tool | Esito atteso | Causa se fallisce |
|---|---|---|---|
| La testata esiste | `pn_tabellabase_single` su `pn_notifications` | record presente | inserimento mai avvenuto |
| `publish_datetime` valorizzato e <= NOW | rilettura testata | valorizzato e nel passato | **causa più frequente**: NULL o futuro → invisibile (`RULE-NOT-002`); valorizzare via `pn_tabellabase_update` |
| Riga destinatario per l'utente | `pn_tabellabase_list` su `pn_notifications_users` con `user_id`+`notification_id` | 1 riga | utente non assegnato: creare la riga (step 2c/4 della Skill) |
| Interfaccia abilitata | config `feature_ai_notifications` = "1" (`CFG-NOT-001`) | `NON_VERIFICABILE_VIA_TOOL` | dropdown non renderizzato se "0": dichiararlo e indicare verifica UI |

**Conclusioni ammesse**: publish_datetime mancante/futuro / utente non
assegnato / feature disattivata (`DA CONFERMARE` via UI) / problema
frontend (polling 20s, pagina non attiva).

## DIAG-NOT-002 — Il contatore delle non lette non si azzera

| Sintomo | Verifica | Causa probabile | Azione agente |
|---|---|---|---|
| Non letta residua dopo "segna tutte lette" | `pn_tabellabase_list` su `pn_notifications_users` per user con `aknowledged_flag`='0' | Notifica con `aknowldge_mode='click'`: il blocco "all" marca solo `visione` (`RULE-NOT-005`) | Spiegare; marcare la singola riga via `pn_tabellabase_update` (flag='1' + datetime) |
| Riga non letta anche su notifica `visione` | rilettura riga | Acknowledge mai eseguito per quella riga (utente diverso dal richiedente) | Verificare `user_id` della riga; marcare la riga corretta |
| Conteggio 0 ma indicatore acceso | letture | Problema frontend (polling/cache) | Dichiarare lato client |
| Ramo tenant B utenti 28/38 | righe dei due utenti | acknowledge incrociata (`EXT-NOT-001`) | Comportamento tenant: dichiararlo |

## DIAG-NOT-003 — Coda email/push programmata

Fuori scope: riguarda `pending_notifications` (RULE-NOT-008), canale
separato dal centro in-app. Risposta knowledge-level citando il
runbook; nessuna primitiva TabellaBase della Skill agisce su quella
coda.

## Rischi sulle scritture via TabellaBase

| Operazione | Rischio | Da dichiarare |
|---|---|---|
| `pn_tabellabase_new` su `pn_notifications` senza `publish_datetime` | notifica invisibile per sempre (NULL) | sempre valorizzarlo e rileggere |
| righe `pn_notifications_users` duplicate | doppioni sulla coppia (notification_id, user_id) | verificare con list prima di inserire |
| delete testata senza rimozione righe | righe orfane in `pn_notifications_users` (nessuna cascata/`delete_also`) | eliminare prima le righe utenti |
| `aknowldge_mode` richiesto 'click' | campo non esposto nel descriptor: non settabile via TabellaBase | dichiarare il gap (config_personalizzati), non scrivere SQL raw |

## Controlli trasversali

- "Non la vedo" → prima `publish_datetime`, poi assegnazione, poi
  feature flag.
- Le notifiche in-app NON inviano email: se l'utente si aspetta una
  mail, chiarire il canale (pn_email_send / pending_notifications).
- Mai esporre link con dati sensibili non richiesti; i link vengono
  assolutizzati dal motore.
