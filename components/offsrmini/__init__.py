import esphome.codegen as cg
import esphome.config_validation as cv
from esphome.components import sensor, output, time

CODEOWNERS = ["@sebydocky"]
DEPENDENCIES = ["time"]
MULTI_CONF = True

offsr_ns = cg.esphome_ns.namespace("offsr")
OFFSRComponent = offsr_ns.class_("OFFSRComponent", cg.Component)

from esphome.const import (
    CONF_ID,
)
CONF_OFFSR_ID = "offsr_id"
CONF_BATTERY_CURRENT_ID = 'battery_current_id'
CONF_BATTERY_VOLTAGE_ID = 'battery_voltage_id'
CONF_OUTPUT_ID = 'output_id'
CONF_POWER_ID = 'power_id'
CONF_BATTERY_VOLTAGE = 'battery_voltage'
# CONF_OUTPUT_NEVER_ZERO = 'output_never_zero'

# PidUpdateAction = offsr_ns.class_('PidUpdateAction', automation.Action)

OFFSRComponent_SCHEMA = cv.Schema(
    {
        cv.GenerateID(CONF_OFFSR_ID): cv.use_id(OFFSRComponent),
    }
)

CONFIG_SCHEMA = (
    cv.Schema(
        {
          cv.GenerateID(): cv.declare_id(OFFSRComponent),
          cv.Required(CONF_BATTERY_CURRENT_ID): cv.use_id(sensor.Sensor),
          cv.Required(CONF_BATTERY_VOLTAGE_ID): cv.use_id(sensor.Sensor),     
          cv.Required(CONF_OUTPUT_ID): cv.use_id(output.FloatOutput),
          cv.Optional(CONF_POWER_ID): cv.use_id(sensor.Sensor),
          cv.Optional(CONF_BATTERY_VOLTAGE, default=24): cv.one_of(24, 48, int=True),
		  # cv.Optional(CONF_OUTPUT_NEVER_ZERO, default=False): cv.boolean,
        }
    )
 )
 
async def to_code(config):
    var = cg.new_Pvariable(config[CONF_ID])
    await cg.register_component(var, config)
	
    sens = await cg.get_variable(config[CONF_BATTERY_CURRENT_ID])
    cg.add(var.set_battery_current_sensor(sens))

    sens = await cg.get_variable(config[CONF_BATTERY_VOLTAGE_ID])
    cg.add(var.set_battery_voltage_sensor(sens))
	
    out = await cg.get_variable(config[CONF_OUTPUT_ID])
    cg.add(var.set_device_output(out))
        
    if CONF_POWER_ID in config:
        sens = await cg.get_variable(config[CONF_POWER_ID])
        cg.add(var.set_power_sensor(sens))
      
    # if CONF_OUTPUT_NEVER_ZERO in config:
    #     cg.add(var.set_output_never_zero(config[CONF_OUTPUT_NEVER_ZERO]))

    # offsrmini : profil de batterie. 24 V : valeurs ci-dessous ; 48 V : valeurs d'origine de Seby.
    if config[CONF_BATTERY_VOLTAGE] == 48:
        cg.add(var.set_default_battery_voltages(53.0, 55.8, 55.6))
    else:
        cg.add(var.set_default_battery_voltages(27.0, 28.0, 27.6))
