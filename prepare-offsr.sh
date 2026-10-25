#!/usr/bin/env bash
# Prépare components/offsrmini (copie du composant offsr de SeByDocKy, renommée) pour un pack 24 V, à côté de la-mini.yaml.
# Remplace patches/offsr-24v.patch, qui ne s'applique plus sur le HEAD actuel (fins de ligne CRLF + nouveau champ coeff_multiplier).
#
# Usage :  ./prepare-offsr.sh                      (clone https://github.com/SeByDocKy/myESPhome)
#          OFFSR_SRC=/chemin/vers/myESPhome ./prepare-offsr.sh   (clone déjà présent)
# Réglages de départ (modifiables ensuite dans l'interface, mémorisés en flash) :
#          V_START=27.0 V_CHARGED=28.0 V_DISCH=27.6 OUT_MIN=0.0 SP_CHARGE=15.0 ./prepare-offsr.sh
set -euo pipefail

V_START="${V_START:-27.0}"     # en dessous : sortie forcée à 0
V_CHARGED="${V_CHARGED:-28.0}" # au-dessus : consigne "floating"
V_DISCH="${V_DISCH:-27.6}"     # en dessous : consigne "charging"
OUT_MIN="${OUT_MIN:-0.0}"      # 0.18 d'origine : inadapté à un triac, la sortie ne descendrait jamais sous 18 %
SP_CHARGE="${SP_CHARGE:-15.0}" # consigne de courant en zone "charge" (20 A d'origine = limite de la pince HSTS016L, qui sature vers 19 A)

cd "$(dirname "$0")"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

if [ -n "${OFFSR_SRC:-}" ]; then
  src="$OFFSR_SRC/components/offsr"
else
  git clone --depth 1 https://github.com/SeByDocKy/myESPhome.git "$tmp/myESPhome"
  src="$tmp/myESPhome/components/offsr"
fi
[ -d "$src" ] || { echo "components/offsr introuvable dans $src" >&2; exit 1; }

rm -rf components/offsrmini
mkdir -p components
cp -r "$src" components/offsrmini
rm -f components/offsrmini/*.orig components/offsrmini/*.rej components/offsrmini/testoffsr.yaml
find components/offsrmini -type f \( -name '*.h' -o -name '*.cpp' -o -name '*.py' -o -name '*.yaml' \) -exec sed -i 's/\r$//' {} +

# le composant s'appelle offsrmini (dossier = nom du composant) : son components/offsr d'origine reste intact
# (l'espace de noms C++ reste "offsr" : les deux ne sont jamais compilés dans le même firmware)
grep -rl 'DEPENDENCIES = \["offsr"\]' components/offsrmini | xargs sed -i 's/DEPENDENCIES = \["offsr"\]/DEPENDENCIES = ["offsrmini"]/'
[ "$(grep -rc 'DEPENDENCIES = \["offsrmini"\]' components/offsrmini --include=__init__.py | awk -F: '{s+=$2} END{print s}')" = 5 ] || { echo "échec : DEPENDENCIES" >&2; exit 1; }

h=components/offsrmini/offsr.h
n=components/offsrmini/number/__init__.py

# défauts C++ (utilisés tant que rien n'est mémorisé en flash)
sed -i -E "s/(current_starting_battery_voltage_ = )[0-9.]+f/\1${V_START}f/" "$h"
sed -i -E "s/(current_charged_battery_voltage_ = )[0-9.]+f/\1${V_CHARGED}f/" "$h"
sed -i -E "s/(current_discharged_battery_voltage_ = )[0-9.]+f/\1${V_DISCH}f/" "$h"
sed -i -E "s/(current_output_min_ = )[0-9.]+f/\1${OUT_MIN}f/" "$h"
sed -i -E "s/(current_charging_setpoint_ = )[0-9.]+f/\1${SP_CHARGE}f/" "$h"

# bornes des curseurs (45-60 V d'origine, calibrées pour ~48 V)
sed -i -E "s/(starting_battery_voltage_config, min_value=)[0-9.]+(, max_value=)[0-9.]+/\120.0\232.0/" "$n"
sed -i -E "s/(charged_battery_voltage_config, min_value=)[0-9.]+(, max_value=)[0-9.]+/\120.0\232.0/" "$n"
sed -i -E "s/(discharged_battery_voltage_config, min_value=)[0-9.]+(, max_value=)[0-9.]+/\120.0\232.0/" "$n"

# contrôle : chaque remplacement doit avoir eu lieu
grep -q "current_starting_battery_voltage_ = ${V_START}f" "$h"       || { echo "échec : défaut starting"   >&2; exit 1; }
grep -q "current_charged_battery_voltage_ = ${V_CHARGED}f" "$h"      || { echo "échec : défaut charged"    >&2; exit 1; }
grep -q "current_discharged_battery_voltage_ = ${V_DISCH}f" "$h"     || { echo "échec : défaut discharged" >&2; exit 1; }
grep -q "current_output_min_ = ${OUT_MIN}f" "$h"                     || { echo "échec : défaut output_min" >&2; exit 1; }
grep -q "current_charging_setpoint_ = ${SP_CHARGE}f" "$h"            || { echo "échec : consigne charge"   >&2; exit 1; }
[ "$(grep -c 'min_value=20.0, max_value=32.0' "$n")" = 3 ]           || { echo "échec : bornes des tensions" >&2; exit 1; }

echo "OK : components/offsrmini prêt (start ${V_START} V, charged ${V_CHARGED} V, discharged ${V_DISCH} V, output_min ${OUT_MIN}, consigne charge ${SP_CHARGE} A)"
