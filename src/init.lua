-- https://zigbeealliance.org/wp-content/uploads/2019/12/07-5123-06-zigbee-cluster-library-specification.pdf

local capabilities = require "st.capabilities"
local ZigbeeDriver = require "st.zigbee"
local defaults     = require "st.zigbee.defaults"
local clusters     = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types   = require "st.zigbee.data_types"
local constants    = require "st.zigbee.constants"
local log          = require "log"

local c_linkyPoweringModule = capabilities["stormachieve25639.linkyPoweringModule"]
local c_linkyMode           = capabilities["stormachieve25639.linkyMode"]
local c_linkySerial         = capabilities["stormachieve25639.linkySerial"]
local c_subscription        = capabilities["stormachieve25639.subscription"]
local c_instantaneous       = capabilities["stormachieve25639.instantaneous"]



-- read-only

local default_mode_configuration = {
  cluster           = 0xFF66,
  attribute         = 0x0300,
  data_type         = data_types.Uint8,
}

local default_ADC0_ADSC_configuration = {
  cluster           = clusters.SimpleMetering.ID,
  attribute         = 0x0308,
  data_type         = data_types.String,
}

local default_OPTARIF_NGTF_configuration = {
  cluster           = 0xFF66,
  attribute         = 0x0000,
  data_type         = data_types.String,
}

local default_ISOUSC_PREF_configuration = {
  cluster           = 0x0B01,
  attribute         = 0x000D,
  data_type         = data_types.Uint16,
}


-- Reportable

local default_voltage_configuration = {
  cluster           = clusters.PowerConfiguration.ID,
  attribute         = clusters.PowerConfiguration.attributes.MainsVoltage.ID,
  minimum_interval  = 30,
  maximum_interval  = 21600,
  data_type         = clusters.PowerConfiguration.attributes.MainsVoltage.base_type,
  reportable_change = 1
}

local default_index_0000_configuration = {
  cluster           = clusters.SimpleMetering.ID,
  attribute         = clusters.SimpleMetering.attributes.CurrentSummationDelivered.ID,
  minimum_interval  = 30,
  maximum_interval  = 60,
  data_type         = clusters.SimpleMetering.attributes.CurrentSummationDelivered.base_type,
  reportable_change = 1
}

local default_PAPP_SINST_SINST1_configuration = {
  cluster           = clusters.ElectricalMeasurement.ID,
  attribute         = clusters.ElectricalMeasurement.attributes.ApparentPower.ID,
  minimum_interval  = 30,
  maximum_interval  = 60,
  data_type         = clusters.ElectricalMeasurement.attributes.ApparentPower.base_type,
  reportable_change = 1
}

local default_IINST_configuration = {
  cluster           = clusters.ElectricalMeasurement.ID,
  attribute         = clusters.ElectricalMeasurement.attributes.RMSCurrent.ID,
  minimum_interval  = 30,
  maximum_interval  = 60,
  data_type         = clusters.ElectricalMeasurement.attributes.RMSCurrent.base_type,
  reportable_change = 1
}







local device_init = function(self, device)
   log.info("[" .. device.id .. "] Initializing ZLinky device")

   device:set_field(constants.SIMPLE_METERING_DIVISOR_KEY, 1000, {persist = true})

   -- read-only
   device:add_configured_attribute(default_mode_configuration)
   device:add_configured_attribute(default_ADC0_ADSC_configuration)
   device:add_configured_attribute(default_OPTARIF_NGTF_configuration)
   device:add_configured_attribute(default_ISOUSC_PREF_configuration)

   -- reportable
   device:add_configured_attribute(default_index_0000_configuration)
   device:add_monitored_attribute(default_index_0000_configuration)
   
   device:add_configured_attribute(default_IINST_configuration)
   device:add_monitored_attribute(default_IINST_configuration)
   
   device:add_configured_attribute(default_PAPP_SINST_SINST1_configuration)
   device:add_monitored_attribute(default_PAPP_SINST_SINST1_configuration)
  
   device:add_configured_attribute(default_voltage_configuration)
   device:add_monitored_attribute(default_voltage_configuration)

  -- mark device as online so it can be controlled from the app
  device:online()
end


--local do_configure = function(self, device)
--   device:configure()
--   device:refresh()
--end

local function zlinky_PAPP_SINST_SINST1(driver, device, value, zb_rx)
   device:emit_event_for_endpoint(
      zb_rx.address_header.src_endpoint.value,
      c_instantaneous.power({ value = value.value, unit = "VA" })
   )
end

local function zlinky_IINST_IINST1_IRMS1(driver, device, value, zb_rx)
   device:emit_event_for_endpoint(
      zb_rx.address_header.src_endpoint.value,
      c_instantaneous.current({ value = value.value, unit = "A" })
   )
end

local function zlinky_mode(driver, device, value, zb_rx)
   device:emit_component_event(device.profile.components.linky,
			       c_linkyMode.mode({ value = value.value }))  
end

local function zlinky_ADC0_ADSC(driver, device, value, zb_rx)
   device:emit_component_event(device.profile.components.linky,
			       c_linkySerial.serial({ value = value.value }))
end

local function zlinky_OPTARIF_NGTF(driver, device, value, zb_rx)
   device:emit_event_for_endpoint(
      zb_rx.address_header.src_endpoint.value,
      c_subscription.mode({ value = value.value })
   )
end

local function zlinky_ISOUSC_PREF(driver, device, value, zb_rx)
   device:emit_event_for_endpoint(
      zb_rx.address_header.src_endpoint.value,
      c_subscription.power({ value = value.value * 200 / 1000, unit = "kVA" })
   )
end



local function battery_volt_attr_handler(driver, device, value, zb_rx)
   device:emit_component_event(device.profile.components.linky,
			       c_linkyPoweringModule.voltage({ value = value.value, unit = "mV" }))
end

local function refresh_handler(driver, device, command)
  device:send(clusters.PowerConfiguration.attributes.MainsVoltage:read(device))
  device:send(clusters.Basic.attributes.SWBuildID:read(device))
  device:send(cluster_base.read_attribute(device,
					  data_types.ClusterId(0xFF66),
					  data_types.AttributeId(0x0300)))
  device:send(cluster_base.read_attribute(device,
					  data_types.ClusterId(0xFF66),
					  data_types.AttributeId(0x0000)))

    device:send(cluster_base.read_attribute(device,
					  data_types.ClusterId(0x0B01),
					  data_types.AttributeId(0x000D)))

end

local zigbee_zlinky_template = {
   supported_capabilities = {
      capabilities.refresh,
      capabilities.energyMeter,
--    capabilities.battery,
   },
   capability_handlers = {
--      [capabilities.refresh.ID] = {
--	 [capabilities.refresh.commands.refresh.NAME] = refresh_handler
--      }
   },
   additional_zcl_profiles = {
      [ clusters.SimpleMetering.ID        ] = true,
      [ 0x0B01                            ] = true,
      [ clusters.ElectricalMeasurement.ID ] = true,
      [ 0xFF66                            ] = true,
   },
   zigbee_handlers = {
      attr = {
	 [ clusters.PowerConfiguration.ID ] = {
	    [ clusters.PowerConfiguration.attributes.MainsVoltage.ID ] = battery_volt_attr_handler,
	 -- [ clusters.PowerConfiguration.attributes.MainsVoltageMinThreshold.ID ] = yo,
	 -- [ clusters.PowerConfiguration.attributes.MainsVoltageMaxThreshold.ID ] = yo,
	 },	
	 [ clusters.SimpleMetering.ID ] = { -- 0x0702
	 -- 0x0000 (handled by capabilities.energyMeter)
         -- [ clusters.SimpleMetering.attributes.CurrentSummationDelivered.ID ] = zlinky_index,
	 -- -- 0x0100
	 -- [ 0x0100 ] = zlinky_index,
	 -- -- 0x0102
	 -- [ 0x0102 ] = zlinky_index,
	 -- -- 0x0104
	 -- [ 0x0104 ] = zlinky_index,
	 -- -- 0x0106
	 -- [ 0x0106 ] = zlinky_index,
	 -- -- 0x0108
	 -- [ 0x0108 ] = zlinky_index,
	 -- -- 0x010A
	 -- [ 0x010A ] = zlinky_index,
	 -- -- 0x010C
	 -- [ 0x010C ] = zlinky_index,
	 -- -- 0x010E
	 -- [ 0x010E ] = zlinky_index,
	 -- -- 0x0110
	 -- [ 0x0110 ] = zlinky_index,
	 -- -- 0x0112
	 -- [ 0x0112 ] = zlinky_index,
	    -- 0x0308
	    [ 0x0308 ] = zlinky_ADC0_ADSC,
	 },
	 [ clusters.ElectricalMeasurement.ID ] = { -- 0x0B04
	    -- 0x0508 | IINST / IINST1 | IRMS1
	    [ clusters.ElectricalMeasurement.attributes.RMSCurrent.ID         ] = zlinky_IINST_IINST1_IRMS1,
	 -- -- 0x0908 | IINST2 | IRMS2
	 -- [ clusters.ElectricalMeasurement.attributes.RMSCurrentPhB.ID      ] = zlinky_IINST2_IRMS2,
	 -- -- 0x0A08 | IINST3 | IRMS3
	 -- [ clusters.ElectricalMeasurement.attributes.RMSCurrentPhC.ID      ] = zlinky_IINST3_IRMS3,
	 -- -- 0x050A | IMAX / IMAX1 | -
	 -- [ clusters.ElectricalMeasurement.attributes.RMSCurrentMax.ID      ] = zlinky_IMAX_IMAX1,
	 -- -- 0x090A | IMAX2
	 -- [ clusters.ElectricalMeasurement.attributes.RMSCurrentMaxPhB.ID   ] = zlinky_IMAX2,
	 -- -- 0x0A0A | IMAX3
	 -- [ clusters.ElectricalMeasurement.attributes.RMSCurrentMaxPhC.ID   ] = zlinky_IMAX3,
	 -- -- 0x050D | PMAX | SMAXN / SMAXN1
	 -- [ clusters.ElectricalMeasurement.attributes.ActivePowerMax.ID     ] = zlinky_PMAX_SMANX_SMAXN1,
	 -- 0x050F | PAPP | SINST / SINST1
	    [ clusters.ElectricalMeasurement.attributes.ApparentPower.ID      ] = zlinky_PAPP_SINST_SINST1, 
	 -- 0x090F | - | SINST2
	 -- [ clusters.ElectricalMeasurement.attributes.ApparentPowerPhB.ID   ] = zlinky_SINST2,
	 -- -- 0x0A0F | - | SINST3
	 -- [ clusters.ElectricalMeasurement.attributes.ApparentPowerPhC.ID   ] = zlinky_SINST3, 
	 -- -- 0x0305 | - | ERQ1
	 -- [ clusters.ElectricalMeasurement.attributes.TotalReactivePower.ID ] = zlinky_ERQ1,
	 -- -- 0x050E | - | ERQ2
	 -- [ clusters.ElectricalMeasurement.attributes.ReactivePower.ID      ] = zlinky_ERQ2,
	 -- -- 0x090E | - | ERQ3
	 -- [ clusters.ElectricalMeasurement.attributes.ReactivePowerPhB.ID   ] = zlinky_ERQ3,
	 -- -- 0x0A0E | - | ERQ4
	 -- [ clusters.ElectricalMeasurement.attributes.ReactivePowerPhC.ID   ] = zlinky_ERQ4,
	 -- -- 0x0505 | - | URMS1
	 -- [ clusters.ElectricalMeasurement.attributes.RMSVoltage.ID         ] = zlinky_URMS1,
	 -- -- 0x0905 | - | URMS2
	 -- [ clusters.ElectricalMeasurement.attributes.RMSVoltagePhB.ID      ] = zlinky_URMS2,
	 -- -- 0x0A05 | - | URMS3
	 -- [ clusters.ElectricalMeasurement.attributes.RMSVoltagePhC.ID      ] = zlinky_URMS3, 
	 -- -- 0x0511 | - | UMOY1
	 -- [ clusters.ElectricalMeasurement.attributes.AverageRMSVoltageMeasurementPeriod.ID    ] = zlinky_UMOY1,
	 -- -- 0x0911 | - | UMOY2
	 -- [ clusters.ElectricalMeasurement.attributes.AverageRMSVoltageMeasurementPeriodPhB.ID ] = zlinky_UMOY2,
	 -- -- 0x0A11 | - | UMOY3
	 -- [ clusters.ElectricalMeasurement.attributes.AverageRMSVoltageMeasurementPeriodPhC.ID ] = zlinky_UMOY3, 
	 -- -- 0x050B | - | CCASN
	 -- [ clusters.ElectricalMeasurement.attributes.ActivePower.ID        ] = zlinky_CCASN,
	 -- -- 0x090B | - | CCASN-1
	 -- [ clusters.ElectricalMeasurement.attributes.ActivePowerPhB.ID     ] = zlinky_CCASN1,
	 },
	 [ 0xFF66 ] = {
	    [ 0x0000 ] = zlinky_OPTARIF_NGTF,
	    [ 0x0300 ] = zlinky_mode
	 },
	 [ 0x0B01 ] = {
	 -- -- 0x000A | - | VTIC
	 -- [ 0x000A ] = zlinky_VTIC,
	    -- 0x000D | ISOUSC | PREF
	    [ 0x000D ] = zlinky_ISOUSC_PREF,
	 -- -- 0x000E | - | PCOUP
	 -- [ 0x000E ] = zlinky_PCOUP
	 }
      }
   },
   lifecycle_handlers = {
      init = device_init,
--      doConfigure = do_configure
   },
}


defaults.register_for_default_handlers(zigbee_zlinky_template, zigbee_zlinky_template.supported_capabilities)

local zigbee_zlinky = ZigbeeDriver("zigbee_zlinky", zigbee_zlinky_template)
zigbee_zlinky:run()





