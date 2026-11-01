---
name: pn-dati-acquisto-articoli
description: >-
  Procedura obbligatoria per DATI DI ACQUISTO DEGLI ARTICOLI - costo ultimo, prezzo/data dell'ultimo
  acquisto, fornitore dell'ultimo acquisto o carico, costo ultimo per uno specifico fornitore,
  confronto costi tra fornitori, fornitore preferenziale/di riassortimento, costi insieme alle
  giacenze. Attivala prima di cercare costi o ultimi acquisti di articoli: le fonti sono viste gia'
  pronte, non si ricostruiscono da documenti o movimenti.
---

> **Nel plugin (Claude, Codex).** Questa procedura nasce per il motore ProgestAI: dove differisce, vale questa nota.
> - `output=url` non va usato per scaricare dati: il tuo ambiente di esecuzione non raggiunge gli URL ProgestNOW. Restringi i filtri, aggrega lato server con `pn_tabellabase_aggregate`, oppure pagina con limiti piccoli; i calcoli locali li fai sui dati gia restituiti dai tool, nel tuo ambiente di esecuzione, al posto del "sandbox".
> - Questi tool qui non esistono: `pn_dataset_merge`, `pn_excel_generate`. Se un passaggio li richiede, usa un equivalente disponibile (il tuo ambiente di esecuzione per calcoli e file, la chat per testi da inviare) oppure dichiara all'utente il limite; non inventare chiamate.

# Dati di acquisto degli articoli

Costi e ultimi acquisti degli articoli esistono gia' calcolati in tre TabelleBase.
**Non ricostruirli** da testate/righe documento o dai movimenti di magazzino grezzi:
e' lento, e i movimenti di carico comprendono trasferimenti, inventari, rettifiche e
resi, che NON sono acquisti.

Per la sintassi di filtri, aggregate ed export segui la skill `pn-tabellabase-query`.
Verifica sempre i nomi reali dei campi con `pn_tabellabase_descriptor`.

## Che cos'e' un "acquisto"
Un movimento di magazzino con causale che aggiorna il costo ultimo/medio
(`causalimagazzino.aggiornacostoulimomedio <> 0`) e quantita' caricata diversa da zero.
Di norma e' il carico da fornitore (es. causale `CAR`). Le viste sotto applicano gia'
questa regola: non serve filtrare le causali a mano.

## Le tre fonti

### 1. `qryultc` - ultimo acquisto in assoluto (una riga per articolo)
| Campo | Significato |
| --- | --- |
| `qryultc.idmagazzino` | articolo |
| `qryultc.dataultimoacquisto` | data dell'ultimo acquisto |
| `qryultc.cult` | costo unitario dell'ultimo acquisto (netto sconti di riga) |
| `qryultc.idfornitore` | fornitore di quell'ultimo acquisto (-> `arcfor.codice`) |

Altri campi disponibili: `quantitacaricata`, `importounitario`, `importototalecaricato`,
`percentualesconto_1..3`, `numeroriferimento` (riferimento del documento di carico).

Usala per: "costo ultimo", "ultimo prezzo d'acquisto", "quando l'abbiamo comprato
l'ultima volta", "fornitore dell'ultimo acquisto/carico".

### 2. `qryultc_for` - ultimo acquisto per ogni fornitore (una riga per articolo + fornitore)
| Campo | Significato |
| --- | --- |
| `qryultc_for.idmagazzino` | articolo |
| `qryultc_for.idfornitore` | fornitore (-> `arcfor.codice`) |
| `qryultc_for.dataultacq` | data dell'ultimo acquisto da QUEL fornitore (testo `aaaa-mm-gg`) |
| `qryultc_for.cult` | costo unitario dell'ultimo acquisto da QUEL fornitore |

Usala per: "quanto lo pagavamo da X", "confronta i costi tra fornitori",
"ultimo acquisto di questo articolo dal fornitore Y". Filtra sempre per articolo
e/o fornitore: senza filtri la vista e' pesante.

### 3. `_qrymag` - situazione di magazzino con costo (una riga per articolo)
Espone giacenza, ordinato clienti e fornitori, prezzi e anche `cult` e
`dataultimoacquisto` (stessi significati di `qryultc`). **Non ha il fornitore.**

Usala quando la domanda riguarda insieme costi e giacenze ("valore del magazzino",
"articoli con giacenza e costo ultimo"). Se serve anche il fornitore dell'ultimo
acquisto, unisci con `qryultc` per `idmagazzino` (export di entrambe con `output=url`
e `pn_dataset_merge`).

## Fornitori in anagrafica articolo (non sono "acquisti")
- `articoli.idfornitore1` = fornitore preferenziale (principale);
- `articoli.idfornitore2` = secondo fornitore, spesso etichettato "fornitore di
  riassortimento/rifornimento" (verifica l'etichetta nel descriptor del tenant).

Sono impostazioni dell'anagrafica: possono essere diverse dal fornitore dell'ultimo
acquisto. Se l'utente chiede "fornitore" senza specificare, chiedi quale dei tre intende,
oppure riportali tutti e tre con l'etichetta giusta.

## Regole
1. Il nome del fornitore si prende sempre da `arcfor.nome` tramite `idfornitore`.
   Mai da campi di testo dei movimenti.
2. Articolo senza riga in `qryultc` = mai acquistato (con causale d'acquisto): dichiaralo,
   non cercare "l'ultimo carico" in altri movimenti.
3. Valuta: `cult` e' nella valuta del documento di carico; se nel perimetro ci sono
   fornitori esteri, segnalalo.
4. Se `qryultc_for` non e' disponibile sul tenant (errore o TabellaBase assente):
   dillo all'utente e usa `qryultc` per il solo ultimo acquisto in assoluto.
   Non ricostruire il dato dai movimenti.

## Ricetta tipica: elenco articoli con fornitori e ultimo acquisto (Excel)
Esempio: "articoli di magazzino con fornitore preferenziale, di riassortimento e
fornitore dell'ultimo carico".
1. Export degli articoli del perimetro (`output=url`): `idmagazzino`, `descrizione`,
   `idfornitore1`, `idfornitore2`, con il filtro chiesto dall'utente (verifica il nome
   del campo nel descriptor: es. `trade_inmagazzino` dove l'utente scrive "in_magazzino").
2. Export di `qryultc` (`output=url`): `idmagazzino`, `dataultimoacquisto`, `cult`,
   `idfornitore`.
3. Export di `arcfor` (`codice`, `nome`).
4. `pn_dataset_merge`: articoli + qryultc su `idmagazzino` (left join, gli articoli
   mai acquistati restano con campi vuoti), poi tre volte arcfor per i nomi di
   `idfornitore1`, `idfornitore2` e `idfornitore` dell'ultimo acquisto.
5. `pn_excel_generate` sul dataset finale. Colonne con intestazioni chiare:
   Fornitore preferenziale, Fornitore riassortimento, Fornitore ultimo acquisto,
   Data ultimo acquisto, Costo ultimo.
6. Nel riepilogo: numero articoli, quanti mai acquistati, quanti senza fornitore
   preferenziale / di riassortimento.

Se i tool dataset non bastano per i join, usa il sandbox solo per unire i dataset gia'
esportati, mai per ricalcolare l'ultimo acquisto.
