# Decision tables diagnostiche — allegati

Proiezione operativa dei runbook `DIAG-ATT-001..003`. Fonte canonica:
`40_CAP-20260810-013_Diagnostica.md`.

## DIAG-ATT-002 — Allegato non visibile o non scaricabile

| Sintomo | Verifica | Causa probabile | Azione agente |
|---|---|---|---|
| Allegato non in lista per il record | `pn_tabellabase_list` su `attachments` con tablename/tableid (documenti: `testapiedefatture` normalizzato) | Registrazione mancante (upload riuscito, passo di registrazione fallito) | Spiegare SCN-ATT-003; guidare ri-allegato da UI |
| Record presente ma `tableid` = `DEL_...` | prefisso nel valore `tableid` | Record padre cancellato; motore ha re-marcato (RULE-TBL-017) | Allegato solo storico; spiegare |
| Record presente, `url='false'` | valore colonna `url` | Upload S3 fallito ma record creato | Allegato rotto: nessun fetch possibile; guidare nuovo upload |
| URL presente ma non scaricabile | ACL/oggetto | `attachments_public_private=private` oppure oggetto rimosso/orfano | Verificare config; dichiarare limite; nessun workaround |
| Categoria non visibile in lista | `attachments_categories` vuoto/codice errato | Categoria assente o `category` non corrispondente | QRY-ATT-004 equivalente via TabellaBase |

## DIAG-ATT-001 — Upload fallito (guida, l'agente non osserva il client)

| Messaggio riportato | Significato (RULE-ATT-001/002, RULE-ATT-004) | Indicazione |
|---|---|---|
| `No File received` | multipart senza campo `file` | verificare il form/client |
| `File size is too big` | `getPathname()` vuoto: limite framework superato | ridurre dimensione |
| `Missing extension querystring parameter` | `/tabelle/attachments/upload` senza `extension` | aggiungere il parametro |
| `Errore durante l'upload dell'attachment` | `uploadGenericAttachment=false`: base64 non valida o upload S3 fallito | verificare payload e config S3 |
| Errore S3 generico | config mancante/credenziali/bucket | verificare `CFG-ATT-002/003` (senza esporre valori) |

## DIAG-ATT-003 — ZIP o email non inviati

| Sintomo | Causa probabile (RULE-ATT-007/008) | Indicazione |
|---|---|---|
| `Errore: allegati mancanti!` | body senza righe | payload vuoto |
| `Errore: email mancante!` / `email non corretta!` | validazione email | correggere indirizzo |
| ZIP con file vuoti | URL privati/assenti: `@file_get_contents` fallisce in silenzio | verificare ACL `CFG-ATT-001` e raggiungibilità oggetti |
| Email non arrivata | `sendMail` fallito senza errore esplicito | verificare configurazione mail tenant |

## Controlli trasversali

- Mai concludere una causa senza almeno una lettura di verifica.
- Mai esporre credenziali AWS (`CFG-ATT-003`).
- Su tenant con `attachments_public_private=private` gli ZIP via UI possono
  produrre file vuoti: segnalarlo come ipotesi prioritaria.
- Ramo tenant `ioniapietre` (RULE-ATT-010/EXT-ATT-001): email di notifica
  post-inserimento su `agenda_event`/`pn_tasks`; non riguarda il tenant
  `progest` (client_unique_code=progest), ma spiegarlo se richiesto in
  contesto multi-tenant.
