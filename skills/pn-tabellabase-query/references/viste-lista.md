# Viste di lista personalizzate: colonne visibili e raggruppamento

Quando l'utente vuole **vedere solo alcune colonne** nella lista ("mostrami solo codice, ragione sociale e citta", "togli le colonne che non servono") o **raggruppare** ("raggruppa per nazione"), non rispondere solo con i dati: crea una vista personale con `pn_tabellabase_list_view_create` e restituisci il link.

## Quando usarla

- L'utente nomina esplicitamente le colonne da vedere, oppure dice "metti/nascondi/aggiungi la colonna X".
- L'utente chiede il raggruppamento della lista per una o piu colonne.

Quando **non** serve: una singola domanda a cui rispondi direttamente (un totale, una lookup, un elenco breve). In quel caso rispondi con i dati, senza creare viste.

## Prima di chiamarla

1. `pn_tabellabase_descriptor(table_name)` (compact) per questa tabella.
2. Prendi i nomi colonna dalle colonne della lista (il campo `data`/`name` del descriptor). Usa solo nomi che esistono: se il server rifiuta, riporta i nomi ammessi dall'errore.
3. Decidi l'ordine di visualizzazione (il primo e il piu a sinistra).

## Parametri

| Parametro | Obbligatorio | Note |
|---|---|---|
| `table_name` | si | la TabellaBase |
| `title` | si | titolo breve della vista |
| `columns` | si | 1-40 nomi colonna, nell'ordine di visualizzazione |
| `grouping` | no | fino a 3 nomi, in ordine di profondita (il primo raggruppa, il secondo nidifica). Devono essere tra le `columns` |
| `search` / `keyword` | no | filtri che verranno messi **solo nel link**, non salvati nella vista |

## Risposta

- `view_id`, `reused` (`true` se l'utente ha gia' una vista identica: niente duplicati).
- `urls.list`: il link alla lista con `custom_dt_fields=<id>` (e `search`/`keyword` se passati). Includilo verbatim nella risposta finale: `[Apri la lista](urls.list)`.
- `urls.edit` / `urls.grouping_edit`: le pagine ProgestNOW dove l'utente puo' modificare colonne e raggruppamento.
- `warnings` con `GROUPING_UNFILTERED` se c'e' raggruppamento senza filtri.

## Regole

- **Mai costruire l'URL a mano**: usa `urls.list` come lo restituisce il tool.
- La vista e' personale (utente corrente) e non diventa mai il default dell'utente: il link funziona solo per chi l'ha creata (o per viste gia' condivise).
- Il raggruppamento carica **tutte** le righe della lista (niente paginazione): se la tabella e' grande, passa filtri `search` per restringerla, oppure avverti l'utente.
- Non usare `pn_tabellabase_new` su `config_tabellabase_list` per creare viste: il tool dedicato valida le colonne, forza l'utente corrente e deduplica.

## Esempio

Utente: "clienti Italia o Francia, mostra solo codice, ragione sociale e citta, raggruppati per nazione".

1. `pn_tabellabase_descriptor("arccli")`.
2. `pn_tabellabase_list_view_create(table_name:"arccli", title:"Clienti estero essenziale", columns:["codice","ragionesociale","citta"], grouping:["nazione"], search:[{"field":"arccli.nazione","op":"=","type":"string","value":"IT"},{"field":"arccli.nazione","op":"=","type":"string","value":"FR"}])`.

Nota: due filtri `=` sullo stesso campo sono in OR tra loro (semantica lista documenti); se il tenant usa un pattern diverso (es. `collection_or`), segui il descriptor e `references/filtri.md`.

3. Risposta: `[Apri la lista](urls.list)` con `custom_dt_fields=<id>&search=...`.
