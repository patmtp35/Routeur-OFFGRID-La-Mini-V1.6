#!/usr/bin/env bash
# Recrée components/offsrmini : copie du composant `offsr` de SeByDocKy, renommée et adaptée 24 V / 48 V.
# Facultatif : components/offsrmini est déjà dans ce dépôt ; ce script sert à repartir de la dernière version de Seby.
# La liste exacte des modifications : components/offsrmini/MODIFICATIONS.md
#
# Usage :  ./prepare-offsr.sh                              (clone https://github.com/SeByDocKy/myESPhome)
#          OFFSR_SRC=/chemin/vers/myESPhome ./prepare-offsr.sh   (clone déjà présent)
# Valeurs de départ du profil 24 V (modifiables ensuite dans l'interface, mémorisées en flash) :
#          V24_START=27.0 V24_CHARGED=28.0 V24_DISCH=27.6 OUT_MIN=0.0 SP_CHARGE=15.0 ./prepare-offsr.sh
# Le profil 48 V garde les valeurs d'origine de Seby (53.0 / 55.8 / 55.6 V).
set -euo pipefail

V24_START="${V24_START:-27.0}"     # en dessous : sortie forcée à 0
V24_CHARGED="${V24_CHARGED:-28.0}" # au-dessus : consigne "floating"
V24_DISCH="${V24_DISCH:-27.6}"     # en dessous : consigne "charging"
OUT_MIN="${OUT_MIN:-0.0}"          # 0.18 d'origine : inadapté à un triac, la sortie ne descendrait jamais sous 18 %
SP_CHARGE="${SP_CHARGE:-15.0}"     # 20 A d'origine = limite de la pince HSTS016L, qui sature vers 19 A

cd "$(dirname "$0")"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

if [ -n "${OFFSR_SRC:-}" ]; then
  src="$OFFSR_SRC/components/offsr"
else
  git clone --depth 1 https://github.com/SeByDocKy/myESPhome.git "$tmp/myESPhome"
  src="$tmp/myESPhome/components/offsr"
fi
[ -d "$src" ] || { echo "components/offsr introuvable dans $src" >&2; exit 1; }

# les fichiers de documentation de ce dépôt survivent à la régénération
mkdir -p "$tmp/doc"
for f in MODIFICATIONS.md offsrmini-vs-upstream.diff; do
  [ -f "components/offsrmini/$f" ] && cp "components/offsrmini/$f" "$tmp/doc/$f"
done
rm -rf components/offsrmini
mkdir -p components
cp -r "$src" components/offsrmini
rm -f components/offsrmini/*.orig components/offsrmini/*.rej components/offsrmini/testoffsr.yaml
find components/offsrmini -type f \( -name '*.h' -o -name '*.cpp' -o -name '*.py' -o -name '*.yaml' \) -exec sed -i 's/\r$//' {} +

V24_START="$V24_START" V24_CHARGED="$V24_CHARGED" V24_DISCH="$V24_DISCH" OUT_MIN="$OUT_MIN" SP_CHARGE="$SP_CHARGE" \
python3 -I - <<'PY'
import os, re, glob, sys

def read(p):  return open(p, encoding="utf-8").read()
def write(p, s): open(p, "w", encoding="utf-8").write(s)
def replace_once(s, old, new, what):
    if s.count(old) != 1:
        sys.exit(f"échec : {what} ({s.count(old)} occurrences)")
    return s.replace(old, new)

base = "components/offsrmini/"

# 1. nom du composant = nom du dossier (5 sous-composants)
n = 0
for p in glob.glob(base + "*/__init__.py"):
    s = read(p)
    if 'DEPENDENCIES = ["offsr"]' in s:
        write(p, s.replace('DEPENDENCIES = ["offsr"]', 'DEPENDENCIES = ["offsrmini"]')); n += 1
if n != 5: sys.exit(f"échec : DEPENDENCIES ({n} fichiers au lieu de 5)")

# 2. bornes des tensions : 20-64 V (couvre 24 V et 48 V ; 45-60 V d'origine)
p = base + "number/__init__.py"; s = read(p)
for name, lo, hi in (("starting", "45.0", "60.0"), ("charged", "50.0", "60.0"), ("discharged", "45.0", "60.0")):
    s = replace_once(s, f"{name}_battery_voltage_config, min_value={lo}, max_value={hi}",
                        f"{name}_battery_voltage_config, min_value=20.0, max_value=64.0", f"bornes {name}")
write(p, s)

# 3. offsr.h : valeurs de départ output_min / consigne de charge, et setter du profil de tension
p = base + "offsr.h"; s = read(p)
s = replace_once(s, "current_output_min_ = 0.18f", f"current_output_min_ = {os.environ['OUT_MIN']}f", "output_min")
s = replace_once(s, "current_charging_setpoint_ = 20.0f", f"current_charging_setpoint_ = {os.environ['SP_CHARGE']}f", "consigne de charge")
anchor = s.index("  void set_charging_setpoint")
ins = s.rindex("#ifdef USE_NUMBER", 0, anchor)
setter = """  // offsrmini : valeurs de départ des 3 seuils de tension selon le profil de batterie (option `battery_voltage`).
  // Appelé avant les entités number : sans valeur mémorisée en flash, ce sont ces valeurs qui s'appliquent.
  void set_default_battery_voltages(float starting, float charged, float discharged) {
#ifdef USE_NUMBER
    this->current_starting_battery_voltage_ = starting;
    this->current_charged_battery_voltage_ = charged;
    this->current_discharged_battery_voltage_ = discharged;
#endif
  }
"""
write(p, s[:ins] + setter + s[ins:])

# 4. __init__.py : option battery_voltage (24 ou 48)
p = base + "__init__.py"; s = read(p)
s = replace_once(s, "CONF_POWER_ID = 'power_id'\n", "CONF_POWER_ID = 'power_id'\nCONF_BATTERY_VOLTAGE = 'battery_voltage'\n", "constante")
s = replace_once(s, "          cv.Optional(CONF_POWER_ID): cv.use_id(sensor.Sensor),\n",
                    "          cv.Optional(CONF_POWER_ID): cv.use_id(sensor.Sensor),\n"
                    "          cv.Optional(CONF_BATTERY_VOLTAGE, default=24): cv.one_of(24, 48, int=True),\n", "schéma")
s = s.rstrip("\n") + f"""

    # offsrmini : profil de batterie. 24 V : valeurs ci-dessous ; 48 V : valeurs d'origine de Seby.
    if config[CONF_BATTERY_VOLTAGE] == 48:
        cg.add(var.set_default_battery_voltages(53.0, 55.8, 55.6))
    else:
        cg.add(var.set_default_battery_voltages({os.environ['V24_START']}, {os.environ['V24_CHARGED']}, {os.environ['V24_DISCH']}))
"""
write(p, s)
print("OK")
PY

cp "$tmp/doc/"* components/offsrmini/ 2>/dev/null || true

echo "OK : components/offsrmini prêt (profil 24 V : ${V24_START} / ${V24_CHARGED} / ${V24_DISCH} V, output_min ${OUT_MIN}, consigne charge ${SP_CHARGE} A)"
