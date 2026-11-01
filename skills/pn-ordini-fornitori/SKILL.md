---
name: pn-ordini-fornitori
description: Procedura obbligatoria per ORDINI A FORNITORE e MERCE IN ARRIVO in lettura. Attivala PRIMA di rispondere su ordini fornitore aperti, merce da ricevere, in arrivo, ordinato a fornitore, consegne in ritardo, ricevimenti parziali, puntualità fornitori, stato di un ordine fornitore, residuo da ricevere, carichi che evadono un ordine. Legge prima la configurazione del tenant (causali T, stati, valute). Evita di confondere richieste d'offerta e carichi con ordini, ricevuto gonfiato da chiusure a saldo, valute sommate.
---

> **Nel plugin (Claude, Codex).** Questa procedura nasce per il motore ProgestAI: dove differisce, vale questa nota.
> - `output=url` non va usato per scaricare dati: il tuo ambiente di esecuzione non raggiunge gli URL ProgestNOW. Restringi i filtri, aggrega lato server con `pn_tabellabase_aggregate`, oppure pagina con limiti piccoli; i calcoli locali li fai sui dati gia restituiti dai tool, nel tuo ambiente di esecuzione, al posto del "sandbox".
> - Questi tool qui non esistono: `pn_code_exec`, `pn_dataset_calculate`. Se un passaggio li richiede, usa un equivalente disponibile (il tuo ambiente di esecuzione per calcoli e file, la chat per testi da inviare) oppure dichiara all'utente il limite; non inventare chiamate.

# Ordini a fornitore e merce in arrivo

**Dipendenza.** Sintassi di `search`, aggregate, liste, `output=url` e sandbox: skill `pn-tabellabase-query` (attivala se non è attiva). Mai `freesql`, mai SQL diretto.

**Rimandi**: caricare, evadere o chiudere a saldo → `pn-evasione-ordini`; lato vendita → `pn-ordini-clienti`; pagamenti → `pn_document_payments_status`.

## 1. Modello in breve (dettaglio in `references/modello-dati.md`)

**Ordine fornitore**: documento con `causalimagazzino.tipocausale = 'T'` e `flagidcliente_idfornitore = 'F'`. Il codice causale cambia da tenant a tenant (su tenant A `ORFOR`): filtra **sempre per tipologia**, mai per codice.

Non sono ordini fornitore le richieste d'offerta a fornitore (**R** con flag F, tenant A `RICHO`) né i documenti di magazzino **M**: carichi da fornitore (`CAR`), ma anche resi da cliente, rettifiche, produzione e inventario. Alcuni tenant hanno causali T che non sono acquisti, ad esempio `ORDPR` "ORDINE PRODUZIONE" su progest: mostrale separate.

Il flag F con `movimentaquantitacaricata = '+'` **non** identifica i carichi da fornitore. Il documento che evade si riconosce dal collegamento di riga, non dalla causale.

**Testata** (`testapiedefatture`, TabellaBase `testapiedefatture_T`):

| Campo | Significato |
|---|---|
| `datafattura` | data dell'ordine |
| `idfornitore` | fornitore → `arcfor` (nella query del descriptor `arcfor` è in join **con alias `arccli`**) |
| `cidoperatore` | **buyer**, chi ha emesso l'ordine. `codage` sugli acquisti non ha significato |
| `nidtipologiaordine` | stato del tenant → `tipologieordine` |
| `idvaluta`, `cambio` | valuta del documento |
| `riferimento`, `n_doc_orig` | collegamenti testuali, inaffidabili (§2.4) |
| `totaleimponibile` | valore dell'**intero** ordine, non il residuo |

**Righe** (`righefatture`): `quantita`, `quantitaevasa`, `levasioneasaldo`, `dataconsegna`, `importototale` (netto sconti di riga), `idriga`, `idmagazzino`.

**Residuo di riga** = 0 se `levasioneasaldo = 'S'` oppure se `quantitaevasa >= quantita`; altrimenti `quantita − quantitaevasa`. In `qrystatistichedocumenti` è già calcolato in `riga_quantitadaevadere`.

**Valore residuo** = residuo × `importototale` / `quantita`. È nella valuta del documento, non comprende spese né sconti di testata.

**Fonte dell'evasione** = `quantitaevasa` + `levasioneasaldo` sulla riga d'ordine. Il salvataggio del carico (righe con `riferimentorigaordine = idriga`) le aggiorna nella stessa transazione: RULE-DOC-019; per il WMS RULE-WRC-005.

**Chi ha evaso un ordine**: `pn_document_linked_documents`.

## 2. Trappole verificate (tenant A, ordini dal 2025: 3.429 ordini, 185 fornitori)

1. **Mai ricalcolare l'evasione sommando i documenti con `riferimentorigaordine`.** Su alcuni tenant il riferimento è propagato anche a fatture d'acquisto (A, RULE-LNK-003) o a richieste di acquisto (I, RULE-LNK-013): sommare darebbe una doppia evasione.
2. **Ricevuto ≠ evaso.** Una riga chiusa a saldo conta come evasa, ma la merce può non essere mai arrivata. Nel 2026: 132 righe chiuse a saldo senza alcun carico, 148 chiuse a saldo con quantità ricevuta inferiore all'ordinato. Il "ricevuto" è `quantitaevasa` reale: `qryordevasi.totqtaevasa_reale` dove esiste, oppure le righe. Mai `totqtaevasa`, che conta le righe a saldo come interamente ricevute.
3. **Evasione oltre l'ordinato**: ~50 righe nel 2026. Una causa nota è il WMS (FIND-WRC-002): la quantità eccedente viene attribuita all'ultima riga ordine. Il residuo resta 0, ma l'eccedenza va segnalata.
4. **`riferimento` e `n_doc_orig` sono inaffidabili come collegamento.** `riferimento` corrisponde a un documento solo 11 volte su 3.382; `n_doc_orig` vale la stringa `'NULL'` su 3.226 ordini. Usali **solo** dopo aver verificato che il documento puntato esista e di che tipologia è.
5. **Quantità evasa senza carico**: 6 righe nel 2026, probabile carico cancellato. Da segnalare.
6. **Valute miste**: EUR, USD e `FFC`, con 1 ordine in EUR con cambio ≠ 1; negli ordini storici anche `''`, `EURO`, `US$`. Totali **separati per valuta**; accorpa o converti solo dichiarandolo, con una regola verificata.
7. **Righe `*`**: testo libero. Alcune hanno quantità e restano aperte per sempre (spese, note), tenendo l'ordine a `evaso = N`. Escludile dalle quantità e segnalale a parte.
8. **`qryordevasi` varia per tenant**: S/N (N comprende i parziali), a volte `P`. `totqtaevasa_reale` esiste solo su alcuni tenant. `trg_testapiedefatture_dati` non è una fonte.
9. **Stati del tenant**: inutilizzati su tenant A; su tenant B c'è anche **ANNULLATO** (`tipocausale` è un elenco, es. `T,O`). Uno stato di annullamento va escluso dichiarandolo; se non è chiaro quali stati siano terminali, **chiedi**.
10. **WMS in sospeso** (CAP-20260811-011): se `qrywms_tmp_carichi_ordfor` esiste e ha righe per gli ordini richiesti, l'evasione è in sospeso (non confermata): segnalalo. La temporanea non va mai modificata.

## 3. Procedura

1. **Configurazione del tenant** (R1, una lettura ciascuna):
   - causali T con flag e `no_evasione`;
   - causali M flag F con `movimentaquantitacaricata = '+'`, solo per riconoscerle;
   - `tipologieordine` con `tipocausale` contenente `T`;
   - valori di `testa_evaso` presenti;
   - valute degli ordini del periodo;
   - presenza di `qrywms_tmp_carichi_ordfor` nel catalogo.
2. **Ordinato aperto in quantità e conteggi** (per fornitore, buyer, mese): `pn_tabellabase_aggregate` su `qrystatistichedocumenti` con `testa_causale_tipo = 'T'`, `riga_quantitadaevadere > 0`, righe non `*` (R2).
3. **Merce in arrivo (valore)**: export delle righe aperte da `qrystampafattura` (`output=url`), poi nel sandbox residuo × `importototale` / `quantita`, **per valuta** (R3).
4. **Ritardi**: righe aperte con `dataconsegna` < oggi, per fornitore, con giorni di ritardo (R4). Dichiara la quota di righe aperte senza data.
5. **Puntualità**: `dataconsegna` contro la data dell'ultimo carico M collegato: % entro la data, ritardo medio, consegne in più carichi (R5).
6. **Singolo ordine**: righe e residui, carichi con `pn_document_linked_documents`, origine solo se verificata (R6).
7. **Ordini fermi**: aperti, senza ricevimenti, oltre la soglia dichiarata (default 180 giorni), o in stato bloccato (R7).
8. **Controlli di plausibilità** (§5) e risposta (§6).

## 4. Quale fonte per quale domanda (payload in `references/ricette.md`)

| Domanda | Fonte | Ricetta |
|---|---|---|
| Configurazione | `causalimagazzino`, `tipologieordine`, `testapiedefatture_T` aggregate | R1 |
| Ordinato aperto per fornitore, buyer, mese | `qrystatistichedocumenti` aggregate | R2 |
| Valore in arrivo per valuta | `qrystampafattura` export + sandbox | R3 |
| Righe in ritardo | `qrystatistichedocumenti` aggregate / `qrystampafattura` list | R4 |
| Puntualità per fornitore | `qrystampafattura` (righe ordine + righe carico) + sandbox | R5 |
| Singolo ordine con carichi | `pn_document_evadable_rows`, `pn_document_linked_documents` | R6 |
| Ordini fermi, stati | `qrystatistichedocumenti` aggregate con `having` | R7 |

`qrystatistichedocumenti` ha **una riga per ogni riga di documento**: conta gli ordini con `count_distinct testa_cidfattura`, mai `count`, e non sommare `piede_*`.
- Campi: `testa_fornitore_codice` / `testa_clifor_nome` (fornitore), `piede_utente_*` (buyer), `testa_evaso`, `piede_tipologia_*` (stato), `riga_quantitadaevadere`, `riga_quantitaevasa`, `riga_dataconsegna`.
- Non ha la valuta: per gli importi usa `qrystampafattura`.

Domande del tipo "l'ordine contiene il codice X?": se X e' un codice di terzi (codice fornitore/cliente, EAN) e hai il tool `pn_articoli_risolvi_codici`, attiva `pn-identificazione-articoli` passando la controparte del documento; poi cerca l'`idmagazzino` risultante nelle righe del documento. Con esito `probabile` indicalo come probabile; con `ambiguo` o `non_trovato` dichiaralo, non dedurre.

## 4-bis. Regola sui totali e sui conteggi (obbligatoria)

- **Mai sommare a mente più di 3 numeri.** Il totale (ordini aperti, righe, quantità residua) lo calcola il server: un aggregate su `qrystatistichedocumenti` filtrato sulla tipologia T, **senza dimensioni** o con una sola. Il valore in arrivo si calcola nel sandbox, per valuta.
- **Dettaglio per fornitore, buyer o mese in una seconda chiamata.** Il totale riportato è quello della prima chiamata, non una somma del dettaglio. Molti gruppi: `pn_dataset_calculate` o sandbox.
- **Prima di rispondere**, il dettaglio deve quadrare con il totale (tolleranza 1 € o 1 unità). Se non quadra, NON rispondere: ricalcola.
- **Il numero di ordini da riportare è `count_distinct testa_cidfattura`** dei gruppi di tipologia T, **mai `total_matching_records`**: su `qrystatistichedocumenti` e `qrystampafattura` conta le righe; su `testapiedefatture` non filtrata conta tutti i documenti del periodo (ordini clienti, DDT, carichi…).
- **Filtro sulla causale**: su `testapiedefatture_T` usa `tpf.idcausale` `in` [causali T con flag F] (R1a), mai `cm.flagidcliente_idfornitore`.
- **Strada secondaria**: se un filtro o una dimensione su un campo della causale (`cm.*`, `testa_causale_tipo`, `tipocausale`) risponde `FIELD_UNKNOWN` / `FIELD_NOT_FILTERABLE`:
  1. leggi le causali da `causalimagazzino`;
  2. rilancia filtrando per codice causale, con `in` + `string` (`tpf.idcausale`, `testa_causale_codice`, `idcausale`). Mai `collection` / `collection_or`.

  Dettaglio in `references/ricette.md`.

## 5. Controlli di plausibilità (obbligatori)

Da riportare nel blocco **"Qualità del dato"** a fine risposta:

- evasioni oltre l'ordinato;
- righe chiuse a saldo senza carico, o con ricevuto inferiore all'ordinato;
- quantità evase senza carico che le referenzi;
- ordini aperti da oltre 180 giorni;
- valute miste e cambi incoerenti (EUR con cambio ≠ 1);
- righe `*` aperte;
- ordini in stato di annullamento con residuo;
- temporanea WMS con righe in sospeso per gli ordini analizzati;
- quota di righe aperte senza data di consegna.

## 6. Definizioni da dichiarare nella risposta

- **Ordine aperto** = almeno una riga non `*` con residuo > 0, causale con `no_evasione = 0`, stato non terminale. Elenca gli stati esclusi.
- **Merce in arrivo** = Σ residuo × `importototale` / `quantita` delle righe aperte, **per valuta**, netto IVA.
- **In ritardo** = riga aperta con `dataconsegna` passata.
- **Ricevuto** = quantità effettivamente caricata (`totqtaevasa_reale` o somma dei carichi). Non `quantitaevasa` quando la riga è chiusa a saldo.
- **Puntuale** = riga il cui **ultimo** carico ha data ≤ `dataconsegna`. La data è quella richiesta sull'ordine, non una conferma del fornitore.

Struttura della risposta: definizioni, periodo o data di riferimento, causali e stati inclusi/esclusi, tabella (ordini, righe aperte, quantità residua, valore per valuta, righe in ritardo), blocco "Qualità del dato".

## 7. Scritture

Nessuna. Caricare, chiudere a saldo o annullare: `pn-evasione-ordini` o la UI. Cambiare lo stato di **un** ordine: solo su richiesta esplicita, con conferma e se l'agente ha il tool. Fuori perimetro: riconciliazione con le fatture passive, pagamenti, fabbisogni e MRP.

## 8. Checklist

- [ ] Configurazione del tenant letta (causali T, stati, valute, temporanea WMS)?
- [ ] Filtrato per tipologia T, senza RICHO (R) né documenti M?
- [ ] Evasione da `quantitaevasa`/`levasioneasaldo`, non dalla somma dei documenti a valle?
- [ ] Ricevuto distinto da evaso (chiusure a saldo)?
- [ ] Righe `*` escluse dalle quantità e segnalate?
- [ ] Ordini contati con `count_distinct`, mai `total_matching_records`? Totale dalla prima chiamata e dettaglio che quadra?
- [ ] Valore residuo dalle righe, separato per valuta?
- [ ] Origine (ordine cliente, richiesta d'offerta) dichiarata solo dopo aver verificato che il documento esiste?
- [ ] Blocco "Qualità del dato" presente?
