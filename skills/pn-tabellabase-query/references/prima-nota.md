# Prima nota e contabilita: pattern di lettura

Le tabelle contabili di ProgestNOW hanno convenzioni proprie. Leggi questa scheda **prima** di costruire i filtri su costi, ricavi, clienti, fornitori, scadenze o partitario. Per la sintassi generale dei filtri vedi `references/filtri.md`.

## Partita doppia

- Ogni movimento ha **dare** e **avere**. Un saldo e `somma(dare) - somma(avere)` (o l'inverso secondo la sezione): non sommare mai una sola colonna e chiamarlo "saldo".
- Le colonne degli importi (es. `impdare`, `impavere`) sono **decimali come stringhe**: usa `sum` in `pn_tabellabase_aggregate` (con `round`) o `pn_dataset_calculate`, e riporta il valore senza arrotondarlo a mente.
- Un **conto/sottoconto** identifica la contropartita: filtra per sottoconto quando l'utente chiede "i costi/ricavi di X", non per il solo documento.

## Contesto: cliente o fornitore

- Prima di filtrare, stabilisci se la richiesta riguarda un **cliente** (ricavi/crediti) o un **fornitore** (costi/debiti): cambia la tabella e il significato del segno.
- Se il nome della tabella non e certo, usa `pn_tabellabase_catalog` (indice) e poi `ai_instructions` del descriptor: la scheda dice su quale tabella/colonna si esprime il conto.
- Riferimenti a un soggetto specifico: filtra sul **codice** (campo fisico), non sull'alias di descrizione.

## Causali

- La **causale** (es. campo `caumovc`) classifica il movimento. E un codice: filtra sul codice fisico.
- Per escludere movimenti di servizio usa **un `<>` per ogni** causale da escludere (`collection` + `<>` non esclude: vedi `references/filtri.md`).

## Date e periodi

- Formato **gg/mm/aaaa**, sempre con due filtri `>=` / `<=`.
- Per totali mensili/trimestrali/annuali non iterare le date a mano: usa `date_buckets` in `pn_tabellabase_aggregate` (`month`, `quarter`, `year`).
- Per lo scadenzario (scadenze aperte, aging) filtra la data di scadenza entro la finestra richiesta e aggrega per soggetto o per bucket.

## Aggregazioni tipiche

- Ricavi/costi per cliente/fornitore o per periodo: `dimensions` = codice soggetto (e/o causale), `date_buckets` = periodo, `measures` = `sum` degli importi + `count` righe.
- Saldo per sottoconto: `dimensions` = sottoconto, `measures` = `sum` dare e `sum` avere (due misure), poi saldo = differenza.
- Numero movimenti: `count` o `count_distinct` su un identificativo movimento.
- Max 5 misure, 5 dimensioni, 3 bucket per chiamata: split in piu chiamate se serve di piu.

## Controlli di coerenza

- **Quadra con la tabella**: confronta il totale aggregato con il numero di righe atteso; se i due non tornano, il filtro e costruito su un campo diverso da quello che credi.
- **Segno e periodo**: prima di dare un numero all'utente, verifica di aver incluso tutte le causali rilevanti e il periodo corretto.
- **Estrazioni grandi**: per elaborazioni riga-per-riga (riconciliazioni) usa `output=url` → sandbox, non la lettura paginata.
