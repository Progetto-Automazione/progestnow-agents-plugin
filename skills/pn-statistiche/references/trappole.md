# Trappole delle statistiche

1. **A mescola T e M.** L'acquistato somma ordini a fornitore (T) e carichi (M): lo stesso acquisto compare due volte (ordinato e poi caricato). Separa sempre con `filters.tipocausale` o il gruppo `tipocausale` (warning `A_MIXED_T_M`).
2. **R vuoto per configurazione.** Se nessuna causale ha `tipo_statistica = R` (progest: OFF ha 115 documenti nel 2026 ma `tipo_statistica` vuoto) l'offerto e vuoto (`TIPO_STATISTICA_EMPTY`): dillo, non inventare. Per le offerte CRM c'e `pn-offerte-crm`.
3. **Causali escluse.** Le causali con `tipo_statistica` vuoto non entrano nelle statistiche anche se hanno documenti (progest: ND nota di debito, 2 documenti 2026). Arriva `CAUSALI_NOT_IN_STATISTICS`; `pn_statistiche_catalog` le elenca in `causali_escluse`.
4. **Spese di piede escluse.** Le statistiche sommano le righe: trasporto, incasso e altre spese di piede non ci sono. Per questo differiscono dall'imponibile di testata (`pn-fatturato-documenti`).
5. **Costo = ultimo costo attuale.** Con il tipo di costo di default (`cost_type.code` vuoto) il costo e `cached_qrymag.cult × quantita`: l'ultimo costo di oggi, non quello alla data della vendita (`COST_IS_CURRENT_LAST_COST`). Il margine storico e indicativo.
6. **Costo zero non e costo mancante.** `righe_senza_costo` conta solo i costi NULL (articolo senza costo in cache); un costo 0 conta come coperto ma rende il margine 100%. Se il margine e quasi 100% segnalalo.
7. **`anno` non e `YEAR(data)`.** Il filtro `anno` e l'anno di numerazione del documento; il gruppo `anno` e il periodo `date_from`/`date_to` usano la data documento. Un documento numerato 2025 con data 2026 cade in modo diverso.
8. **Mese senza anno.** Il gruppo `mese` vale `01`..`12` senza anno: su un periodo di piu anni somma gennaio 2025 e gennaio 2026 (`MESE_WITHOUT_ANNO`).
9. **`codricavo` duplicato.** `codricavo` e `codricavorighefatture` sono lo stesso gruppo: non usarli entrambi.
10. **Viste dei costi senza alcune colonne.** Con il costo medio ponderato o il costo per vendita (`feature_statistiche_tipocosto` 1/2) la vista puo non avere `idfornitore`, `collezione_codice`, `diversadestinazione`: arriva `UNSUPPORTED_GROUP`/`UNSUPPORTED_FILTER` con `reason=column_not_in_view` (in pagina quei gruppi danno errore).
11. **Regola dei doppioni DDT/fattura.** Se una causale DDT ha tipo statistica F il motore esclude automaticamente le fatture generate da DDT (o i DDT gia fatturati, secondo `statistiche_datafatt`), per ogni tipo statistica: vedi `duplicate_rule` nel catalogo. Non correggerlo a mano.
12. **Cambio 0 o NULL.** Il valore in euro e `importototale × cambio`: con cambio 0 o NULL la riga vale 0 (`CAMBIO_MISSING`). La pagina corregge solo cambio 0 al momento della generazione; il tool non scrive mai.
13. **Articoli `*` e codici fuori anagrafica.** Righe descrittive o articoli non in anagrafica possono avere categoria/reparto `null` o vuoti: sono gruppi "senza ..." distinti (null e stringa vuota restano due gruppi).
14. **Note di credito gia negative.** Nelle statistiche le note di credito (C) e i movimenti M con segno `-` hanno gia quantita e valore negativi: non sottrarli una seconda volta.
15. **Totali arrotondati.** `totals` e calcolato sull'intero perimetro e puo differire di qualche centesimo dalla somma dei gruppi (arrotondati a 2 decimali come in pagina): riporta `totals`.
