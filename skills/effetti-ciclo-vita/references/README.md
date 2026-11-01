# Riferimenti — effetti-ciclo-vita

Risorse consultabili on demand (`pn_ai_skill_resource`). La semantica canonica
resta in KB: questi file sono indici di navigazione e tabelle di supporto, non
duplicati integrali.

## Mapping regola → fase Skill

| Regola KB | Fase Skill | Uso |
|---|---|---|
| RULE-EFF-001 | Fase 3 | Selezione documenti idonei (filtro trasfeffetti, causale F/C) |
| RULE-EFF-002 | Fase 1, 3 | Costruzione effetto dalle scadenze (1 effetto per scadenza, segno NC, cambio) |
| RULE-EFF-003 | Fase 3 | Cliente collegato (codsconto), diversa destinazione IBAN, RID banca cliente |
| RULE-EFF-004 | Fase 3 | Marcatura trasfeffetti; blocco/sblocco (FIND-EFF-001) |
| RULE-EFF-005 | UC-05 | Aggiornamento banca solo su non presentati senza banca |
| RULE-EFF-006 | Fase 4 | Validazione distinta (banca univoca, presentato=0, dati obbligatori) |
| RULE-EFF-007 | Fase 4 | File RIBA/RID: ABI/CAB, banca univoca, dati banca completi, raggruppa_riba |
| RULE-EFF-008 | Fase 5 | Composizione trasferimento (righe AVERE cliente + DARE banca, savePn) |
| RULE-EFF-009 | Fase 6 | Composizione insoluti (DARE cliente + AVERE banca, insoluti_postfisso) |
| RULE-EFF-010 | UC-06 | Raggruppamento (cliente/tipo/scadenza, effetti_raggruppati) |

## Stati dell'effetto (tabella effetti)

| Campo | Valori | Significato |
|---|---|---|
| tipo_eff | riba / rid | tipo titolo |
| presentato | 0/1 | presentato in distinta (con datapresentazione, ndistinta) |
| accreditato | 0/1 | accreditato in banca |
| ltrasferito | 0/1 | trasferito in prima nota |
| codicebancapresentazione | nidbanca | banca di presentazione |

Combinazioni da verificare nei casi reali:

- presentato=0, ltrasferito=0 → da presentare (superficie effetti_daraggruppare)
- presentato=1, ltrasferito=0 → presentato, da trasferire (superficie effetti_presentati)
- presentato=1, ltrasferito=1 → trasferito in contabilità
- presentato=1, accreditato=1 → accreditato in banca

## Configurazioni che cambiano il comportamento (CFG-EFF)

| Chiave | Default | Effetto |
|---|---|---|
| raggruppa_riba | 0 | raggruppa per cliente nel file RIBA |
| feature_effetti_diversadest_iban | 0 | ABI/CAB da diversa destinazione |
| generarid_idnsbanca_cli | (vuoto) | RID con banca dal cliente |
| insoluti_postfisso | (vuoto) | suffisso rifpa insoluti |
| raggruppaeffetti_righeseparate | (vuoto) | righe separate in prima nota per partite accorpate |
| feature_ribarid_accorpa_codsconto | 0 | accorpa sul cliente capo |
| feature_ribarid_accorpa_indirizzospedizione | 0 | raggruppa anche per indirizzo spedizione |
| esercizio_default | (vuoto) | esercizio preimpostato |

Valori tenant: verificabili via Knowledge MCP `get_tenant_overlays` o lettura
configurazione autorizzata; non hardcodare valori tenant nella Skill.

## Query di supporto (QRY-EFF-*)

- QRY-EFF-001 scadenze/importi documento
- QRY-EFF-002 documenti idonei alla generazione
- QRY-EFF-003 effetti di una fattura/cliente
- QRY-EFF-004 stato e banca effetti selezionati
- QRY-EFF-005 banca di presentazione e partite trasferite

Le query sono template read-only: eseguirle solo con tenant autorizzato
(canale mysql dedicato se disponibile nel toolset; altrimenti usare le letture
TabellaBase equivalenti).
