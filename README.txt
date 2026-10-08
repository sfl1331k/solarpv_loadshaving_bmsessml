PV-BATTERY EMS SIMULATION  -  LEVEL 1 AND LEVEL 2
AC grid version (230 V, 50 Hz grid -> AC/DC -> 12 V bus -> inverter -> AC load)
=====================================================================

FILES
  params_ems.m             One parameter file shared by both levels.
                           Every value is tagged GIVEN / CALC / START / KEPT / LEVEL 2.
  level1_energy_balance.m  Level 1: 24 h, 1-minute steps, power and energy only.
  level2_electrical.m      Level 2: 3 s, 5-microsecond steps, real diode bridge
                           and capacitors, average-model converters.

RUN ORDER
  1. Run level2_electrical.m. Its last section prints new loss-model and
     power-factor values for the whole AC/DC converter.
  2. Paste those lines into params_ems.m (section 2). This has already been
     done once with the values from the current circuit.
  3. Run level1_energy_balance.m.
  Results (PNG figures and CSV files) are saved in results_level1 and
  results_level2 next to the scripts.

USING REAL DATA IN LEVEL 1
  Put profile_day.csv in this folder with 1440 rows and the columns
  minute, P_load_ac_W, P_pv_avail_W (household load and PV scaled to the
  prototype). Without that file Level 1 uses a SYNTHETIC TEST PROFILE,
  and every figure says so.

WHERE EACH PIECE OF THEORY IS EXPLAINED (search the files for "THEORY")
  params_ems.m             Loss model P0 + k1*P + k2*P^2; inverse of the loss
                           model; power factor of a bridge rectifier
  level1_energy_balance.m  Bus energy balance; PV half-sine profile; SOC
                           hysteresis; coulomb counting; peak-shaving metrics;
                           battery-sustainable limit
  level2_electrical.m      Forward-Euler integration and time-step choice;
                           diode-bridge conduction; DC-bus signalling (voltage
                           priority); average model of a DC/DC converter;
                           battery Rint model; PI control and anti-windup;
                           100 Hz power pulsation of a single-phase load; RMS,
                           P, Q, S, PF, Fourier fundamental, THD; least-squares
                           fit
