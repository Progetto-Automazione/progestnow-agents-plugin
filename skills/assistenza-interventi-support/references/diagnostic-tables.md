# Decision table diagnostiche — interventi

Le QRY-INTV-*/QRY-TCI-* canoniche sono template SQL per accesso diretto al db
(client mysql-readonly). In un job agentico si replicano con i tool
TabellaBase sugli stessi campi. Mai concludere senza evidenza.

## DIAG-INTV-001 — Intervento non presente nella lista

| # | Verifica (tool) | Se risulta | Conclusione |
|---|---|---|---|
| 1 | `pn_tabellabase_single(interventi, id)` | nessuna riga | record inesistente (mai salvato o eliminato) |
| 2 | come 1, con riga presente | record esiste | procede al punto 3 |
| 3 | `pn_tabellabase_list` con gli stessi filtri usati dall'utente (stato, date, tecnico, impianto) | vuoto con filtri, presente senza | un filtro esclude il record: verificare `statointervento` e `dataintervento` del record |
| 4 | decodifiche vuote in lista (tecnico/impianto/stato/tipoint) | LEFT JOIN senza corrispondenza | referenziale mancante: controllare `manodopera.cidmanodopera`, `structures.id`, `interventi_stato.codice`, `interventi_tipo.codice` |
| 5 | tutto corretto ma l'utente non vede | — | permessi sul descrittore o cache UI (fuori portata agente: dichiararlo) |

## DIAG-INTV-002 — Ricorrenze non generate o errate

| # | Verifica | Se risulta | Conclusione |
|---|---|---|---|
| 1 | `pn_tabellabase_single` sul padre: campi `recurrency`/`repeat_days` | `repeat_days` con `limit.repeat_type=autocreate` | generazione differita per progettazione: nessuna occorrenza immediata attesa (RULE-INTV-005) |
| 2 | come 1 | `repeat_days` vuoto e `recurrency` mai valorizzato | ricorrenza mai configurata |
| 3 | `pn_tabellabase_list` con filtro sul campo `father_id` = id padre | occorrenze presenti | generazione immediata avvenuta; controllare date e stato (TODO, nome "Ricorrente: ...") |
| 4 | come 3, senza occorrenze e `repeat_type` ≠ autocreate | — | generazione fallita: dichiarare e richiedere verifica backend |
| 5 | sintomo "nessuna occorrenza dopo DONE" | — | comportamento standard verificato: hook update non collegati (RULE-INTV-006, FIND-INTV-001). Non è un bug del tenant salvo override del descrittore (DA CONFERMARE) |

## DIAG-INTV-003 — Intervento non collegato o non fatturabile

| # | Verifica | Se risulta | Conclusione |
|---|---|---|---|
| 1 | documento collegato: oggi non verificabile direttamente via MCP (nessun filtro `intervento_id` in `pn_documents_search`); fallback: `pn_documents_search` per cliente dell'impianto + data, poi `pn_document_read` per cercare il riferimento | nessun documento plausibile | documento mai aperto con `intervento_id` (collegamento assente) |
| 2 | `pn_tabellabase_single` intervento → `structures.cod_fatturazione` dell'impianto (via `structures`) | codice vuoto | impianto senza cliente di fatturazione: documento resta senza cliente (atteso) |
| 3 | codice cliente presente ma documento non lo ha | — | possibile join non corrispondente (`structures_subscriptions.id` vs `structures.id`, FIND-INTV-003): dichiarare DA CONFERMARE |
| 4 | `interventi.cidfattura` valorizzato | — | marcatore affidabile SOLO tenant `bene`; altrove non concludere "fatturato" |

## DIAG-TCI-001..003 — Scheda/checklist/firma su commessa

Premessa sul tenant `progest`: le tabelle non esistono → ogni verifica dati è
impossibile; dichiararlo subito e fermarsi.

| DIAG | Sintomo | Causa canonica (da KB) |
|---|---|---|
| DIAG-TCI-001 | scheda vuota o non si apre | intervento inesistente o non collegato a commessa/cliente (`{"success":0,"error":"Nessun intervento trovato"}`); oppure errore SQL mascherato (RULE-TCI-007) |
| DIAG-TCI-002 | risposte checklist perse | salvataggio è delete-and-reinsert (RULE-TCI-004): un salvataggio successivo sovrascrive; payload senza `intervento_id` o `rows` → errore esplicito |
| DIAG-TCI-003 | firma non acquisita / stato non DONE | la POST firma deve completare l'UPDATE di `fine_signature_*`, `fine_data`/`fine_ora` e `stato=DONE` (RULE-TCI-006); errori SQL in produzione non sono intercettati (RULE-TCI-007, FIND-TCI-001..003) |

Regola trasversale: per CAP-20260812-032 gli errori SQL possono essere
silenti (fetch/execSql restituiscono il messaggio come stringa): in diagnosi,
non fidarsi di un "successo" senza verifica di rilettura.
