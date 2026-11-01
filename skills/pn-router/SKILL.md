---
name: pn-router
description: Punto di ingresso per qualsiasi richiesta sul gestionale ProgestNOW del tenant collegato. Usala quando l'utente parla di clienti, fornitori, articoli, fatture, ordini, DDT, offerte, note credito, scadenze, incassi, pagamenti, commesse, statistiche, agenda, allegati, attività, TabellaBase o stampe, anche se non nomina ProgestNOW.
---

# ProgestNOW: come orientarsi

Il connettore `progestnow` espone molti tool. Non indovinare: questa skill dice quale
skill caricare, quale famiglia di tool usare e in che ordine. Le informazioni specifiche
del tenant (nomi tabella, campi, decodifiche, trappole) arrivano dal server, non da qui.

## 1. Bootstrap (obbligatorio, una volta per conversazione)

1. **Prima di qualsiasi altro tool ProgestNOW, chiama `pn_capabilities`.** Restituisce le
   famiglie di tool abilitate per questo utente e le eventuali skill specifiche del tenant.
2. Le skill elencate nella sezione 3 sono già installate in questo plugin: per quelle aree
   usa la copia installata e **non** caricarle anche con `pn_skill_get`, anche se
   compaiono in `pn_capabilities` con lo stesso nome.
3. Se `pn_capabilities` elenca skill che non sono nella sezione 3 e pertinenti alla
   richiesta, caricale con `pn_skill_get` prima dei tool operativi; le risorse con
   `pn_skill_resource`. Le regole di una skill specifica del tenant prevalgono su quelle
   generiche della stessa area.
4. Se `pn_capabilities` non risponde, prosegui con le sezioni 2 e 3.
5. Per i tool `pn_tabellabase_*` con filtri o aggregazioni, prima della chiamata operativa
   chiama lo stesso tool con `_pn_info_request: true`: ricevi la documentazione per questo
   tenant senza eseguire nulla. Per gli altri tool chiama direttamente; se il server dice
   che il documento informativo non esiste, procedi senza ritentare.

## 2. Mappa intento → famiglia di tool

| L'utente vuole | Sequenza |
|---|---|
| Dati di clienti, fornitori, articoli, qualsiasi anagrafica o tabella | `pn_tabellabase_catalog` → `pn_tabellabase_descriptor(table_name)` → `pn_tabellabase_list` oppure `pn_tabellabase_single` |
| Totali, conteggi, medie, ranking, andamenti per mese/trimestre/anno | stessa sequenza, ma chiudi con `pn_tabellabase_aggregate`, mai sommando pagine di `list` |
| Documenti commerciali (fatture, ordini, DDT, offerte, note credito) | `pn_macro_document_types` / `pn_document_types` per i codici del tenant → `pn_documents_search` → `pn_document_read` |
| Stato pagamenti o incassi di un documento, documenti collegati | `pn_document_payments_status`, `pn_document_receipts_status`, `pn_document_linked_documents` |
| Scadenze, scaduto, esposizione clienti o fornitori | `pn_coge_scadenzario` filtrato per codice e date |
| Stampa PDF di un documento | `pn_document_pdf_generate` |
| Agenda e appuntamenti | `pn_agenda_find_my_agenda` → `pn_agenda_calendar_v3` |

## 3. Skill installate in questo plugin

Prima dei tool, carica la skill corrispondente all'intento e seguila: le sue regole
prevalgono sulla mappa della sezione 2. Se una skill dichiara `requires_skill`, carica
anche quella.

| Area / intento | Skill |
|---|---|
| Leggere qualsiasi TabellaBase: ricerca record, filtri, totali, conteggi, viste lista, partitario | `pn-tabellabase-query` (base per quasi tutte le altre) |
| Fatturato, vendite, ricavi per periodo/cliente/agente/articolo | `pn-fatturato-documenti` |
| Pagina Statistiche, `pn_statistiche_*`, top clienti/articoli, confronto anno precedente, margini | `pn-statistiche` |
| Incassi di fatture attive, residui, insoluti, crediti aperti, registrare un incasso | `pn-incassi` |
| Effetti RIBA/RID: distinte, file bancario, insoluti | `effetti-ciclo-vita` |
| Offerte, pipeline, preventivi, opportunità, tasso di conversione | `pn-offerte-crm` |
| Ordini clienti in lettura: portafoglio, backlog, inevasi, ritardi | `pn-ordini-clienti` |
| Ordini a fornitore in lettura: merce in arrivo, residuo da ricevere, puntualità | `pn-ordini-fornitori` |
| Evadere ordini: carico da ordine fornitore, DDT/fattura da ordine cliente | `pn-evasione-ordini` |
| Commesse, pratiche, cantieri: preventivo/consuntivo, costi, margini | `pn-commesse` |
| Riconoscere articoli da codici o descrizioni di terzi (bolle, listini, EAN, codici fornitore) | `pn-identificazione-articoli` |
| Costo ultimo, ultimo acquisto, fornitore di un articolo, confronto costi | `pn-dati-acquisto-articoli` |
| Allegati: ricerca, upload, copia, diagnosi | `attachments-support` |
| Attività/task e promemoria | `tasks-support` |
| Messaggi/discussioni su un record (`pn_threads`) | `threads-support` |
| Notifiche interne in-app (campanella) | `notifications-support` |
| Interventi di assistenza tecnica, schede/checklist/firme su commessa | `assistenza-interventi-support` |

Se la richiesta tocca più aree (es. "fatturato e incassato del cliente X"), carica tutte
le skill coinvolte. Se nessuna corrisponde, usa la mappa della sezione 2 e le regole qui
sotto.

## 4. Regole che valgono sempre

- Mai inventare `table_name` o nomi campo: solo quelli restituiti da catalogo e descriptor.
  "Clienti" e "fornitori" sono entità business, non nomi tabella.
- Se il descriptor o il catalogo restituiscono `ai_instructions`, leggile prima di costruire
  filtri: contengono nomi fisici, decodifiche e trappole di quella tabella per questo tenant.
- Nei filtri `search` usa gli `accepted_fields` del descriptor; se la tabella ha join,
  qualifica il campo come `nometabella.campo`.
- Date: `gg/mm/aaaa`, `aaaa-mm-gg` o relative (`@today`, `@today-30d`, `@start_of_month`).
- Dataset grandi: non usare `output=url` per scaricare dati, il tuo ambiente di esecuzione
  non raggiunge gli URL ProgestNOW. Restringi i filtri o usa `pn_tabellabase_aggregate`;
  non chiedere mai tutte le pagine. Una risposta con `auto_export` o `_pn_truncated`
  contiene solo un'anteprima: non ricostruire i dati mancanti.
- Link `urls.list`: includilo nella risposta solo se riporti esattamente i record di quei
  filtri, copiandolo verbatim; non costruire né modificare URL ProgestNOW.
- Codici e stati: usa il valore tecnico mostrato dal descriptor, non etichette business
  inventate.
- Nessuna scrittura (creare, modificare, cancellare, registrare, inviare) senza richiesta
  esplicita dell'utente nel turno corrente; prima di eseguirla riepiloga cosa verrà fatto e
  aspetta la conferma.
- Alcune skill citano tool del motore ProgestAI (`pn_code_exec`, `pn_excel_generate` e
  simili) che qui non esistono: segui la nota "Nel plugin" in testa alla skill.

## 5. Errori ricorrenti

- `PERMISSION_DENIED`: l'utente non ha il permesso su quella tabella o quel tool; dillo, non
  aggirare.
- `DATASET_TOO_LARGE*`: restringi i filtri o aggrega.
- Nome tabella sconosciuto: torna a `pn_tabellabase_catalog`, non provare varianti.
