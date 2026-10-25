# La Mini sous ESPHome : routeur solaire off-grid 24 V

Reprise sous [ESPHome](https://esphome.io) du matériel de « la mini » (carte PCB V1.0b du projet [SeByDocKy/routeur_solaire](https://github.com/SeByDocKy/routeur_solaire), Réseautonome). Le routeur détourne le surplus solaire d'un pack de batteries 24 V gel vers une résistance (radiateur, ballon) via le triac de la carte.

La régulation est le composant `offsr` de SeByDocKy ([myESPhome](https://github.com/SeByDocKy/myESPhome)) : PID sur le courant net de la batterie, avec une consigne différente selon la tension (charge, absorption, floating).

> L'ancien firmware Arduino de Seby (v1.6) est toujours là, avec son correctif de perte de paramètres : [patch-firmware-seby-v1.6/](patch-firmware-seby-v1.6/README.md).

## Matériel visé

| Élément | Détail |
|---|---|
| Carte | PCB mini V1.0b, ESP32 Wemos D1 mini32, triac BTA41-600B + MOC3021S, détection de passage par zéro (MB10S + EL357N) |
| Courant batterie | Pince Hall HSTS016L 20 A (2,5 V ± 0,625 V pour ± 20 A), montée sur le + du pool, avant le busbar |
| Tension batterie | Diviseur de la carte sur GPIO36 |
| Écran | OLED 0,66" 64x48 (shield Wemos), I2C 0x3C |
| Sonde | DS18B20 sur GPIO23 |
| Non utilisé | PZEM, sortie 2, relais, potentiomètre, pince AC |

Broches (identiques au firmware d'origine) : triac GPIO27, passage par zéro GPIO33, pince GPIO32, référence pince GPIO34, tension GPIO36, DS18B20 GPIO23, I2C GPIO21/GPIO22. Elles se changent dans les `substitutions` de `la-mini.yaml`.

## Fichiers

| Fichier | Rôle |
|---|---|
| `la-mini.yaml` | Configuration ESPHome complète. Tout se règle dans les `substitutions` en haut. Pas de `!secret`. |
| `prepare-offsr.sh` | Crée `components/offsrmini` à partir du composant de Seby, adapté au 24 V. |

Le code de Seby n'est pas dans ce dépôt (il n'a pas de licence) : le script le récupère chez lui et le modifie localement. `components/` est dans le `.gitignore`.

## Installation

1. **Préparer le composant.** Dans le dossier du YAML : `./prepare-offsr.sh` (bash : Git Bash, WSL ou le terminal de Home Assistant). Il crée `components/offsrmini`. Le script prend des variables pour d'autres valeurs de départ :
   `V_START=27.0 V_CHARGED=28.0 V_DISCH=27.6 OUT_MIN=0.0 SP_CHARGE=15.0 ./prepare-offsr.sh`
   Sans bash, copie à la main `components/offsr` de myESPhome vers `components/offsrmini`, puis remplace `DEPENDENCIES = ["offsr"]` par `["offsrmini"]` dans les 5 sous-dossiers, les 4 défauts de tension / `output_min` / consigne de charge dans `offsr.h`, et les bornes des 3 tensions (20–32 V) dans `number/__init__.py`.
2. **Renseigner le YAML** : `wifi_ssid` et `wifi_password`, et pour le SmartShunt en BLE `smartshunt_mac` et `smartshunt_bindkey` (VictronConnect, Produit, Infos, clé de chiffrement). Pour le mode via Home Assistant, `ha_voltage_entity` et `ha_current_entity`.
3. **Compiler et flasher** (ESPHome Builder ou `esphome run`). Le premier flash se fait par USB.

Ne publie jamais le YAML rempli avec tes vrais identifiants.

Le composant porte un nom à part (`offsrmini`) pour cohabiter dans un même dossier `components/` avec un `offsr` déjà utilisé par un autre routeur sans y toucher.

## Sources de mesure

Le sélecteur **Source de mesure** choisit ce que voit `offsr` :

| Source | Tension | Courant |
|---|---|---|
| Autonome (pince + diviseur) | Diviseur de la carte | Pince HSTS016L |
| SmartShunt BLE | Annonces Victron en Bluetooth | Annonces Victron en Bluetooth |
| SmartShunt via HA | Entité HA | Entité HA |

Pour le mode HA, prends les entités du **SmartShunt**, pas celles d'un MPPT : le « courant batterie » d'un MPPT n'est pas le courant net de la batterie.

## Sécurité intégrée

- **Source perdue** (BLE coupé, HA absent, diviseur débranché, tension < 5 V) : la tension envoyée à `offsr` passe à 0 V, ce qui force la sortie à 0. Un simple `timeout` ne suffit pas : `offsr` ne recalcule que sur un nouveau courant et resterait figé sur sa dernière sortie, voire produirait `NaN`.
- **Courant perdu** : 0 A est envoyé, sous la consigne, donc `offsr` réduit la charge.
- **Surchauffe** : si le DS18B20 dépasse `Température max` (80 °C par défaut), le routage est désactivé et le curseur manuel remis à 0.
- **Après un premier flash**, `Routeur activation` est OFF.
- **Pas de redémarrage de l'ESP quand HA est absent** (`api: reboot_timeout: 0s`).

En mode gel de la régulation (`Routeur gel de la régulation` ON), `offsr` n'écrit plus la sortie : plus aucune de ces protections, sauf la surchauffe.

## Calibration

Les valeurs de départ sont des estimations, pas des mesures. Les réglages sont mémorisés en flash : changer une substitution plus tard n'écrase pas une valeur déjà mémorisée.

| Réglage | Méthode |
|---|---|
| Tension : gain diviseur | Comparer « Tension batterie locale » à un multimètre. Nouveau gain = gain × V multimètre / V affichée. |
| Pince : zéro (A) | Aucun courant dans le câble (charges et chargeurs coupés) : régler pour lire 0,00 A. Refaire à chaud, le zéro dérive. |
| Pince : gain (A/V) | Valeur constructeur : 32 A/V (20 A / 0,625 V). Comparer au courant d'un SmartShunt ou d'une pince ampèremétrique : nouveau gain = gain × I réel / I affiché. |
| Pince : sens inversé | À activer si la batterie charge et que « Courant batterie local » est négatif. `offsr` attend courant > 0 = charge. |

La pince sature vers ± 19 A (la sortie dépasse 3,1 V, limite de l'ADC de l'ESP32) : sans alerte, la mesure est alors fausse. Garde donc la consigne de charge à 15 A ou moins avec cette pince, et vérifie que l'entrée GPIO34 de ta carte est protégée si plus de 20 A peuvent traverser la pince.

## Réglages de la régulation

Seuils de départ pour un pool **gel 24 V** : démarrage 27,0 V, « déchargée » 27,6 V, « chargée » 28,0 V ; consigne de charge 15 A, absorption 5 A, floating 0 A ; `output_min` 0.

Règle pour « Tension seuil chargée » : **l'absorption la plus basse de tes chargeurs moins 0,2 V**, relevée par grand froid. Au-dessus de ce seuil, le routeur vise 0 A de courant net et détourne tout le courant de charge. Un seuil trop bas empêche le pool de finir son absorption, ce qui use vite un gel. Un chargeur à compensation de température monte d'environ 36 mV par °C sur un pack gel 24 V : un garage à 5 °C au lieu de 25 °C ajoute environ 0,7 V.

Le PID part de Kp 4, Ki 0, Kd 0 (valeurs de Seby). `output_min` à 0 est nécessaire avec un triac : avec la valeur d'origine de 0,18, la sortie ne descendrait jamais sous 18 %.

## Entités principales

- Réglages : source de mesure, calibration (gain diviseur, gain et zéro pince, sens), température max, consignes de courant (charge, absorption, floating), seuils de tension (démarrage, déchargée, chargée), Kp/Ki/Kd, sortie min/max.
- Commandes : Routeur activation, gel de la régulation, mode PID complet, sens inversé, **Puissance manuelle** (curseur 0–100 %, pour tester le triac avec le gel de la régulation activé).
- Mesures : tension et courant locaux, SmartShunt BLE, tension et courant utilisés par `offsr`, courant lissé, sortie, consigne, erreur, température, ADC bruts (diagnostic).
- Écran : 2 pages alternées toutes les 3 s (tension, courant, sortie, état du routage ; source, consigne, température).

## Premier essai

1. Banc, **pas sur la vraie batterie** : ampoule ou radiateur bain d'huile comme charge.
2. `Routeur activation` OFF, source « Autonome », calibration complète.
3. Triac : `Routeur gel de la régulation` ON, monter doucement `Puissance manuelle`, la remettre à 0 ensuite.
4. Régulation : `Routeur gel de la régulation` OFF, vérifier le sens du courant, puis `Routeur activation` ON.
5. Ne passer sur la batterie réelle qu'après avoir vérifié que la sortie tombe à 0 quand la source est coupée.

## Ce qui est vérifié, ce qui ne l'est pas

Vérifié :

- Compilation et flash sous ESPHome 2026.10.0.
- Réseau, API, DS18B20, écran OLED 64x48.
- Lecture du SmartShunt en BLE (testé avec une batterie 48 V sur la table).
- Sécurité sur source perdue : sans batterie sur le diviseur, la tension utilisée tombe à 0 V et la sortie reste à 0.
- Sens de l'erreur : un courant négatif donne une erreur négative.

Non testé :

- La pince Hall et le diviseur avec de vraies valeurs.
- Le triac et la détection de passage par zéro, sur charge.
- La régulation sous charge, le réglage du PID, le mode « SmartShunt via HA ».
- Le comportement sur le pool 24 V gel réel.

Limites connues :

- `ac_dimmer` démarre la gâchette sur le front descendant du passage par zéro, comme le firmware d'origine : à confirmer sur l'oscilloscope ou à l'essai sur charge résistive.
- Pas de détection de coupure de thermostat (elle demande un PZEM, absent ici).
- La police de l'écran est téléchargée au moment de la compilation (`gfonts://Roboto`) : il faut un accès internet à ce moment-là.
- Wi-Fi en clair dans le YAML, OTA sans mot de passe, API sans chiffrement : choix « sans secret », pensé pour un réseau local.

## Crédits

- Matériel et firmware d'origine : [SeByDocKy/routeur_solaire](https://github.com/SeByDocKy/routeur_solaire), équipe Discord Réseautonome.
- Composant `offsr` : [SeByDocKy/myESPhome](https://github.com/SeByDocKy/myESPhome).
- Lecture BLE Victron : [Fabian-Schmidt/esphome-victron_ble](https://github.com/Fabian-Schmidt/esphome-victron_ble).
- Configuration et documentation préparées avec l'aide de Claude (Anthropic).
