# Modello dati degli ordini clienti

## 1. Identificazione

- Ordine cliente = `testapiedefatture` con `causalimagazzino.tipocausale = 'O'` (`flagidcliente_idfornitore = 'C'`). Ordini fornitore = T, documenti interni = I, offerte = R, DDT = D, fatture = F.
- Causali O verificate (2026-10-10): progest e tenant B `ORCLI`; bene `ORCLI`; tenant C `OC` (ordine cliente), `OP` (ordine partner); tenant E 22 causali, tra cui `ORCLI`, `ORCLE` (ecommerce), `ORCTL` (conto lavoro), `ORCAM`/`ORCAE` (campionature), `ORCSP`, `ORCLA` (lastre), `ORDNC` (per accredito), `ORPRO` (progetti), `ORCRE` (reclamo), `ORCRF` (rifacimento), `IMPL`/`IMPPR` (impegni), `ORMAG` e `IMPPR` con prefisso "zzz" (dismesse). Mostra le causali con ordini aperti nella risposta: impegni, reclami e accrediti non sono portafoglio commerciale in senso stretto.
- `causalimagazzino.no_evasione = 1`: causale non soggetta a evasione (esclusa dal "da evadere"). Campo presente ovunque, 0 nei tenant controllati.

## 2. Testata (`testapiedefatture`, TabellaBase `testapiedefatture_O`)

| Campo | Significato | Note |
|---|---|---|
| `cidfattura` | codice documento | chiave per tutti i tool documenti |
| `datafattura` | data dell'ordine | |
| `idcliente` | cliente | `arccli.codice` |
| `codage` | agente commerciale | `agenti.idagente` → `agenti.nome`. **Mai** `cidoperatore` (chi ha registrato) |
| `nidtipologiaordine` | stato operativo | decodifica in `tipologieordine`; 0 o nullo = nessuno stato |
| `n_doc_orig` | documento di origine | sull'ordine è il `cidfattura` dell'offerta (RULE-LNK-014) |
| `totaleimponibile` | valore dell'intero ordine, netto IVA | non è il residuo |
| `riferimento` | riferimento libero | sugli ordini fornitore può contenere l'ordine cliente d'origine (RULE-LNK-013) |

La testata standard **non ha una data di consegna**. Solo 5 tenant hanno campi personalizzati (`zz_ionia_delivery_date` su 4, `data_consegna_vettore` su 1).

`testapiedefatture_O` core espone anche, via join: `evaso`, `descrizione_stato`, `perc_evasione`, `totqtaevasa` (da `qryordevasi`), `tipologia_ordine` (descrizione stato), `dataconsegna` (minima delle righe, da `qrymindataconsegnaordini`). Su tenant B, tenant C e bene è personalizzata con `GROUP BY tpf.cidfattura` (tenant C senza join a `qryordevasi`): l'aggregate la rifiuta, la lista e la scheda funzionano.

## 3. Righe (`righefatture`)

| Campo | Significato |
|---|---|
| `idriga` | id riga; le righe evasori puntano qui con `riferimentorigaordine` |
| `idmagazzino` | articolo; `*` = riga a testo libero (spesso con quantità e importo: non è solo descrittiva) |
| `quantita`, `quantitaevasa` | ordinata, evasa |
| `levasioneasaldo` | `S` = chiusa a saldo; ammessi anche `N` e vuoto (tenant B 2026: 17.307 S, 116 N) |
| `dataconsegna` | data di consegna di riga, spesso vuota (tenant B 2026: 2.436 righe con data su 89.414; esistono date "0000-00-00") |
| `prezzounitario`, `percentualesconto_1..3`, `importototale` | `importototale` = quantità × prezzo × sconti, IVA esclusa (verificato su tenant A su tutte le righe; su tenant B 2026 su 89.413 righe su 89.414) |

`prezzofinalenetto` / `prezzofinalenettototale` **non esistono su DB**: li riporta la KB (DATA-DOC-002), ma sono solo proprietà del modello documento lato front-end. Su DB `righefatture` ha `prezzounitario`, `percentualesconto_1..3` e `importototale`. Prezzo netto unitario = `importototale / quantita`.

**Residuo di riga**: 0 se `levasioneasaldo = 'S'` o `quantitaevasa >= quantita`; altrimenti `quantita − quantitaevasa`. Stessa formula di `qrystatistichedocumenti.riga_quantitadaevadere` e di `qrystampafattura.qtaresidua`.

**Valore residuo di riga** = residuo × `importototale` / `quantita` (righe con `quantita > 0`).

**Evasione oltre l'ordinato** possibile (`quantitaevasa > quantita`, tenant B 2026: 378 righe): residuo 0, da segnalare.

## 4. Come si aggiorna l'evasione (RULE-DOC-019, RULE-LNK-003/007, DATA-LNK-002)

Al salvataggio di un documento che evade, il motore documenti aggiorna `quantitaevasa` e `levasioneasaldo` sulle righe d'ordine **nella stessa transazione** (fasi "R" e "A" di `aggiornaQuantitaEvasa`), poi rinfresca `trg_testapiedefatture_dati` dei documenti collegati. Le righe del documento evasore puntano alla riga d'ordine con `righefatture.riferimentorigaordine = idriga`.

Il riferimento viene **propagato a valle**: la fattura emessa da un DDT e le liste o documenti interni (I) puntano alla stessa riga d'ordine. Sommare tutti i documenti con `riferimentorigaordine` conta più volte la stessa evasione (tenant B, marzo 2026: 0 righe su 12.176 coerenti sommando tutti gli evasori, 10.145 contando solo i DDT). Fonte autorevole: `quantitaevasa` + `levasioneasaldo`. Catena dei documenti: `pn_document_linked_documents` (viste `qrydocumenti_documentievasi`, `qryfatture_ddtevasi`), che distingue evasione diretta, fattura di DDT e fattura che evade l'ordine tramite DDT.

## 5. Stato di evasione per ordine: `qryordevasi`

Presente su tutti i tenant, **non** esposta come TabellaBase: si legge tramite `testapiedefatture_O` (campi in join, dove il descriptor li ha) o `qrystatistichedocumenti.testa_evaso`.

| Campo | Significato |
|---|---|
| `cidfattura` | ordine |
| `evaso` | S / N; su tenant J e tenant C anche `P` |
| `descrizione_stato` | "evaso / ordinato", es. "8 / 8" |
| `totqta`, `totqtaevasa`, `totqtaresidua` | totali di quantità dell'ordine |
| `totqtaevasa_reale`, `perc_evasione` | solo su alcuni tenant (progest, tenant B) |

Differenze tra tenant:

- progest: vista su tabella materializzata `trg_qryordevasi` (aggiornata dai trigger), solo S/N; N comprende i parziali. Verificata coerente con il calcolo dalle righe (0 differenze su 1.566 ordini, incluse le righe `*`).
- tenant B: vista con `totqtaevasa_reale`; coerente col calcolo dalle righe sugli ordini 2026; gli ordini senza righe non compaiono.
- bene, tenant C: vista calcolata (`qryordevasi_0`) con `evaso = 'P'` quando l'ordine è in una lista di prelievo (`qryliste_ordini`), che prevale su S/N.
- `totqtaevasa` considera evase anche le righe chiuse a saldo; `totqtaevasa_reale` conta solo il consegnato: per questo `descrizione_stato` può risultare "9 / 8".

## 6. `trg_testapiedefatture_dati`

Tabella materializzata (`evaso`, `totqtaresidua`, `dataconsegna_min`/`max`) presente quasi ovunque ma popolata solo in alcuni tenant: tenant A tutti i 16.204 ordini; tenant B 116 su 18.292; progest 1 su 206; bene 2 su 6.115; assente in 5 tenant di db2. **Non usarla come fonte** salvo verifica che copra tutti gli ordini del periodo.

## 7. Stati ordine (`tipologieordine`)

Campi: `nidtipologiaordine`, `cdesctipologiaordine`, `cbloccato`, `cbloccaproduzione`, `tipocausale` (elenco delle tipologie a cui lo stato si applica, es. "T,O", "P,O"; vuoto = tutte).

| Tenant | Stati |
|---|---|
| progest | 1 DA VEDERE, 2 VISTO, 3 GESTITO (0 = nessuno stato) |
| tenant C | stati di processo condivisi con ordini fornitore e carichi: DA FIRMARE CLIENTE, CONFERMATO - ATTESA PAGAMENTO ACCONTO, LAVORABILE, MERCE ARRIVATA - ATTESA PAGAMENTO SALDO, SPEDIBILE (O); IN PREPARAZIONE, INVIATO, CONFERMATO (T); CARICO DA VALIDARE / VALIDATO (M) |
| tenant B | 3 ANNULLATO, 5 ORDINE IN RIFINITURA, 6 ORDINE IN GESTIONE, 20 REINTEGRO, 21 SOSTITUZIONE, 22 NON FATTURARE, 24 FATTURATA (la maggior parte degli ordini: nessuno stato) |

Incoerenze tenant B da segnalare, non correggere: 8 ordini ANNULLATO con residuo aperto; 31 ordini FATTURATA non evasi.

## 8. Agente

`codage` compilato in misura molto diversa: circa 100% su tenant J e tenant D, 0% su tenant F, parziale su tenant B e progest (varia con il periodo). "Senza agente" è sempre una riga esplicita. `arccli.codage` (agente di default del cliente) solo come ipotesi dichiarata. In `agenti` possono esistere pseudo-agenti usati per altri scopi (progest: "Crediti Obsoleti", "Invio fatt. a mezzo email").

## 9. Viste di riga usate dalle ricette

- `qrystatistichedocumenti`: una riga per riga di documento (tutti i tenant). Campi ordini: `testa_causale_tipo`, `testa_causale_codice`, `testa_evaso`, `piede_tipologia_codice`, `piede_tipologia_descrizione`, `testa_agente_codice`, `testa_agente_nome`, `testa_cliente_codice`, `testa_clifor_nome`, `testa_anno`, `testa_mese`, `testa_data` (testo `aaaa-mm-gg`), `riga_idriga`, `riga_quantita`, `riga_quantitaevasa`, `riga_quantitadaevadere`, `riga_dataconsegna`, `riga_importototale`. Esportabili con `output_fields` solo le 11 colonne del descriptor core: per gli export usa `qrystampafattura`.
- `qrystampafattura`: righe con testata (export R5/R7). `qtaresidua` calcolato; join con `lotti` che può duplicare righe (deduplica su `idriga`).
- Ordini senza righe: compaiono in `qrystatistichedocumenti` con campi riga nulli e `testa_evaso` nullo.
