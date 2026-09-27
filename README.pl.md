# AirCard macOS

[English](README.md) · [Українська](README.uk.md) · **Polski**

Natywny port na macOS procesu zmiany wyglądu kart Apple Wallet z [AirCard-Windows](https://github.com/Lumid-Off/AirCard-Windows). Interfejs napisano w Swift 6.2 ze Swift Concurrency do wykrywania iPhone’a, przygotowywania obrazów i zapisu atomowego.

> Status: przetestowano na iPhone18,3 z iOS 27.2 (kompilacja 24B5084k). Wykrywanie hasha karty obsługuje także iOS 18 (w tym 18.7.8). Projekt korzysta z prywatnych API Apple, jest eksperymentalny i nie jest oficjalnym narzędziem Apple.

## Języki

Aplikacja używa języka systemu macOS (Ustawienia systemowe → Ogólne → Język i region). Obsługiwane: angielski (`en`), ukraiński (`uk`), polski (`pl`). Portugalski brazylijski (`pt-BR`) czeka na aktualizację i na razie wyświetla tekst po angielsku.

Aby wymusić język polski:

```sh
open build/AirCardMac.app --args -AppleLanguages '(pl)'
```

## Instalacja i kompilacja

Najprościej pobrać `AirCardMac.dmg` ze strony wydań, otworzyć go i przeciągnąć `AirCardMac.app` do folderu Aplikacje. Aplikacja ma podpis ad-hoc, więc przy pierwszym uruchomieniu kliknij ją prawym przyciskiem → **Otwórz** (lub zezwól na uruchomienie w Ustawienia systemowe → Prywatność i ochrona).

Samodzielna kompilacja (wymaga Command Line Tools):

```sh
chmod +x Scripts/*.sh
Scripts/build_dmg.sh
open build/AirCardMac.dmg
```

DMG zawiera uniwersalną aplikację `AirCardMac.app` dla Apple Silicon i Intel.

## Jak zmienić obraz karty

1. **Przygotuj iPhone’a:** podłącz go kablem USB, odblokuj i stuknij **Zaufaj**. Raz otwórz **Apple Books** na iPhonie (aplikacja używa jej kanału synchronizacji do zapisu plików).
2. **Znajdź kartę:** na pasku bocznym kliknij **Wykryj z Wallet**. Na iPhonie otwórz **Wallet** i stuknij kartę, którą chcesz zmienić. Pojawi się ona w sekcji **Karty**. Kliknij ją prawym przyciskiem → **Użyj jako docelowej** (lub pozostaw włączone „Śledź ostatnio otwartą kartę”).
3. **Zaprojektuj obraz:** otwórz **Studio kart**. Kliknij **Dodaj obraz** i wybierz zdjęcie (lub przeciągnij je na kartę) albo wybierz jeden z gotowych **Stylów**. Dopasuj położenie i efekty w **Inspektorze**. Włącz **Strefy Wallet**, aby zobaczyć, która część jest widoczna w stosie kart.
4. **Zastosuj:** upewnij się, że w menu kart na pasku narzędzi wybrana jest właściwa karta, i kliknij **Zastosuj**. Trzymaj iPhone’a odblokowanego z włączonym ekranem, aż dziennik **Aktywność** pokaże zakończenie.
5. **Sprawdź wynik:** wymuś zamknięcie Wallet na iPhonie (przesuń ją w przełączniku aplikacji) i otwórz ponownie.

Wskazówki:

- Zalecany rozmiar obrazu to **1536 × 969** (proporcje karty). Inne rozmiary są skalowane zgodnie z wybranym trybem dopasowania.
- Każdy zastosowany projekt trafia do **Historii zastosowanych skórek** karty — można go otworzyć w studiu lub zastosować ponownie.
- **Aby przywrócić oryginalny projekt banku,** usuń kartę z Wallet i dodaj ją ponownie. Aplikacja nie może odczytać ani zarchiwizować oryginalnej grafiki.
- Jeśli nic się nie zmieniło, zablokuj i odblokuj iPhone’a, ponownie otwórz Wallet i sprawdź błędy w dzienniku **Aktywność**.

## Studio kart

- Warstwy: obraz, kolor, gradient liniowy/radialny/stożkowy, gradient siatkowy, holografia, szczotkowany metal, połysk, ziarno, wzory (linie, kropki, siatka, karbon, gilosz, fale) i tekst.
- Każda warstwa ma krycie i tryb mieszania, a do tego globalne korekty koloru, winietę, poświatę, rozmycie i wyostrzenie.
- Gotowe style: Tytan, Holo, Zorza, Karbon, Gilosz, Szkło, Zachód słońca, Noir.
- Przeciągnij kartę, aby ją pochylić i zobaczyć odbicia. Wallet otrzymuje statyczny obraz, więc „Nachylenie” wybiera zamrożony kąt eksportu.
- Cofnij/ponów, zapis i otwieranie `.aircardskin`, import obrazów przez przeciąganie.
- Zastosowane skórki są zapisywane w `~/Library/Application Support/AirCard/Cards/<hash>/`.

## Ograniczenia

- **Nie można odczytać bieżącej grafiki karty w Wallet** — dane Wallet są niedostępne przez AFC, a AirTraffic obsługuje tylko zapis.
- Dlatego **nie ma kopii zapasowej oryginalnego projektu**. Aby go przywrócić, usuń kartę z Wallet i dodaj ponownie.
- Efekty ruchu/żyroskopu rysuje iOS; zapisany obraz pozostaje statyczny.

Szczegóły techniczne (format `.passthm`, kolor cyfr klawiatury, pamięci podręczne TelephonyUI) znajdziesz w [angielskim README](README.md).
