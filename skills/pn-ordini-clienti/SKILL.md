---
name: pn-ordini-clienti
description: Procedura obbligatoria per ORDINI CLIENTI e PORTAFOGLIO ORDINI in lettura. Attivala PRIMA di rispondere su ordini aperti, da evadere, inevasi, backlog, portafoglio, ordinato, residuo, consegne in ritardo, stato di un ordine, evasione parziale, ordini fermi, ordini per agente o cliente, offerta di origine o DDT e fatture che evadono un ordine. Legge prima la configurazione del tenant (causali O, stati ordine). Evita backlog con ordini annullati, evasione ricalcolata dai documenti a valle, valore residuo preso dalla testata.
metadata:
  scope: core
  requires_skill: pn-tabellabase-query
  related_skills: pn-evasione-ordini, pn-offerte-crm, pn-fatturato-documenti
---

> **Nel plugin (Claude, Codex).** Questa procedura nasce per il motore ProgestAI: dove differisce, vale questa nota.
> - `output=url` non va usato per scaricare dati: il tuo ambiente di esecuzione non raggiunge gli URL ProgestNOW. Restringi i filtri, aggrega lato server con `pn_tabellabase_aggregate`, oppure pagina con limiti piccoli; i calcoli locali li fai sui dati gia restituiti dai tool, nel tuo ambiente di esecuzione, al posto del "sandbox".
> - Questi tool qui non esistono: `pn_code_exec`, `pn_dataset_calculate`. Se un passaggio li richiede, usa un equivalente disponibile (il tuo ambiente di esecuzione per calcoli e file, la chat per testi da inviare) oppure dichiara all'utente il limite; non inventare chiamate.

# Ordini clienti e portafoglio

**Dipendenza.** Sintassi di `search`, `pn_tabellabase_aggregate`, `pn_tabellabase_list`, `output=url`, sandbox: skill `pn-tabellabase-query` (attivala se non è attiva). Mai `freesql`, mai SQL diretto.

**Rimandi.** Evadere un ordine (DDT, fattura, carico), chiudere a saldo: `pn-evasione-ordini`. Offerta e pipeline: `pn-offerte-crm`. Fatturato: `pn-fatturato-documenti`. L'ordinato non è fatturato.

## 1. Modello in breve (dettaglio in `references/modello-dati.md`)

- **Ordine cliente** = documento con `causalimagazzino.tipocausale = 'O'` (flag intestatario `C`). Codici causale diversi per tenant (ORCLI su progest e tenant B; OC e OP su tenant C; oltre 20 su tenant E, inclusi "IMPEGNO" e causali "zzz" dismesse). **Filtra sempre per tipologia**, mai per codice. Ordini fornitore (T) e documenti interni (I) sono fuori.
- **Testata** `testapiedefatture` (TabellaBase `testapiedefatture_O`): `datafattura` (data ordine), `idcliente`, `codage` (agente: **mai** `cidoperatore`, che è chi ha registrato), `nidtipologiaordine` (stato del tenant, decodifica in `tipologieordine`), `n_doc_orig` (cidfattura dell'offerta d'origine), `totaleimponibile` (valore **intero** dell'ordine).
- **Righe** `righefatture`: `quantita`, `quantitaevasa`, `levasioneasaldo` (`S` = chiusa a saldo), `dataconsegna` (solo di riga, spesso vuota), `importototale` (totale riga netto sconti, IVA esclusa), `idriga`.
- **Residuo di riga** = 0 se `levasioneasaldo = 'S'` o `quantitaevasa >= quantita`, altrimenti `quantita − quantitaevasa`. È `qrystatistichedocumenti.riga_quantitadaevadere`.
- **Valore residuo di riga** = residuo × `importototale` / `quantita`. `prezzofinalenetto` (citato in KB, DATA-DOC-002) **non esiste** su DB: non usarlo.
- **Fonte dell'evasione** = `quantitaevasa` + `levasioneasaldo` sulla riga d'ordine, aggiornati dal salvataggio del documento evasore nella stessa transazione (RULE-DOC-019). La vista `qryordevasi` (per ordine: `evaso`, `descrizione_stato` "8 / 8", `totqta`, `totqtaevasa`, `totqtaresidua`) è coerente con questa formula.

## 2. Trappole verificate

1. **Mai ricalcolare l'evasione sommando i documenti con `riferimentorigaordine`.** Il riferimento è propagato a valle: la fattura del DDT e le liste o documenti interni (I) puntano alla stessa riga d'ordine. Su tenant B, marzo 2026, sommando tutti gli evasori 0 righe su 12.176 tornano con `quantitaevasa`. Per sapere **chi** ha evaso un ordine: `pn_document_linked_documents`.
2. **`evaso = N` non vuol dire "niente consegnato"**: su progest vale solo S/N e N include i parziali; su tenant J e tenant C esiste `P` (ordine in una lista di prelievo, prevale su S/N). Per separare aperto da parziale usa le quantità.
3. **Gli stati ordine sono del tenant** (progest: DA VEDERE, VISTO, GESTITO; tenant B: ANNULLATO, FATTURATA, NON FATTURARE, REINTEGRO, SOSTITUZIONE; `tipologieordine.tipocausale` è un elenco, es. "T,O"). Su tenant B 8 ordini ANNULLATO hanno ancora residuo e 31 FATTURATA risultano non evasi: senza leggere gli stati finirebbero nel backlog. Escludi gli stati di annullamento (per descrizione) **dichiarandolo**; se non è chiaro quali stati siano terminali, **chiedi**. Le incoerenze (FATTURATA con residuo) si segnalano, non si correggono.
4. **Agente spesso vuoto**, in misura molto diversa tra tenant (bene circa 100%, tenant F 0%). "Senza agente" è sempre una riga esplicita; se è la maggioranza, l'analisi per agente non è significativa e va detto. `arccli.codage` (agente di default del cliente) solo come ipotesi dichiarata. Possono esistere pseudo-agenti (su progest "Crediti Obsoleti", "Invio fatt. a mezzo email"): riportali con il loro nome.
5. **Righe con `idmagazzino = '*'` non sono sempre descrittive**: sono righe a testo libero e spesso hanno quantità e importo (progest: 970 su 1.545 con importo, evase normalmente). Non escluderle. Una riga senza quantità (`quantita = 0`) ha residuo 0 da sola.
6. **Ordini senza righe** (tenant B: 31) non compaiono in `qryordevasi`: `testa_evaso` nullo. Segnalali a parte.
7. **Valore residuo solo dalle righe**: `totaleimponibile` è il valore dell'intero ordine.
8. **`trg_testapiedefatture_dati` non è una fonte**: è completa solo su alcuni tenant (tenant A), quasi vuota o assente sugli altri.
9. **`causalimagazzino.no_evasione = 1`**: causale d'ordine non soggetta a evasione, esclusa dal "da evadere" (nei tenant verificati vale 0, ma il campo c'è ovunque).
10. **`testapiedefatture_O` non è sempre aggregabile**: su tenant B, tenant C e bene è personalizzata con `GROUP BY tpf.cidfattura` e l'aggregate la rifiuta. Per i conteggi usa `qrystatistichedocumenti` (§4).

## 3. Procedura

1. **Configurazione del tenant** (ricetta R1, una lettura ciascuna):
   a) causali O con `no_evasione = 1`;
   b) `tipologieordine` (stati: quali sono di annullamento o terminali);
   c) valori di `testa_evaso` presenti (S/N, eventuale P) dalla prima aggregate.
2. **Portafoglio e backlog in quantità e conteggi** (per stato, causale, agente, cliente, mese): `pn_tabellabase_aggregate` su `qrystatistichedocumenti` con `testa_causale_tipo = 'O'` (R2, R3, R4).
3. **Valore del backlog**: export delle righe aperte da `qrystampafattura` con `output=url`, poi nel sandbox residuo × `importototale` / `quantita` (R5). L'aggregate non moltiplica.
4. **Ritardi**: righe con residuo > 0 e `dataconsegna` < oggi (R6). Dichiara **sempre** la quota di righe aperte senza data di consegna (su molti tenant è la maggioranza: tenant B 2.436 righe con data su 89.414 nel 2026).
5. **Singolo ordine** (R7): righe e residui (`pn_document_evadable_rows` con `include_closed=yes` se disponibile, altrimenti `qrystampafattura` filtrata per `cidfattura`), evasori con `pn_document_linked_documents`, offerta d'origine da `n_doc_orig`.
6. **Ordini fermi**: ordini aperti senza evasioni (`riga_quantitaevasa` tutta a 0) e con data ordine più vecchia della soglia chiesta (default: oltre 60 giorni, dichiarato), oppure stato bloccato (`tipologieordine.cbloccato = 'S'`).
7. **Controlli di plausibilità** (§5) e risposta (§6).

## 4. Quale fonte per quale domanda (payload in `references/ricette.md`)

| Domanda | Fonte | Ricetta |
|---|---|---|
| Configurazione | `causalimagazzino`, `tipologieordine` (list) | R1 |
| Portafoglio per stato, causale, mese | `qrystatistichedocumenti` aggregate | R2 |
| Per agente, con "senza agente" | `qrystatistichedocumenti` aggregate | R3 |
| Per cliente (conteggi) | `qrystatistichedocumenti` aggregate | R4 |
| Valore backlog (totale, per cliente, agente) | `qrystampafattura` export + sandbox | R5 |
| Consegne in ritardo | `qrystatistichedocumenti` aggregate | R6 |
| Singolo ordine, evasori, offerta | tool documenti | R7 |
| Ordinato del periodo | `testapiedefatture` aggregate | R8 |

`qrystatistichedocumenti` è **una riga per riga di documento** (esiste su tutti i tenant): ordini = `count_distinct` su `testa_cidfattura`, mai `count`; mai sommare `piede_*`. Campi chiave: `testa_causale_tipo`, `testa_causale_codice`, `testa_evaso`, `piede_tipologia_codice`/`piede_tipologia_descrizione` (stato ordine), `testa_agente_codice`/`testa_agente_nome`, `testa_cliente_codice`, `testa_clifor_nome`, `riga_quantita`, `riga_quantitaevasa`, `riga_quantitadaevadere`, `riga_dataconsegna`, `riga_importototale`, `testa_anno`, `testa_mese`.

Stati da escludere: filtro `piede_tipologia_codice` `not_in` gli id di annullamento **in OR con** `is_empty` (altrimenti spariscono gli ordini senza stato).

Domande del tipo "l'ordine contiene il codice X?": se X e' un codice di terzi (codice fornitore/cliente, EAN) e hai il tool `pn_articoli_risolvi_codici`, attiva `pn-identificazione-articoli` passando la controparte del documento; poi cerca l'`idmagazzino` risultante nelle righe del documento. Con esito `probabile` indicalo come probabile; con `ambiguo` o `non_trovato` dichiaralo, non dedurre.

## 4-bis. Regola sui totali e sui conteggi (obbligatoria)

- **Mai sommare a mente più di 3 numeri.** Il totale (ordini aperti, righe, quantità residua) lo calcola il server: un aggregate su `qrystatistichedocumenti` con `testa_causale_tipo = 'O'` **senza dimensioni** o con una sola. Il backlog in valore si calcola nel sandbox (R5).
- **Dettaglio per stato, agente, cliente o mese in una seconda chiamata.** Il totale riportato è quello della prima chiamata, non una somma del dettaglio. Molti gruppi: `pn_dataset_calculate` o sandbox.
- **Prima di rispondere** il dettaglio deve quadrare con il totale (tolleranza 1 € o 1 unità). Se non quadra, NON rispondere: ricalcola.
- **Il numero di ordini da riportare è il `count_distinct testa_cidfattura` dei soli gruppi O, mai `total_matching_records`**:
  - su `qrystatistichedocumenti` e `qrystampafattura` conta le righe;
  - su `testapiedefatture` non filtrata per tipologia conta tutti i documenti del periodo (fatture, DDT, proforma, ordini fornitore).
- Su `testapiedefatture` (R8) filtra `tpf.idcausale` `in` [causali O] da `pn_document_types(document_macro_type="O")`. `cm.tipocausale` non è filtrabile, perché non è nel catalogo campi.
- **Strada secondaria**: se un filtro o una dimensione su un campo della causale (`cm.*`, `testa_causale_tipo`, `tipocausale`) risponde `FIELD_UNKNOWN` / `FIELD_NOT_FILTERABLE`:
  1. prendi i codici con `pn_document_types` o da `causalimagazzino`;
  2. rilancia filtrando il codice causale (`tpf.idcausale`, `testa_causale_codice`, `idcausale`) con `in` + `string`;
  3. al posto della dimensione usa il codice causale.

  Mai `collection` / `collection_or`.

## 5. Controlli di plausibilità (obbligatori)

Riportali nel blocco **"Qualità del dato"** a fine risposta:

- ordini in stato di annullamento con residuo (esclusi o no, dichiaralo);
- stati che indicano "fatturato/evaso" ma con residuo;
- evasioni oltre l'ordinato (`riga_quantitaevasa > riga_quantita`: residuo 0, ma da segnalare);
- ordini senza righe;
- quota di ordini aperti senza agente;
- quota di righe aperte senza data di consegna;
- causali O dal nome anomalo con ordini aperti (IMPEGNO, "zzz", RECLAMO, ACCREDITO): mostrale separate.

## 6. Definizioni da dichiarare nella risposta

- **Ordine aperto** = almeno una riga con residuo > 0, causale con `no_evasione = 0`, stato non escluso (elenca gli stati esclusi).
- **Parzialmente evaso** = aperto e con almeno una riga con `quantitaevasa > 0`.
- **Backlog** = Σ residuo × `importototale` / `quantita` delle righe degli ordini aperti, netto IVA.
- **Ordinato del periodo** = Σ `totaleimponibile` degli ordini con `datafattura` nel periodo, esclusi gli annullati (dichiaralo). Non è fatturato.

Risposta: definizioni usate, periodo o data di riferimento, causali e stati inclusi/esclusi, tabella (ordini, aperti, parziali, quantità residua, valore), blocco "Qualità del dato".

## 7. Scritture

Nessuna. Evadere, chiudere a saldo o annullare: `pn-evasione-ordini` o la UI. Cambiare lo stato di **un** ordine: solo su richiesta esplicita, con conferma e se l'agente ha il tool. Mai modifiche massive.

## 8. Checklist

- [ ] Ho letto causali O, `no_evasione` e `tipologieordine` del tenant?
- [ ] Ho filtrato per tipologia O, non per codice causale?
- [ ] L'evasione viene da `quantitaevasa`/`levasioneasaldo` (o `riga_quantitadaevadere`), non dalla somma degli evasori?
- [ ] Ho escluso gli stati di annullamento dichiarandolo, senza perdere gli ordini senza stato?
- [ ] Ordini contati con `count_distinct` dei gruppi O, mai `total_matching_records`? Totale dalla prima chiamata, dettaglio che quadra?
- [ ] Valore residuo calcolato dalle righe, non da `totaleimponibile`?
- [ ] "Senza agente" e "senza data di consegna" riportati con la loro quota?
- [ ] Blocco "Qualità del dato" presente?
