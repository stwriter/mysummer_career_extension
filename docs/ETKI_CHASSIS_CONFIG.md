# ETK-I Chassis Configuration - Referencia Tecnica

## Objetivo

El ETK-I inicial del jugador debe ser un **chasis vacio** con lo minimo necesario para existir en el juego. El jugador debe comprar e instalar todas las piezas para hacerlo funcional.

## Configuracion Base

Archivo fuente: `vehicles/etki/rolling.pc`

```lua
{
  mainPartName = "etki",
  mainPartPath = "/etki",
  model = "etki",
  partConfigFilename = "vehicles/etki/rolling.pc",
  -- ... resto de config
}
```

## Pintura

Azul oscuro mate sin clearcoat:

```lua
paints = {
  {
    baseColor = { 0.03, 0.06, 0.2, 1.2 },
    clearcoat = 0,
    clearcoatRoughness = 0,
    metallic = 0,
    roughness = 0.07
  },
  -- Repetir 3 veces para las 3 capas
}
```

## Piezas que DEBEN ESTAR

Estas piezas son necesarias para que el vehiculo exista:

### 1. Carroceria Principal
```lua
etki_body = {
  chosenPartName = "etki_body",
  decisionMethod = "user",
  -- children: todo vacio excepto lo listado abajo
}
```

### 2. Interior (minimo funcional)
```lua
etki_interior = {
  chosenPartName = "etki_interior",
  children = {
    skin_gauges = { chosenPartName = "etki_gauges_metric_ttsport" },
    skin_interior = { chosenPartName = "etki_skin_interior_sport" },
    -- resto vacio
  }
}
```

### 3. Suspension (solo estructura, sin componentes)
```lua
etki_suspension_F = {
  chosenPartName = "etki_suspension_F",
  children = {
    etki_wheeldata_F = { chosenPartName = "etki_wheeldata_F" },
    wheel_F_5 = {
      chosenPartName = "steelwheel_01a_14x5.5_F_alt",
      children = {
        ["tire_F_14x5.5"] = { chosenPartName = "tire_F_175_65_14_standard" },
        hubcap_F_14 = { chosenPartName = "" }  -- Sin tapacubos
      }
    },
    -- Frenos, struts, steering, swaybar: VACIOS
    etki_brake_F = { chosenPartName = "" },
    etki_strut_F = { chosenPartName = "" },
    etki_steering = { chosenPartName = "" },
    etki_swaybar_F = { chosenPartName = "" },
    etki_differential_F = { chosenPartName = "" }
  }
}

etki_suspension_R = {
  chosenPartName = "etki_suspension_R",
  children = {
    etki_wheeldata_R = { chosenPartName = "etki_wheeldata_R" },
    wheel_R_5 = {
      chosenPartName = "steelwheel_01a_14x5.5_R_alt",
      children = {
        ["tire_R_14x5.5"] = { chosenPartName = "tire_R_175_65_14_standard" },
        hubcap_R_14 = { chosenPartName = "" }
      }
    },
    -- Resto vacio
    etki_brake_R = { chosenPartName = "" },
    etki_coilover_R = { chosenPartName = "" },
    etki_swaybar_R = { chosenPartName = "" },
    etki_differential_R = { chosenPartName = "" }
  }
}
```

### 4. Luces (skin minimo)
```lua
skin_lights = {
  chosenPartName = "etki_skin_lights_alt"
}
```

### 5. Matricula
```lua
licenseplate_design_2_1 = {
  chosenPartName = "license_plate_italy_old_2_1"
}
```

## Piezas que DEBEN ESTAR VACIAS

Todas con `chosenPartName = ""` y `decisionMethod = "user-empty"`:

### Motor y Transmision
- `etki_engine` - SIN MOTOR
- `etki_exhaust` - Sin escape
- `etki_radiator` - Sin radiador
- `etki_oilcooler` - Sin enfriador de aceite
- `etki_fueltank` - Sin deposito de combustible

### Carroceria Exterior
- `etki_hood` - Sin capo
- `etki_trunk` - Sin maletero
- `etki_door_FL/FR/RL/RR` - Sin puertas
- `etki_bumper_F` - Sin parachoques delantero
- `etki_bumper_R` - Sin parachoques trasero
- `etki_fender_L/R` - Sin aletas
- `etki_grille` - Sin rejilla
- `etki_headlight_L/R` - Sin faros
- `etki_taillight` - Sin pilotos
- `etki_backlight` - Sin luz trasera
- `etki_windshield` - Sin parabrisas
- `etki_lip_F` - Sin spoiler delantero
- `etki_sideskirt` - Sin faldones
- `etki_trim` - Sin molduras
- `etki_mudflap_R` - Sin guardabarros

### Interior
- `etki_seat_FL/FR` - Sin asientos delanteros
- `etki_seats_R` - Sin asientos traseros
- `etki_steer` - Sin volante
- `gps` - Sin GPS
- `soundscape_horn` - Sin claxon

### Otros
- `etki_ABS` - Sin ABS
- `etki_rollcage` - Sin jaula
- `etki_strut_bar` - Sin barra de refuerzo
- `etki_skidplate` - Sin proteccion inferior
- `etki_roof_accessory` - Sin accesorios de techo
- `etki_roof_antenna` - Sin antena
- `etki_spoiler_window` - Sin aleron de ventana
- `etki_bumperbar_F` - Sin defensa
- `etki_fenderflare_R` - Sin ensanchadores
- `etki_towhitch` - Sin enganche
- `etki_licenseplate_R` - Sin matricula trasera
- `linelock` - Sin line lock
- `paint_design` - Sin diseno de pintura
- `etki_mod` - Sin mods

## Variables de Configuracion

Valores por defecto para suspension basica:

```lua
vars = {
  ["$arb_spring_F"] = 100000,
  ["$arb_spring_R"] = 30000,
  ["$brakebias"] = 0.76,
  ["$brakestrength"] = 1,
  ["$camber_FR"] = 0.985,
  ["$camber_RR"] = 1.014,
  ["$caster_FR"] = 1.01,
  ["$damp_bump_F"] = 4300,
  ["$damp_bump_R"] = 4000,
  ["$damp_rebound_F"] = 11100,
  ["$damp_rebound_R"] = 9600,
  ["$lsdlockcoef_R"] = 0.15,
  ["$lsdlockcoefrev_R"] = 0.15,
  ["$lsdpreload_R"] = 125,
  ["$revLimiterRPM"] = 7250,
  ["$spring_F"] = 100000,
  ["$spring_R"] = 100000,
  ["$springheight_F"] = -0.02,
  ["$springheight_R"] = -0.02,
  ["$toe_FR"] = 1.002,
  ["$toe_RR"] = 0.999,
  ["$trackoffset_F"] = 0.04,
  ["$trackoffset_R"] = 0.04
}
```

## Piezas Requeridas para Funcionar

El jugador necesita comprar e instalar como MINIMO:

1. **Para arrancar el motor:**
   - Motor (`etki_engine_2.4` o `etki_engine_3.0`)
   - Radiador (`etki_radiator`)
   - Deposito de combustible (`etki_fueltank`)
   - Escape (`etki_exhaust`)

2. **Para poder conducir:**
   - Volante (`etki_steer`)
   - Asiento conductor (`etki_seat_FL`)
   - Frenos delanteros (`etki_brake_F`)
   - Frenos traseros (`etki_brake_R`)

3. **Para ser legal/seguro:**
   - Parabrisas (`etki_windshield`)
   - Faros (`etki_headlight_L/R`)
   - Pilotos (`etki_taillight`)
   - Puertas (opcional pero recomendado)

## Notas de Implementacion

1. El vehiculo spawn con ruedas pero sin motor = no se puede mover
2. El interior basico permite entrar en el coche
3. Los gauges permiten ver el estado cuando se instale motor
4. La suspension existe estructuralmente pero sin amortiguadores funcionara mal
5. Sin frenos = el coche no frena (muy peligroso)

## Archivo de Salida

Crear: `vehicles/etki/mysummer_chassis_bare.pc`

Este archivo debe generarse con la estructura de partsTree documentada arriba, asegurando que todas las piezas listadas como "VACIAS" tengan `chosenPartName = ""`.
