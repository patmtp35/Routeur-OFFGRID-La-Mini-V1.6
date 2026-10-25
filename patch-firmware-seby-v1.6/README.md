# Firmware d'origine de Seby (v1.6) : correctif de la perte des paramètres

> Ce dossier concerne l'**ancien firmware Arduino/PlatformIO** de SeByDocKy. La version ESPHome de la mini est à la [racine du dépôt](../README.md).

Correctif pour le firmware [SeByDocKy/routeur_solaire](https://github.com/SeByDocKy/routeur_solaire/tree/v1.6) (branche `v1.6`, projet Réseautonome).

**Symptôme :** les réglages saisis dans l'interface web (seuil de démarrage batterie, coefficients de la pince, Wi-Fi, MQTT...) disparaissent à chaque redémarrage de l'ESP32 et reviennent aux valeurs codées en dur dans `settings.h`.

**Cause :** la zone EEPROM réservée (450 octets) est plus petite que la structure `param` à sauvegarder (480 à 492 octets). Aucune sauvegarde n'est jamais écrite, et aucune erreur n'est signalée.

**Correctif :** `correctif-eeprom-v1.6.patch` (2 fichiers, 12 lignes ajoutées, 6 supprimées).

---

## 1. Ce qui se passe exactement

### 1.1 Les chiffres

`EEPROM_SIZE` vaut 450 dans `src/prgEEprom.cpp` depuis la première version (avril 2020). La structure `param` de `src/settings.h` a grossi version après version. Tailles mesurées en compilant le `settings.h` de chaque commit, marqueur de 1 octet compris :

| Commit | Date | Version | `sizeof(param)` + 1 | Dans 450 octets ? |
|---|---|---|---|---|
| `ddab21f` | 30/04/2020 | 1.0 | 429 | oui |
| `250907e` | 16/02/2021 | 1.5 | 441 | oui |
| `be642d0` | 26/10/2022 | 1.5 (en cours) | 469 | **non** |
| `44f8dee` | 13/01/2023 | 1.6 | 493 | **non** |

Sur la v1.6 publiée, la structure fait 480 octets sans les options MAXI et 492 avec : elle dépasse dans les deux cas. Le correctif de taille s'imposait donc à tous les utilisateurs de la v1.6, quelle que soit la configuration de `settings.h`.

### 1.2 Pourquoi aucune erreur

`platformio.ini` utilise `espressif32 @ 3.5`, donc Arduino-ESP32 1.0.6. Dans [`EEPROM.h`](https://github.com/espressif/arduino-esp32/blob/1.0.6/libraries/EEPROM/src/EEPROM.h) de cette version, `put()` et `get()` commencent par :

```cpp
if (address < 0 || address + sizeof(T) > _size)
  return t;
```

Si la structure dépasse la taille, ces deux fonctions ne font rien et ne signalent rien. Donc :

- `sauve_param()` n'écrit rien (seul l'octet marqueur, écrit à part, passe) ;
- `restore_param()` ne relit rien : au démarrage, `routeur` garde les valeurs de `settings.h`.

### 1.3 Conséquences

- Les réglages ne survivent que tant que l'ESP ne redémarre pas (coupure, plantage, chien de garde, bouton « reboot »).
- Après chaque redémarrage, `actif` revient à `false` (valeur de `settings.h`) : le routeur ne reprend pas tout seul.
- Enregistrer l'onglet « Communication » provoque lui-même un redémarrage (`restartEsp`) : le Wi-Fi et le MQTT repartent aux valeurs de `settings.h`.

### 1.4 Défauts annexes corrigés au passage

- **`EEPROM.end()` au premier démarrage.** Dans la branche « premier démarrage » de `RAPrgEEpromClass::setup()`, `EEPROM.end()` remet la taille interne à 0 : toutes les sauvegardes suivantes de ce démarrage étaient ignorées jusqu'au reboot suivant.
- **`saveWifiSettings`.** Contrairement aux trois autres fonctions `save...Settings`, elle n'appelait ni `sauve_param()` ni `pause_inter = 1`. Les réglages Wi-Fi n'étaient pas enregistrés, et l'interruption du triac, arrêtée au début de la fonction, n'était pas relancée.

---

## 2. Contenu du correctif

**`src/prgEEprom.cpp`**

1. `EEPROM_SIZE` passe de 450 à **1024** (maximum 4096 sur ESP32).
2. Ajout d'un `static_assert(sizeof(param) + 1 <= EEPROM_SIZE, ...)` : si la structure redépasse la taille un jour, la compilation échoue au lieu de perdre les réglages en silence.
3. Le marqueur passe de 123 à **124** (`EEPROM_MARQUEUR`). **Ce changement est obligatoire.** Le blob EEPROM existant de ta carte contient `123` suivi de `0xFF`. À l'agrandissement, la bibliothèque conserve ce contenu : sans nouveau marqueur, le firmware croirait l'EEPROM valide et chargerait des paramètres corrompus (nombres invalides, chaînes à `0xFF`).
4. Suppression de `EEPROM.end()` et de `delay(5000)` dans la branche « premier démarrage ».

**`src/communication.cpp`**

5. `saveWifiSettings` appelle `RAPrgEEprom.sauve_param();` puis `pause_inter = 1;`.

---

## 3. Appliquer le patch

Place `correctif-eeprom-v1.6.patch` à la racine du projet Seby (le dossier qui contient `platformio.ini`, `src/`...). Si tu as déjà modifié `settings.h`, ça ne gêne pas : le patch ne le touche pas.

### Méthode A : `git apply` (recommandée)

Depuis PowerShell, Git Bash ou un terminal, à la racine du projet :

```
git apply --check correctif-eeprom-v1.6.patch
git apply correctif-eeprom-v1.6.patch
```

La première commande ne modifie rien : elle vérifie seulement que le patch s'applique. `git apply` fonctionne aussi sur un dossier récupéré en ZIP (sans dépôt git). Si Windows signale des erreurs de fins de ligne, ajoute `--ignore-whitespace`.

### Méthode B : `patch`

```
patch -p1 --dry-run < correctif-eeprom-v1.6.patch
patch -p1 < correctif-eeprom-v1.6.patch
```

### Méthode C : à la main

Si tu as modifié ces fichiers ailleurs et que le patch refuse de s'appliquer, fais les 3 modifications.

Dans `src/prgEEprom.cpp`, remplace :

```cpp
#define EEPROM_SIZE 450
```

par :

```cpp
#define EEPROM_SIZE 1024
#define EEPROM_MARQUEUR 124

static_assert(sizeof(param) + 1 <= EEPROM_SIZE, "EEPROM_SIZE trop petit pour struct param (settings.h)");
```

Dans la même fonction `RAPrgEEpromClass::setup()`, remplace `if (EEPROM.read(0) != 123)` par `if (EEPROM.read(0) != EEPROM_MARQUEUR)`, et supprime dans ce bloc les lignes `EEPROM.end();` et `delay(5000);`. Dans `sauve_param()`, remplace `EEPROM.writeByte(0, 123);` par `EEPROM.writeByte(0, EEPROM_MARQUEUR);`.

Dans `src/communication.cpp`, fonction `saveWifiSettings`, après `doc.clear();`, ajoute :

```cpp
RAPrgEEprom.sauve_param();
pause_inter = 1;
```

---

## 4. Flasher

1. Dans PlatformIO, environnement **`env:routeur_solaire`** (ou `routeur_solaire_OTA` si l'OTA est déjà en place) : **Build**, puis **Upload**.
2. Il n'est **pas** nécessaire de re-flasher le système de fichiers (`Upload Filesystem Image`) : l'interface web ne change pas.
3. Au premier démarrage, le nouveau marqueur est détecté et l'EEPROM est initialisée avec les valeurs de ton `settings.h`. Ressaisis tes réglages dans l'interface.
4. Laisse l'ESP redémarrer une fois avant de te fier aux sauvegardes.

## 5. Vérifier que ça marche

1. Dans l'interface, change `seuilDemarrageBatterie`, puis enregistre.
2. Onglet « action » : redémarre l'ESP.
3. Retourne dans les réglages : la valeur doit être celle que tu as saisie. Avant correctif, elle revenait à celle de `settings.h`.
4. Contrôle aussi le Wi-Fi : change le SSID ou le mot de passe, redémarre, et vérifie que l'ESP se reconnecte.

---

## 6. Ce qui est vérifié et ce qui ne l'est pas

**Vérifié :**

- Les tailles de `param` par commit, mesurées en compilant les vrais `settings.h`.
- Le comportement de `EEPROM.put/get/begin/end`, lu dans le code source d'Arduino-ESP32 1.0.6.
- Le `static_assert` compile avec 1024 et échoue avec 450.
- Le patch s'applique sur un `v1.6` vierge (`git apply --check`).
- Le bug lui-même sur la carte : avant correctif, la valeur disparaissait après redémarrage.

**Non vérifié :**

- La compilation complète du firmware avec PlatformIO.
- Le comportement du firmware corrigé sur la carte.

Si le test de la section 5 échoue après patch, ouvre une issue avec le log série (mets `VERBOSE` à 3 dans `settings.h`).

## 7. Non corrigé ici (pistes, non prouvées sur ce matériel)

- **Reconnexion bloquante.** `reconnect()` peut bloquer plus de 4 s (Wi-Fi puis MQTT injoignable). Le chien de garde du triac (`triac.cpp`) redémarre l'ESP après environ 4 s sans retour dans `loop()`, mais seulement quand le gradateur est actif.
- **POST du serveur web.** Le corps n'est lu que s'il est déjà arrivé, sans `Content-Length`. S'il manque, `atof(nullptr)` / `strcpy(..., nullptr)` peut planter l'ESP.
- **`strcpy` sans limite** sur `ssid[30]`, `mqttServer[30]`, topics `[30]`... : un champ trop long écrase le champ voisin.
- **Durée d'un tour de `loop()`.** Chaque tour fait 14 000 itérations de mesure (`mesurePinceTension(700, 20)`), et le serveur ne traite qu'une requête par tour : pages lentes et routage coupé à chaque consultation (durée du tour non mesurée).

Je les ai laissés hors de ce patch pour isoler le correctif confirmé.

---

## Crédits

- Firmware d'origine : [SeByDocKy/routeur_solaire](https://github.com/SeByDocKy/routeur_solaire), équipe Discord Réseautonome.
- Analyse et correctif préparés avec l'aide de Claude (Anthropic).
