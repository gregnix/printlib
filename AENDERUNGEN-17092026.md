# printlib 0.3 -- Aufraeumen 17.09.2026

Ausgangslage: zwei Pakete vom 17.09., eines davon mit **14 Dateien aus
pdf4tcl** vermischt (darunter ein `pkgIndex.tcl`, das `pdf4tcl 0.9.4.52`
anmeldete und auf eine nicht vorhandene Datei zeigte). Gearbeitet wurde
auf der sauberen Fassung.

Gemessen: von 101 gemeinsamen Dateien waren **100 bytegleich** -- nur
`README.md` war die von pdf4tcl. Also derselbe Stand, einmal sauber und
einmal ueberschrieben; kein Inhaltsfehler an printlib.

## Geaendert

**`test/test-pdfium-backend.tcl`** nennt jetzt die geladene Datei:

```
printlib 0.3 aus: .../lib/tm/printlib-0.3.tm
```

Der Test sucht sie ueber eine Kandidatenliste und nimmt die erste, die
es gibt. Liegt eine fremde oder alte daneben, faellt das ohne diese
Zeile nicht auf -- genau der Fall von heute.

**`lib/tm/printlib/printlib-booklet.tcl` -> `doc/printlib-booklet.tcl`.**

`bookletOrder` und `makeBooklet` sind in **keiner** geladenen Datei; das
Modul sourct sie nie. Der Kopf sagte *"To be merged into
printlib-0.2.tm"* -- also seit mindestens einer Fassung offen. Unter
`lib/` sah sie aus wie ausgelieferter Code.

Sie liegt jetzt neben `printlib-pdfium-backend.tcl`, das dasselbe ist:
ein Patch, der auf das Einbauen wartet. Der Kopf nennt den Stand und
was zum Einbauen zu tun waere.

Das leere `lib/tm/printlib/` ist weg.

**`doc/printlib-pdfium-backend.tcl`**: Kopf um den Stand ergaenzt.
Nachgemessen -- alle fuenf genannten Stellen sind in `printlib-0.3.tm`:

```
pdfiumPrefer 4x, -pdfiumprefer, _available, detect, pdfium-Zweig
```

Der Patch ist **eingebaut**; die Notiz sagte es nicht.

**`test/test-pdfium-backend-guard.tcl`**: Suchpfad um `doc/` erweitert,
damit der Vergleich der Testkopie gegen den Entwurf weiterlaeuft.

## Gemessen, nicht geaendert

* **Kodierung:** drei Zeilen Nicht-ASCII, alle in Kommentaren. Anders
  als in der fritzbox-Bibliothek (57 Ausgabetexte) hier folgenlos.
* **`package require Tcl 8.6-`** steht schon offen -- die Tcl-9-Falle
  aus pdf4tcl gibt es hier nicht.
* **Fassungsnummer** nur an zwei Stellen (Dateiname, `package
  provide`) plus README. Eine Wache wie `bump.tcl` lohnt noch nicht.

## Zweiter Durchgang -- Roadmap und Demos

**`doc/roadmap.md` behauptete `-booklet` als vorhanden.** Gemessen:
null Treffer auf `booklet` in `printlib-0.3.tm`, keine `-booklet`-Option
in `print`. Zwei Stellen berichtigt, und ein Abschnitt **R3a** ergaenzt,
der den Entwurf nennt und sagt, was zum Einbauen fehlt.

Wer die Roadmap liest und dann `-booklet` sucht, haette nichts gefunden
-- und die Datei, die es koennte, lag unter `lib/` und sah nach
ausgeliefertem Code aus. Beides jetzt zusammengefuehrt.

**Die Demos setzten den Modulpfad nicht.** Vier von fuenf brachen mit
`can't find package printlib` ab -- also genau nach dem Auspacken des
Archivs, obwohl die Bibliothek daneben liegt. Die Testdateien machen es
seit jeher selbst.

Vorspann in vier Demos ergaenzt; `demo-001.tcl` ausserdem von CRLF auf
LF.

**`demo-001.tcl` druckt wirklich** und brach ohne Drucksystem mit einem
Fehler ab -- nicht mit einer Erklaerung. Jetzt:

```
kein Druckbackend -- demo-001.pdf geschrieben, nicht gedruckt
```

Die PDF ist zu diesem Zeitpunkt vollstaendig (2965 Bytes gemessen). Das
ist dieselbe Vorsicht, die die Druck-Serie in ihrem Kopf zweimal
betont: kein echter Druckauftrag ohne Ansage.

## Dritter Durchgang -- nach der Fremdlesung

Die erste printlib-Lesung (17.09., 05:40) fand drei Dinge, die hier
uebersehen wurden. Alle nachgemessen und bestaetigt.

**`status` meldete Fassung 0.2**, waehrend `package provide` 0.3 sagt.
Wer `dict get [status] version` auswertet -- eine Diagnoseausgabe, ein
Howto -- bekam die falsche Nummer.

Behoben so, dass es nicht wieder auseinanderlaeuft:

```tcl
version [package provide printlib]
```

Die Nummer wird nicht mehr ein zweites Mal gefuehrt.

**`printlib-gui.tcl` und `demo/demo-printlib.tcl` zeigten auf ihr
eigenes Verzeichnis**, nicht auf `lib/tm`. Dort liegt keine
`printlib-0.3.tm`. Es funktionierte nur, weil das Modul ohnehin
installiert war -- aus einer ausgepackten Kopie brach es ab.

*Mein Fehler im zweiten Durchgang:* bei `demo-printlib.tcl` kam meine
Zeile zur falschen **dazu**, statt sie zu ersetzen; `printlib-gui.tcl`
hatte ich gar nicht angesehen. Beides berichtigt, gegengeprueft aus
einer isolierten Kopie unter `/tmp/iso`.

**Acht der 36 Testfaelle pruefen eine eingefuegte Kopie.**
`test-pdfium-backend.tcl` definiert `::printlib::bookletOrder` selbst --
nach `package require` ist sie leer. Die Faelle sind gruen gegen den
**Entwurf**, nicht gegen das Paket.

Nicht entfernt, sondern **benannt**: ein Kommentar ueber der Definition
sagt, dass es eine Kopie ist, warum sie trotzdem sinnvoll ist (der
Guard vergleicht sie zeichenweise gegen `doc/printlib-booklet.tcl`) und
was beim Einbauen zu loeschen waere.

**Lizenz an drei Stellen verschieden:** Kopf BSD 2-Clause, README MIT,
`LICENSE` fehlt. Das ist keine technische Frage -- die README benennt
den Widerspruch jetzt ausdruecklich, statt eine der beiden Angaben zu
wiederholen.

## Vierter Durchgang -- 7.1 aus der zweiten Lesung

**Kommentare an `detect` und `print`** nannten zwei Backends
(`pdftocairo | sumatra`), der Code kennt vier. Gemessen:

```
known: pdftocairo pdfium sumatra lp
```

Beide Stellen nennen jetzt alle vier und sagen, dass es bis 0.2 zwei
waren.

**`known` exportiert.** Es liefert die Liste, auf die sich `-backend`
bezieht, war aber nach `namespace import ::printlib::*` unsichtbar.
Gegengeprueft.

**Demo-Zeilen `;# 0.2 oder neuer`** in zwei Dateien entfernt.

**Nicht angefasst:** Lizenz (Entscheidung des Urhebers), site-tcl und
tinventar-Vendor (fremde Baeume).

## Fuenfter Durchgang -- Invarianten und ehrlicher status

**`test/test-module-invariants.tcl`** ist neu: zehn Faelle, die ohne
Drucker, ohne pdfiumtcl und ohne Anzeige laufen. Sie halten fest, was
in zwei Lesungen jeweils von Hand nachgemessen wurde.

```
inv-version    status version == package provide
inv-backends   known == {lp pdfium pdftocairo sumatra}
               detect unter Unix in {lp none}
inv-booklet    bookletOrder und makeBooklet NICHT im Modul
inv-status     can_print folgt detect; backends == known;
               alte *_ok-Schluessel noch da
inv-pages      odd/even -> page-set, Bereiche -> -P
```

**Gegengeprueft, beide Richtungen:**

```
Fassung auf 0.2 zurueckgedreht   -> 2 Faelle rot
bookletOrder eingebaut           -> 2 Faelle rot
```

Der Booklet-Fall ist der wichtigste: **wird der Entwurf eingebaut, wird
er rot** -- und genau dann gehoert die Test-Kopie aus
`test-pdfium-backend.tcl` geloescht. Der Test erinnert daran, statt
dass jemand es merken muss.

### `status` trennt jetzt zwei Fragen

```
pdftocairo_present 1     das Programm ist da
can_print          0     ueber detect kaeme nichts heraus
backend_detected   none
backends           pdftocairo pdfium sumatra lp
```

Unter Linux meldete `pdftocairo_ok 1`, weil `pdftocairo -v` antwortet
-- gedruckt haette es nie, weil die Registry dort nur `lp` freigibt.
Die Zeile las sich wie *"pdftocairo kann drucken"*.

**Die alten `*_ok`-Schluessel bleiben** als Synonym, damit bestehende
Aufrufer nicht brechen; ein Testfall haelt sie fest.

### `-pages odd`/`even`: kein Befund

Die zweite Lesung nennt den leeren `switch`-Rumpf in `_print_lp` als
stillen Volljob. **Gemessen -- er ist Absicht.** `odd`/`even` sollen
nicht an `-P`, sondern weiter unten als `-o page-set`:

```
-pages odd   ->  lp -d Test -o page-set=odd ...
-pages even  ->  lp -d Test -o page-set=even ...
-pages 1-3   ->  lp -d Test -P 1-3 ...
```

`inv-pages-1.0` haelt das fest -- damit niemand den leeren Rumpf
"repariert" und `page-set` dann doppelt gesetzt wird.

Alle drei Testdateien gruen unter Tcl **8.6** und **9.0.4**.

## Sechster Durchgang -- ein Fehler von mir

Die dritte Lesung (17.09., 07:10) nennt `detect` in `status` als
Verhaltensaenderung. **Sie hat recht, und es war meine Aenderung aus dem
fuenften Durchgang.**

`detect` setzt `activeBackend`. Damit hatte `status` -- eine reine
Auskunft -- eine Nebenwirkung bekommen:

```
configure -backend sumatra   activeBackend ''
status                       activeBackend 'none'
```

Ein Aufruf, der nur fragen sollte, verschob still, was die naechste
`print`-Entscheidung nimmt.

**Behoben:** `status` baut die Plattformkette selbst nach --
`_backendsFor`, `pdfiumPrefer`, erstes verfuegbares -- ohne
`activeBackend` anzufassen. Dieselbe Antwort, kein Seiteneffekt.

### Der Testfall dazu griff zuerst nicht

Erster Versuch: Wert vor und nach `status` vergleichen. **Blieb gruen,
obwohl der Fehler da war.**

Grund: ein frueherer Fall in derselben Datei ruft `detect`, also steht
`activeBackend` schon auf `none` -- und ein `status`, der `detect`
ruft, setzt es wieder auf `none`. Der Vergleich ging auf.

Behoben mit einem Merkwert:

```tcl
set ::printlib::activeBackend MERKWERT
printlib::status
# muss MERKWERT bleiben
```

**Gegengeprueft:** Seiteneffekt zurueckgebaut -> 2 Faelle rot.

Das ist die Sorte Test, die ohne Gegenprobe still gruen geblieben
waere -- und ich haette gemeldet, der Fehler sei behoben.

Alle drei Testdateien gruen unter Tcl **8.6** und **9.0.4**:
11 + 36 Faelle plus Guard.

## Siebter Durchgang -- zwei Lieferfehler

Die vierte Lesung (17.09., ~10:05) bestaetigt den sechsten Durchgang
und nennt zwei Fehler, die den Benutzer treffen, nicht den Code.

### Das Etiketten-Snippet in der README war nicht lauffaehig

```tcl
-paper [printlib::labelpaper "DK-22205"]  ;# -> "DK22205"
-scale origsize \
```

Kein Fortsetzungsstrich, dafuer ein `;#`. **Ein Kommentar in einer
fortgesetzten Argumentliste beendet den Aufruf.** Nachgestellt:

```
print bekam: 4 Optionen -> -printer Test -paper DK22205
invalid command name "-scale"
```

Vier statt zehn Optionen -- und der Abbruch kommt erst danach, an einer
Stelle, die nach etwas ganz anderem aussieht.

Berichtigt; der Hinweis steht jetzt als Prosa unter dem Block, nicht in
der Argumentliste. Nachgemessen: **10 Optionen**.

### pdftocairo druckte bei `-pages odd` alles

`pdftocairo` kennt nur `-f/-l`, also einen zusammenhaengenden Bereich.
`odd`, `even` und Listen wie `1,3,5` fielen durch beide Zweige -- ohne
`-f/-l` druckt es das **ganze** Dokument.

Jetzt scheitert es laut:

```
-pages 1-3    rc=0
-pages 2      rc=0
-pages odd    rc=1  ... nur eine Seitenzahl oder ein Bereich wie 1-3.
-pages even   rc=1      odd/even gehen nur ueber lp.
-pages 1,3,5  rc=1
```

**Die Meldung nennt den Ausweg**, nicht nur das Verbot -- `lp` kann
`odd`/`even` ueber `-o page-set`. Die Backends sind nicht gleichwertig,
und das gehoert gesagt statt verschwiegen.

`inv-pages-2.0` haelt es fest. Papier ist die einzige Ausgabe hier, die
man nicht zurueckrollen kann: ein Abbruch kostet nichts, ein Volljob
kostet den Stapel.

Testdateien: **12 + 36 Faelle plus Guard**, gruen unter 8.6 und 9.0.4.

## Achter Durchgang -- die Lizenz entschieden

**BSD 2-Clause**, und alle drei Stellen stimmen jetzt ueberein:

```
lib/tm/printlib-0.3.tm   Lizenz: BSD 2-Clause   (stand schon so)
LICENSE                  neu, 26 Zeilen
README.md                BSD 2-Clause -- see LICENSE
```

Vorher sagte der Kopf BSD, die README MIT, und eine `LICENSE` fehlte --
die Lizenz stand also **nirgends eindeutig**.

**Warum BSD 2-Clause:** inhaltlich deckungsgleich mit MIT, aber es ist
die Lizenzfamilie der Nachbarschaft -- Tcl selbst, pdf4tcl und tcllib
sind alle BSD-artig. Wer printlib daneben ausliefert, hat dann eine
Familie statt zweier. Und der Kopf sagte es ohnehin; dem zu folgen ist
einfacher, als ihn zu aendern.

**Fremdbestandteile** stehen jetzt in der README: `pdftocairo`, `lp`
und SumatraPDF werden als **externe Programme** gerufen -- keine
Verknuepfung, ihre Lizenzen reichen nicht in fremden Code. `pdfiumtcl`
ist anders: es wird in den Prozess geladen, und PDFiums eigene
(BSD-artige) Lizenz gilt dafuer.

### `inv-license-1.0`

Prueft LICENSE, Modulkopf und README auf dieselbe Angabe.
Gegengeprueft, beide Richtungen:

```
README auf MIT gesetzt  -> rot
LICENSE geloescht       -> rot
```

**Der erste Entwurf der Wache war zu scharf:** sie meldete jede
Erwaehnung von `MIT` -- also auch den Satz, der erklaert, dass die drei
Stellen frueher auseinanderliefen. Jetzt prueft sie die **Aussage**,
nicht das Wort: eine Zeile, die MIT als geltende Lizenz ausgibt.

Testdateien: **13 + 36 Faelle plus Guard**, gruen unter 8.6 und 9.0.4.

## Neunter Durchgang -- Booklet bekommt eine Frist

Statt "einbauen oder verwerfen" jetzt: **entschieden bis Maerz 2027.**

Der Entwurf bleibt, wo er ist. Er kostet nichts mehr -- er liegt unter
`doc/`, sein Kopf sagt was fehlt, `inv-booklet` haelt fest dass er
nicht im Modul ist, und R3a nennt den Weg. **Damit ist es keine offene
Frage mehr, sondern eine terminierte.**

Die Frist steht an drei Stellen, damit sie niemand suchen muss:

```
doc/roadmap.md R3a              Ueberschrift + Abschnitt
doc/printlib-booklet.tcl        Kopf
test/test-module-invariants.tcl bei inv-booklet
```

**Der Grund fuers Behalten steht dabei:** die acht `bookletOrder`-Faelle
sind der eigentliche Wert. Seitenzahlen umsortieren ist der Teil, der
bei Booklet-Druck schiefgeht -- wer das spaeter neu schreibt, schreibt
auch die Tests neu. Verwerfen wuerde mehr wegwerfen, als die Datei
gross ist.

**Und das Backend-Gatter ist vermerkt:** beim Einbauen muss `-booklet`
bei `pdftocairo` und `sumatra` abbrechen, nicht still einseitig
drucken. Dieselbe Regel wie bei `-pages` im siebten Durchgang.

## Zehnter Durchgang -- configure und PPD

Die beiden letzten Punkte der vierten Lesung, beide gemessen und
behoben.

### `configure` nahm ungerade Listen an

```
configure -printer HP -silent
  vorher:  rc 0, printer HP, silent ''
  jetzt:   rc 1, "Optionen muessen Paare sein -- 3 Argumente,
                  letztes: -silent"
```

Der Aufrufer wollte `-silent 1` und bekam das Gegenteil, ohne Meldung.
**Bei einem Drucker faellt das erst am Papier auf.**

Dasselbe Muster wie `array set opt $args` in tinventar -- dort war es
ein Probelauf, der trotzdem importierte. Unbekannte Optionen wurden
hier schon abgefangen; die ungerade Zahl nicht.

`configure` ohne Argumente liefert weiterhin das Dict.

### PPD-Rundlauf war fuer Anfuehrungszeichen kaputt

```
'Foto "matt"'  ->  '"Foto "matt""'
```

`savePpdFile` quotet Werte mit Leerzeichen, maskierte das
Anfuehrungszeichen IM Wert aber nicht -- der gequotete Bereich endete
zu frueh. Backslashes (Windows-Pfade) waren derselbe Fall.

Beide Seiten geaendert: schreiben mit Maskierung, lesen mit
Aufloesung. Gemessen ueber sechs Proben:

```
A4, "Tray 2", "", Foto "matt", C:\Pfad, a "b" c\d   -- alle ok
```

`inv-ppd-1.0` haelt den Rundlauf fest; Gegenprobe (Maskierung
entfernt) rot.

**Ein Umweg dabei:** meine ersten zwei Versuche schrieben doppelte
Backslashes, weil die Maskierung durch Python, Bash und Tcl
hindurchmusste. Erst der Weg ueber eine Datei mit unquotiertem Heredoc
lieferte, was gemeint war. Die Messung hat es jedesmal gezeigt.

Testdateien: **16 + 36 Faelle plus Guard**, gruen unter 8.6 und 9.0.4.
Alle fuenf Demos laufen.

## Stand

```
printlib 0.3, 47 Befehle
test-pdfium-backend        36/36 PASSED
test-pdfium-backend-guard  guard ok
```

## Offen

* `printlib-booklet.tcl` einbauen oder verwerfen -- die Entscheidung
  steht aus. Beim Einbauen waeren Tests fuer `bookletOrder` billig:
  reine Rechnung auf der Seitenliste, kein Drucker noetig.
