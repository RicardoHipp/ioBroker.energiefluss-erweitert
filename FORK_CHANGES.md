# Fork-Änderungen gegenüber dem Original (SKB-CGN/ioBroker.energiefluss-erweitert)

Dieser Fork basiert auf Version **0.8.2** des Original-Adapters und behebt mehrere
Probleme im Low-Performance-Animationsmodus, die auf älteren Geräten (z. B. Android)
auftraten.

---

## Problem 1 – Ruckler im Low-Performance-Modus durch falschen Wrap-Punkt

### Ursache

Im Low-Performance-Modus wird die Animation nicht per CSS, sondern per JavaScript
gesteuert: Ein `requestAnimationFrame`-Loop verschiebt den `strokeDashoffset`-Wert
jedes SVG-Pfadelements schrittweise.

Der originale Code nutzte einen **hardcodierten Wrap-Wert von 136**:

```javascript
o %= 136;
```

Das bedeutet: Hat der Offset den Wert −136 erreicht, wird er auf 0 zurückgesetzt.
Damit die Animation **visuell nahtlos** wirkt, muss dieser Reset-Punkt exakt der
Gesamtlänge des `stroke-dasharray`-Musters entsprechen – denn erst dann sieht das
Muster bei Offset 0 genauso aus wie bei Offset −(Musterlänge).

Die tatsächlichen Dasharray-Längen hängen jedoch von den Nutzer-Einstellungen ab
(Anzahl Punkte, Abstand, Lückengröße) und können z. B. 72 px, 77 px, 121 px oder
165 px betragen. Ein Reset bei 136 px trifft fast nie den richtigen Punkt →
die Punkte springen sichtbar zurück.

Da die Sprung-Häufigkeit direkt mit der Animationsgeschwindigkeit zusammenhängt
(bei `Dauer = 1000 ms` einmal pro Sekunde, bei `5000 ms` einmal alle 5 Sekunden),
wurde das Problem fälschlicherweise als periodischer Performance-Einbruch
wahrgenommen.

### Lösung

Der `j`-Wert (Wrap-Grenze) wird jetzt **pro Element und pro Frame** direkt aus dem
Inline-Style `e.style.strokeDasharray` berechnet:

```javascript
const parts = e.style.strokeDasharray.split(",").map(parseFloat).filter(n => n > 0),
      j = parts.length ? parts.reduce((a, b) => a + b, 0) : 136;
```

Das Lesen eines Inline-Style-Werts erzwingt **keinen Browser-Reflow** und ist damit
performanceneutral. Da der Wert direkt aus dem Element gelesen wird, ist er immer
aktuell – auch wenn `refreshData` die Dasharray nachträglich ändert (z. B. weil sich
die Anzahl animierter Punkte durch einen Leistungswechsel geändert hat).

---

## Problem 2 – „Dauer der Animation" hatte im Live-Bild keine Wirkung

### Ursache

Der Low-Performance-Loop verwendete eine **fest kodierte Schrittgröße**:

```javascript
const L = 1.2; // px pro 20 ms – ignoriert die Einstellung "Dauer der Animation"
```

Die Einstellung `Dauer der Animation` (`animation_duration`) wirkte sich zwar auf
die CSS-Animation und die Vorschau in der Konfigurationsoberfläche aus, nicht aber
auf den JavaScript-Loop.

### Lösung

Die Schrittgröße wird jetzt aus `animation_duration` berechnet:

```javascript
const L = 2720 / (configuration.animation?.animation_duration ?? 1000);
```

Herleitung: Das Muster soll in `animation_duration` Millisekunden einmal durchlaufen
werden. Bei einem Frame-Intervall von 20 ms ergibt sich:
`Schritte_gesamt = animation_duration / 20`, also `L = 136 / (animation_duration / 20) = 2720 / animation_duration`.

---

## Problem 3 – `getComputedStyle` verursachte Layout-Thrashing

### Ursache

Der originale Code prüfte in jedem Frame für jedes Element, ob es sichtbar ist:

```javascript
if ("none" === getComputedStyle(e).display) return;
```

`getComputedStyle` erzwingt einen **synchronen Layout-Reflow** des Browsers.
Wird dieser Aufruf innerhalb eines `requestAnimationFrame`-Loops für mehrere Elemente
wiederholt, und gleichzeitig aktualisiert `refreshData` (bei jedem ioBroker-Daten-
Update, typisch alle 5 Sekunden) DOM-Elemente, entsteht **Layout-Thrashing**:
Der Browser muss Layout und Style abwechselnd neu berechnen, was zu messbaren
Frame-Drops führt.

### Lösung

Ersatz durch eine Prüfung des **Inline-Styles**, die keinen Reflow erzwingt:

```javascript
if (e.style.display === "none") return;
```

Elemente, die der Adapter versteckt, erhalten `style.display = "none"` als Inline-
Style (gesetzt durch den Socket-State-Handler). Diese Prüfung reicht daher aus.

---

## Problem 4 – Mehrere parallele Animations-Loops akkumulierten

### Ursache

Bei jedem Config-Reload (z. B. wenn Einstellungen gespeichert werden) wurde
`setLoadedConfig()` erneut aufgerufen, was einen **neuen** `requestAnimationFrame`-
Loop startete, ohne den vorherigen zu stoppen. Nach mehreren Reloads liefen
mehrere Loops gleichzeitig, die alle dasselbe Element animierten.

### Lösung

Ein globales Handle `lowPerfAnimFrame` speichert den aktuellen Frame-Handle.
Vor jedem neuen Loop-Start wird der vorherige explizit abgebrochen:

```javascript
let lowPerfAnimFrame = null; // global

// vor dem neuen Loop:
if (lowPerfAnimFrame) cancelAnimationFrame(lowPerfAnimFrame);
```

---

## Problem 5 – Maximaler Frame-Schritt begrenzt

### Ursache

Bei einem langen Frame (z. B. 200 ms durch ein DOM-Update von `refreshData`)
würde der Loop einen proportional großen Schritt machen:
`a = L * (200 / 20) = 10 × Normalschritt`. Das ist zwar mathematisch korrekt,
sieht aber visuell wie ein Sprung aus.

### Lösung

Die verstrichene Zeit wird auf maximal 50 ms begrenzt:

```javascript
const t = Math.min(e - E, 50);
```

Damit ist der maximale Schritt pro Frame auf das 2,5-fache des Normalschritts
bei 20 ms begrenzt, was visuell nicht auffällt.
