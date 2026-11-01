# Errori e warning dell'evasione

Gli errori di `pn_document_session_evade_rows` sono atomici: se una riga non e valida **nessuna** riga viene aggiunta. Correggi l'elemento indicato e richiama.

## Errori (bloccanti)

| error_code | Significato | Rimedio |
|---|---|---|
| `target_causale_missing` | La sessione non ha la causale | `pn_document_new_start` / `pn_document_new_set_header` con `document_type_code`, poi richiama |
| `target_type_not_supported` | Causale non ammessa (lista prelievo, proforma, ordine...) | Usa carico, DDT, fattura o fattura di acquisto |
| `target_causale_does_not_evade` | La causale non movimenta il magazzino, quindi non aggiornerebbe l'evaso | Proponi una causale che movimenta. Non ripiegare su `row_add` |
| `source_document_not_found` | Codice ordine inesistente | Ricerca di nuovo il documento |
| `source_not_evadable` | Non e un ordine evadibile, la causale e non evadibile, oppure l'ordine e del tipo opposto (ordine cliente su sessione fornitore o viceversa) | Verifica documento e intestatario |
| `counterparty_mismatch` | Ordine di un altro fornitore/cliente rispetto alla sessione | Un documento per intestatario: apri un'altra sessione |
| `currency_mismatch` | Valuta dell'ordine diversa dalla sessione | `pn_document_new_set_header` con `currency`, poi richiama |
| `row_not_found` | `row_id`/`line_number`/`product_code` non presente nell'ordine | Usa gli identificativi di `pn_document_evadable_rows` (il messaggio indica l'intervallo di righe valido) |
| `row_not_evadable` | Riga gia evasa o chiusa a saldo | Chiedi all'utente: forse e gia stata caricata/fatturata |
| `ambiguous_product_code` | Stesso articolo su piu righe evadibili | Scegli il `row_id` tra i `candidates` |
| `nothing_to_evade` | Nessuna quantita residua (o gia tutta in sessione) | Verifica con `pn_document_evadable_rows` passando `session_code` |
| `edit_session_not_supported` | Sessione di modifica di un documento salvato | L'evasione si fa solo su documenti nuovi |
| `invalid_arguments` | Parametro non valido, compreso `original_document_number` uguale al codice dell'ordine | Correggi secondo il messaggio |
| `evasion_row_product_locked` | (`row_update`) cambio articolo su riga di evasione | Rimuovi la riga e aggiungine una libera |
| `row_description_mismatch` | Il `row_id`/`line_number` indicato non e la riga con `expected_description` (abbinamento sfasato) | Rileggi `row_id` dalla `rows_table` di `pn_document_evadable_rows` (eventualmente con `line_numbers`) e richiama: nessuna riga e stata aggiunta |

## Warning (non bloccanti, da riportare all'utente)

| Warning | Significato |
|---|---|
| `over_delivery` | Quantita oltre il residuo dell'ordine: ammessa, ma va detto all'utente |
| `evasion_residual_changed` | Al save il residuo attuale e minore della quantita evasa (un altro documento lo ha consumato nel frattempo) o la riga e stata chiusa |
| `original_document_already_registered` | Lo stesso documento del fornitore (numero + data) e gia registrato su un altro documento: possibile doppio caricamento, chiedi conferma |
| pagamenti / agenti diversi | Hai evaso ordini con condizioni di pagamento o agenti diversi nello stesso documento |

## Errori gia visti in produzione (da non ripetere)

- **Righe ricopiate con `row_add`**: documento salvato senza collegamento all'ordine, ordine ancora aperto, righe gia evase fatturate una seconda volta.
- **Codice ordine in `original_document_number`**: non crea alcun collegamento; su fatture viene interpretato dalla logica acconti.
- **`line_number` indovinati** in `pn_document_session_evade_rows`: errore `row_not_found`, tentativi a vuoto.
- **"Evadi tutto e correggi dopo" per `line_number` di sessione**: quantita applicate alla riga successiva (riga descrittiva in testa), save con dati sbagliati, due sessioni di modifica e verifiche extra.
- **Righe ricopiate a mano in uno script**: risposta lunga troncata dal runtime, l'agente ha ricostruito l'elenco righe in Python con un `row_id` sfasato da riga 21 in poi; 6 righe su 8 caricate sull'articolo sbagliato (Scanner al posto di Stampante etichette, Speaker al posto di Caricatore...) e riepilogo all'utente scritto dalla tabella di partenza invece che dalla risposta del tool. Usa `rows_table`, `expected_description` e verifica `evasion.evaded_rows_table`.
- **Stato di evasione letto da una ricerca documenti**: una verifica preliminare ha dichiarato evadibili solo 8 righe su 50 (le altre risultavano "closed" per un errore di lettura del flag saldo, ora corretto); l'evasione e partita da quella lista. Lo stato di evasione si legge solo da `pn_document_evadable_rows`.
- **Abbinamento dedotto dal codice fornitore**: ordine con righe senza articolo (`product_code` = `*`), delega con soli `codice=quantita` del DDT, abbinamento "a intuito" (es. Cuffie ↔ AUD-MIC, Caricatore ↔ CAV-CAT6): circa 30 righe su 50 caricate con la quantita di un altro articolo e salvate senza conferma. Serve la descrizione del DDT; se l'abbinamento non e certo non si salva.
