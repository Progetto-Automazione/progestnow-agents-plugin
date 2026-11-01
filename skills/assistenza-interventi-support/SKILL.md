---
name: assistenza-interventi-support
description: >-
  Gestione e diagnosi degli interventi di assistenza tecnica in ProgestNOW. Attiva quando la domanda
  riguarda interventi (tabella interventi): ricerca per tecnico/impianto/stato/data, creazione e
  modifica interventi, ricorrenze, cambio stato, fatturazione del lavoro svolto, troubleshooting
  lista/ricorrenze/collegamento documento, e il flusso scheda-checklist-firma degli interventi su
  commessa (testacommesse_interventi).
metadata:
  knowledge_refs:
    - CAP-20260811-007
    - CAP-20260812-032
    - SCN-INTV-001..007
    - RULE-INTV-001..010
    - DATA-INTV-001..008
    - DIAG-INTV-001..003
    - QRY-INTV-001..003
    - SCN-TCI-001..004
    - RULE-TCI-001..007
    - DIAG-TCI-001..003
    - EXT-INTV-002
    - EXT-TCI-001
---

# Supporto interventi di assistenza

## Obiettivo procedurale

Rispondere in modo affidabile a domande e lavori sugli interventi di
assistenza: spiegare il flusso, leggere/creare/modificare interventi con i
tool TabellaBase, diagnosticare anomalie con i runbook canonici, guidare
l'utente sulle operazioni non disponibili via tool senza mai simularle.

## Prerequisiti

- Tool disponibili nel job: Knowledge MCP (`search_knowledge` o equivalenti)
  e TabellaBase (`pn_tabellabase_catalog`, `pn_tabellabase_descriptor`,
  `pn_tabellabase_list`, `pn_tabellabase_single`, `pn_tabellabase_aggregate`;
  `new/update` per le scritture). Se i tool TabellaBase non sono nel toolset
  corrente, delega a PNOWTABELLABASE (se la delega è disponibile).
- Knowledge base canonica: `CAP-20260811-007` e `CAP-20260812-032` sono
  risolvibili via Knowledge MCP; se il Knowledge MCP non risponde, basa la
  risposta SOLO su dati verificati e dichiaralo.

## Sequenza operativa

1. **Classifica la richiesta**:
   - spiegazione (how_to/feasibility/configuration/tenant_difference) → step 2;
   - lettura/stato reale (lista, dettaglio, statistiche) → step 3;
   - scrittura (crea/modifica intervento) → step 4;
   - troubleshooting → step 5;
   - operazioni non disponibili (cambio stato massivo, anteprima ricorrenze,
     fatturazione da intervento, checklist/firma su commessa) → step 6.
2. **Spiegazione**: recupera la capability via Knowledge MCP
   (`search_knowledge` / `get_capability_context` per CAP-20260811-007 o
   CAP-20260812-032); spiega citando SCN/RULE canonici. Schema dati e
   decodifiche in `references/data-model.md`.
3. **Lettura/stato reale**:
   a. `pn_tabellabase_descriptor(table_name="interventi")` prima di costruire
      filtri o output_fields;
   b. `pn_tabellabase_list` con search mirato (tecnico=`interventi.idmanodopera`,
      impianto=`interventi.idimpianto`, stato=`interventi.statointervento`,
      date su `interventi.dataintervento`); usa campi qualificati;
   c. `pn_tabellabase_single` per il dettaglio di un id;
   d. `pn_tabellabase_aggregate` per conteggi/totali per tecnico/stato/impianto
      o periodo, senza riversare righe;
   e. "intervento successivo dello stesso impianto": filtro
      `idimpianto=<id>` + `dataintervento >= <data>`, page_size piccola,
      scegli la data minima tra i risultati (approssimazione dichiarata della
      route gotonextintervento);
   f. volumi grandi: dataset by-reference, mai righe nel contesto.
4. **Scrittura singolo intervento**:
   a. verifica preventiva dei referenziali: tecnico esistente in `manodopera`
      (`cidmanodopera`), impianto in `structures` (`id`), stato in
      `interventi_stato` (`codice`), tipo in `interventi_tipo` (`codice`);
   b. campi minimi consigliati: `dataintervento`, `idmanodopera`,
      `idimpianto`; lo stato vuoto diventa TODO automaticamente (hook
      postInsert, RULE-INTV-001);
   c. `pn_tabellabase_new`/`pn_tabellabase_update` (in execute passa dal
      flusso di conferma: non aggirarlo);
   d. dopo la creazione, se l'utente si aspetta autofill/geocodifica/
      ricorrenze: spiega che sono effetti server-side dell'hook postInsert e
      verifica con una rilettura;
   e. in modifica dichiara i limiti: DONE non genera ricorrenza successiva,
      il cambio indirizzo non ricalcola lat/lng (flussi standard).
5. **Troubleshooting**: applica le decision table in
   `references/diagnostic-tables.md` (DIAG-INTV-001..003 e DIAG-TCI-001..003),
   verificando ogni ipotesi con letture TabellaBase. Le QRY-INTV-* canoniche
   sono query SQL per accesso diretto al db: qui si replicano con
   list/single/aggregate sugli stessi campi. Non concludere una causa senza
   evidenza; ciò che non è verificabile va dichiarato `non verificabile`.
6. **Operazioni non disponibili — NON simulare**:
   - cambio stato massivo: guida alla selezione multipla in lista interventi
     (UI); proponi solo singole modifiche puntuali autorizzate;
   - anteprima ricorrenze: dichiara che la preview non è disponibile via
     agente; la configurazione `recurrency` si salva in creazione e le
     occorrenze sono generate dal backend;
   - fatturazione da intervento: finché i tool documento non accettano
     `intervento_id`, guida l'utente ad aprire il documento dalla scheda
     intervento (è l'unico modo per ottenere il collegamento
     `testapiedefatture.intervento_id` e il cliente dell'impianto);
   - checklist/firma su commessa: se le tabelle non esistono nel tenant
     (verifica con catalog/descriptor), dichiaralo; la firma è comunque
     operazione umana.

## Decision point

- Stato dell'intervento: usa i codici del referenziale `interventi_stato`
  (es. TODO, DONE) letti dal tenant, mai label inventate.
- `interventi.cidfattura` valorizzato: NON concludere "fatturato" tranne che
  nel tenant `bene`; il collegamento standard è
  `testapiedefatture.intervento_id`.
- Interventi con `father_id`: sono occorrenze ricorrenti; il padre ha
  `recurrency`/`repeat_days`. `repeat_type=autocreate` = generazione
  differita (nessuna occorrenza immediata: comportamento atteso).
- Domanda su comportamenti "strani" di un tenant specifico → verifica prima
  `EXT-INTV-002` (tenant J, rossirefrigerazione, golden, rosi/fix4) via
  Knowledge MCP; non generalizzare a standard.

## Fallback

- Tool TabellaBase assenti dal toolset → delega a PNOWTABELLABASE se
  l'arco di delega esiste; altrimenti spiega cosa manca e cosa l'utente può
  fare dalla UI.
- Filtro che produce errore SQL → correggi il campo (qualifica
  `interventi.<campo>`) invece di insistere; se il descriptor non mostra il
  campo, dichiaralo non filtrabile.
- Record non trovato → non inventare: verifica id, filtri e permessi
  (DIAG-INTV-001).

## Criteri di completamento

- Lettura: risultati con decodifiche corrette e filtri dichiarati.
- Scrittura: record verificato con rilettura dopo il salvataggio.
- Diagnosi: conclusione con evidenza (record/valori citati) o dichiarazione
  esplicita di non verificabilità.
- Mai: simulazioni massive, firme simulate, stati inventati, generalizzazioni
  di rami tenant a comportamento standard.
