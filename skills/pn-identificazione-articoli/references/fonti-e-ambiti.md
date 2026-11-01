# Fonti, ambiti e forza del match

Copia di riferimento della sezione Tool del brief (spec 197). Serve a capire
**da dove** viene un abbinamento e **quanto** e' affidabile.

## Fonti (colonna `fonte`)

| Fonte | Origine | Ambito |
| --- | --- | --- |
| `idmagazzino` | `articoli.idmagazzino` (nostro codice) | globale |
| `cpf1` / `cpf2` | `articoli.codiceprodottofornitore1/2` | `F` + `articoli.idfornitore1/2`; se il fornitore e' vuoto, globale |
| `barcode` | `codiciabarre.ccodbar` | globale, con `nqtaconf` (confezione; 0 in DB = non indicata = `null`) |
| `codalt_for` | `codicialternativi.codicealt_articolo` con `codicefor` numerico diverso da `0` | `F` + `codicefor` |
| `codalt_cli` | `codicialternativi.codicealt_articolo` con `codicecli` valorizzato (solo dove la colonna esiste) | `C` + `codicecli` |
| `codalt` | `codicialternativi.codicealt_articolo` senza controparte (`codicefor` vuoto o `0`) | globale |
| (escluso) | `codicialternativi` con `codicefor` valorizzato **non numerico** | non indicizzato |
| `listino` | `righe_listini.ccodicealternativo` | `idlistino`; la controparte si risolve a query time con `arcfor.codlist` / `arccli.codlist` |
| fonte extra (es. `impa`) | tabella propria del tenant configurata in `pn_ai_articoli_lookup_extra_sources` (tenant B: `zz_<tenant>_codici_impa`) | globale |

**Fonti extra (v2.1).** Il nome della fonte (es. `impa`) compare cosi' com'e'
nell'output. Sono codici standard, non di una controparte: ambito `globale`,
forza alta come `barcode`, nessun `controparte_fonte`. Le righe senza articolo
non entrano nella lookup.

**Prefissi (v2.1).** I prefissi di `pn_ai_articoli_lookup_strip_prefixes`
(default `IMPA,RS CODE,CODE,COD.,COD,ART.,ART,REF.,REF,P/N,PN.`) si tolgono solo
in testa, una volta, e solo con un separatore dopo i prefissi che finiscono con
una lettera o cifra (`CODE 277-7939` si', `COD000000011112` no). Nella lookup ci
sono entrambe le versioni (con e senza prefisso, stessa fonte): `577-419` trova
il `cpf1` `RS CODE 577-419`. Anche l'input si cerca in entrambe le versioni: una
fonte trovata tramite il codice senza prefisso riporta
`"variante": "senza_prefisso"`; `codice_input` resta il valore originale.
Un nostro codice (`idmagazzino`) trovato **solo** togliendo il prefisso non vince
se il codice originale, con il prefisso, e' gia' un codice esatto di un altro
articolo: il nostro articolo scende a media e nessuna fonte e' declassata. Es.
`ART.411-1` e' il codice del fornitore F 21431 per l'articolo 10438, mentre
`4111` e' il nostro codice di un altro articolo: senza controparte `ambiguo`
(entrambi media), con il fornitore F 21431 `univoco` 10438. Se l'originale non ha
match esatti su altri articoli (es. `IMPA 110121`) il nostro codice vince.

La controparte dei listini **non** e' materializzata: cambiare il listino di un
fornitore o cliente non richiede ricalcoli.

## Ambiti (colonna `ambito`)

- `controparte`: stessa controparte dell'input, oppure fonte `listino` il cui
  `idlistino` coincide con `arcfor.codlist` / `arccli.codlist` della controparte.
- `globale`: fonti senza controparte (`idmagazzino`, `barcode`, `codalt`, `cpf`
  senza fornitore).
- `altra_controparte`: codice di un altro fornitore o cliente.
- `controparte_ignota`: nessuna controparte in input, ma la riga ha una
  controparte materializzata.

## Forza del match (v2)

| Fonte e ambito | Forza |
| --- | --- |
| `idmagazzino` (nostro codice), esatto o solo senza zeri iniziali, qualunque etichetta | alta |
| `codalt_for` / `cpf1` / `cpf2` / `codalt_cli` / `listino` con ambito `controparte` | alta |
| `barcode` | alta |
| `codalt` globale, `cpf` senza fornitore, fonti di controparte con ambito `controparte_ignota` | media |
| qualsiasi fonte con ambito `altra_controparte` | bassa |
| fonte extra (es. `impa`) | alta |
| stesso codice di un nostro codice, ma su un altro articolo (`declassata: true`) | bassa |
| nostro codice trovato solo senza prefisso, con l'originale esatto su un altro articolo | media |
| match solo su `codice_norm_nz` (zeri iniziali), tranne `idmagazzino` | un livello in meno |

**Il nostro codice vince sempre.** Se un codice coincide con l'`idmagazzino` di
un articolo, quell'articolo e' alta; gli altri articoli trovati dallo **stesso**
codice su altre fonti restano candidati secondari con forza bassa e
`declassata: true` sulla fonte, e l'esito resta `univoco`. Un `idmagazzino`
esatto prevale su un `idmagazzino` trovato solo senza zeri iniziali. I candidati
declassati non contano per `codici_discordanti`: codici **diversi** della stessa
riga che portano con forza alta ad articoli diversi restano discordanti.
L'`etichetta` e' informativa: non cambia la forza.

**Eccezione (v2.1): `conflitto_nostro_codice`.** Il nostro codice **non** vince
se lo stesso codice porta, con forza alta, a un altro articolo tramite una fonte
della controparte del documento (`codalt_cli`, `codalt_for`, `cpf1`, `cpf2`,
`listino` con ambito `controparte`) oppure tramite una fonte extra (es. `impa`).
Allora l'esito e' `ambiguo` con `motivo: conflitto_nostro_codice`: entrambi i
candidati restano alta con le rispettive fonti e nessuna fonte dell'articolo in
conflitto e' `declassata` (in questa riga `declassata` non vuol dire "vince il
nostro codice": marca solo gli altri articoli scartati). Senza
controparte e senza fonte extra in disaccordo la regola resta com'e'. Una fonte
extra che punta allo stesso articolo del nostro codice lo rafforza.

## Normalizzazione

- `codice_norm` = `REGEXP_REPLACE(UPPER(TRIM(x)), '[^A-Z0-9]', '')`.
- `codice_norm_nz` = `codice_norm` senza zeri iniziali (EAN-13 contro UPC-12,
  `0012` contro `12`).
- Un codice e' scartato (`scartato_corto`, mai indicizzato, mai un match) se
  `codice_norm` e' vuoto, se e' piu' corto di `pn_ai_articoli_lookup_min_len`
  (default 3) oppure se `codice_norm_nz` e' vuoto (codice fatto solo di zeri,
  es. `000000`).

## Esito della riga (v2)

Prima dell'esito si tolgono i candidati non piu' presenti in `articoli`
(contati in `sintesi.candidati_esclusi_stale`), l'articolo di fallback (mai
candidato) e, con `includi_obsoleti: false`, gli obsoleti.

- `non_trovato`: nessun candidato (`motivo: scartato_corto` se la riga aveva solo
  codici scartati).
- `ambiguo` con `motivo: codici_discordanti`: almeno due codici della riga hanno
  candidati di forza alta diversi fra loro **e** nessun articolo e' trovato da
  tutti i codici che hanno trovato qualcosa. Un solo codice utile non e' mai
  discordante; un candidato debole in piu' non crea discordanza.
- `ambiguo` con `motivo: conflitto_nostro_codice` (v2.1): il nostro codice e
  una fonte forte della controparte o una fonte extra indicano articoli diversi
  (vedi sopra); `codici_discordanti` ha la precedenza.
- `univoco`: un solo candidato di forza **alta** (anche con altri candidati
  media o bassa).
- `probabile`: un solo candidato, forza media o bassa.
- `ambiguo` (`motivo: null`): piu' candidati senza esattamente un alto.

`sintesi`: `righe` = `univoche` + `probabili` + `ambigue` + `non_trovate`; le
probabili contano tra le non univoche (prime 50 righe inline e soglia del
dataset). `sintesi.warnings` e' sempre un array.

I candidati si ordinano per forza, poi numero di fonti concordanti, poi presenza
in `candidati_preferiti`, poi non-obsoleti prima.

## `controparte_fonte`

Ogni elemento di `fonti` con fonte `cpf1`, `cpf2`, `codalt_for`, `codalt_cli`
riporta `controparte_fonte: {tipo, id, nome}` (a chi appartiene il codice),
qualunque sia l'ambito; `null` se il codice non ha controparte (es. `cpf` senza
fornitore). Per `listino` la controparte e' chi usa quel listino
(`arcfor.codlist` / `arccli.codlist`): `null` se nessuno, un oggetto se uno,
un array di al massimo 5 se piu' d'uno (la controparte dell'input per prima, poi
fornitori, poi clienti), sempre con `n_controparti` (totale). `idmagazzino`,
`barcode`, `codalt`: nessun `controparte_fonte`.

Lo stesso codice di piu' controparti (o su piu' listini) sullo stesso articolo
compare come una fonte per ciascuna controparte/listino: guarda tutte le fonti
del candidato, non solo la prima.

Uso: esito `probabile` con `controparte_fonte` (di una qualsiasi fonte) uguale
alla controparte del documento non passata -> richiama il tool con quella
controparte.

## `fallback`

`fallback: {idmagazzino, descrizione, um}` se `pn_ai_articoli_codice_fallback`
e' configurato con un articolo esistente e non obsoleto; `null` se vuoto; `null`
+ `sintesi.warnings[] = {code: "FALLBACK_ARTICLE_INVALID", message}` se
l'articolo non esiste o e' obsoleto. Presente in ogni risposta con `sintesi`
(anche con dataset o export fallito), assente negli errori `AI_ARTICOLI_*`.
Vedi `fallback.md`.
