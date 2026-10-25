%% =====================================================================
%  params_ems.m  --  ONE parameter file shared by Level 1 and Level 2
%  Project : Intelligent Solar PV-Battery EMS for Peak Load Shaving
%  Source  : "AC Grid Architecture Change - Simulation Specification"
% ======================================================================
%  HOW TO USE
%    Do not run this file on its own. level1_energy_balance.m and
%    level2_electrical.m both call it first, so a value changed here
%    changes it in both models (roadmap Part Q: "one parameter file
%    shared by both").
%
%  TAGS used on every value (same as the specification document)
%    [GIVEN] fixed by the change request (230 V, 50 Hz, single phase)
%    [CALC]  calculated from other values; the calculation is shown
%    [START] a starting value. Replace it with a simulated or measured
%            value as soon as you have one
%    [KEPT]  carried over unchanged from the team roadmap
%    [LEVEL 2] replaced by a value computed in level2_electrical.m
%
%  ARCHITECTURE MODELLED
%    PV      -> PV DC/DC            -> 12 V DC bus
%    230 V AC grid -> protection/measurement -> AC/DC converter -> DC bus
%    12 V battery <-> bidirectional DC/DC <-> DC bus
%    DC bus  -> DC/AC inverter -> AC filter -> AC load
% ======================================================================

p = struct();


%% ---------------- 1. GRID: 230 V AC utility source -------------------
p.Vgrid_rms = 230;                    % [GIVEN] V RMS, single phase
p.f_grid    = 50;                     % [GIVEN] Hz
p.Vgrid_pk  = p.Vgrid_rms*sqrt(2);    % [CALC]  = 325.3 V peak
p.R_src     = 0.5;                    % [START] ohm, grid source resistance
p.L_src     = 1e-3;                   % [START] H,   grid source inductance

%% ---------------- 2. AC/DC CONVERTER (grid-side converter) -----------
%  Topology: diode bridge -> 68 uF bulk capacitor (~310 V intermediate
%  DC link) -> isolated flyback DC/DC regulated to 12.4 V with a
%  programmable output-current limit I_lim.
p.Vf_diode   = 0.8;      % [START] V, forward drop of each bridge diode
p.C_link     = 68e-6;    % [CALC]  F, 52 uF needed for 290 V minimum at 70.6 W
p.R_inrush   = 10;       % [START] ohm, inrush limiter, bypassed after start-up
p.t_bypass   = 0.15;     % [START] s, time at which the inrush resistor is shorted
p.V_uvlo     = 200;      % [START] V, flyback starts only above this link voltage
p.Vref_grid  = 12.4;     % [KEPT]  V, grid converter output set-point
p.Pdc_max_g  = 60;       % [CALC]  W, = 40 W AC load / 0.85 inverter + margin
p.Imax_g     = p.Pdc_max_g/p.Vref_grid;   % [CALC] = 4.8 A
p.C_out_g    = 1000e-6;  % [START] F, converter output capacitor (lumped into bus)

%  THEORY - why a LOSS MODEL and not a constant efficiency:
%  A converter wastes some power even with no load (control circuit,
%  magnetising current), some power in proportion to load (diode and
%  switch drops) and some in proportion to load squared (I^2*R in
%  wires and windings). So
%        P_in = P_out + P0 + k1*P_out + k2*P_out^2
%  which makes efficiency P_out/P_in LOW at light load and highest near
%  rated load. A constant 0.85 hides this. The three coefficients below
%  are [START] values chosen so that efficiency = 0.85 at 60 W; Level 2
%  output (efficiency at several loads) is used to refit them.
%  Flyback stage ALONE (used inside Level 2, where the bridge diodes and
%  source resistance are modelled separately as real components):
p.fly_P0 = 1.0;  p.fly_k1 = 0.08;  p.fly_k2 = 0.00133;   % [START]
%  Whole AC/DC converter, bridge + flyback (used by Level 1 and by the
%  EMS to convert P_lim into a bus-side cap).
%  Values below are the LEVEL 2 FIT (printed by level2_electrical.m,
%  Step 5). Original [START] values were P0 = 1.0, k1 = 0.08,
%  k2 = 0.00133. Re-run Level 2 and paste again if the circuit changes.
p.acdc_P0 = 1.005;      % [LEVEL 2] W   no-load loss
p.acdc_k1 = 0.0858;     % [LEVEL 2] -   proportional loss
p.acdc_k2 = 0.001413;   % [LEVEL 2] 1/W resistive loss
%  Note: P0 is drawn whenever the converter is plugged in, even at zero
%  output, so the grid never reads exactly 0 W. That is real behaviour.
p.lossACDC = @(Pout) p.acdc_P0 + p.acdc_k1*Pout + p.acdc_k2*Pout.^2;
%  Inverse of the loss model: the largest DC output that keeps AC input
%  at or below Pin. Solves k2*P^2 + (1+k1)*P + (P0 - Pin) = 0 for P
%  (quadratic formula, positive root). Used to turn the AC limit P_lim
%  into the bus-side cap the EMS works with.
p.invACDC  = @(Pin) max(0, (-(1+p.acdc_k1) + sqrt((1+p.acdc_k1)^2 - ...
                     4*p.acdc_k2*(p.acdc_P0 - Pin)))/(2*p.acdc_k2));

%  THEORY - power factor of a diode bridge with a capacitor:
%  The capacitor holds the DC link near the AC peak, so the diodes
%  conduct only for a short time around each voltage peak. The grid
%  current is a narrow pulse, not a sine. Real power P = Vrms*Irms*PF;
%  with narrow pulses Irms is large for the real power delivered, so PF
%  is low (typically 0.5 to 0.65) and falls further at light load,
%  where the pulses become narrower still. Level 1 uses this [START]
%  curve; Level 2 computes PF directly from waveforms and prints values
%  to paste back here.
%  Table below is from LEVEL 2 (Step 5). The [START] guess was 0.40 to
%  0.60; the simulated bridge gives about 0.31 to 0.41, because the
%  current pulses are very narrow (THD above 200 %). Outside the table
%  the end values are held.
p.PF_table_P  = [3.2   15.1  27.7  41.1  55.2];    % AC input power, W
p.PF_table_pf = [0.308 0.364 0.386 0.399 0.408];  % [LEVEL 2] power factor
p.PFgrid = @(Pac) interp1(p.PF_table_P, p.PF_table_pf, ...
           min(max(Pac,p.PF_table_P(1)),p.PF_table_P(end)), 'linear');

%% ---------------- 3. PV SOURCE AND PV DC/DC --------------------------
p.Ppv_rated  = 20;       % [KEPT]  W, PV panel rating
p.Vref_pv    = 12.6;     % [KEPT]  V, PV converter set-point (highest -> used first)
p.eta_pv     = 0.90;     % [START] PV buck efficiency

%% ---------------- 4. BATTERY AND BIDIRECTIONAL DC/DC -----------------
p.Vbat_nom   = 12;       % [KEPT]  V
p.Cbat_Ah    = 7;        % [KEPT]  Ah (12 V 7 Ah VRLA)
p.Ebat_Wh    = p.Vbat_nom*p.Cbat_Ah;   % [CALC] = 84 Wh
p.SOC_min    = 0.40;     % [KEPT]  roadmap rule set
p.SOC_max    = 0.90;     % [KEPT]
p.SOC_hyst   = 0.03;     % [KEPT]  3 % hysteresis
p.SOC0       = 0.90;     % [START] SOC at the start of a run: battery full at
                         %         SOC_max, as after a sunny previous day
p.R0_bat     = 0.025;    % [START] ohm, internal resistance (check datasheet)
%  Open-circuit voltage against SOC: [START] straight line between
%  typical rested VRLA values. Replace with the manufacturer's table.
p.OCV        = @(soc) 11.8 + (12.85-11.8)*soc;
p.Vref_dis   = 12.0;     % [KEPT]  V, discharger (LTC3780) set-point - lowest
p.Idis_max   = 2.5;      % [KEPT]  A, discharger output current limit
p.eta_dis    = 0.92;     % [START] discharge path efficiency
p.Pchg_max   = 14.4*1.4; % [KEPT]  W, charger CV 14.4 V, CC 1.4 A = 20.2 W
p.eta_chg    = 0.90;     % [START] charge path efficiency
p.eta_coul   = 0.95;     % [START] coulombic (charge) efficiency of VRLA

%% ---------------- 5. DC BUS ------------------------------------------
p.C_bus      = 22000e-6; % [CALC/START] F, from the 100 Hz ripple calculation

%% ---------------- 6. INVERTER, AC FILTER, AC LOAD --------------------
p.Vload_rms  = 230;      % [GIVEN] inverter output voltage
p.P_step     = 10;       % [KEPT]  W per load step, 4 steps -> 40 W
p.R_step     = p.Vload_rms^2/p.P_step;   % [CALC] = 5290 ohm per step
%  Inverter loss model, same form as the AC/DC converter, written on
%  the inverter OUTPUT power. [START] values give eta = 0.85 at 40 W.
p.inv_P0 = 2.0;  p.inv_k1 = 0.06;  p.inv_k2 = 0.00166;
%  P0 here is the inverter's no-load loss: drawn even with every load off.
p.lossINV = @(Pac) p.inv_P0 + p.inv_k1*Pac + p.inv_k2*Pac.^2;

%% ---------------- 7. EMS ---------------------------------------------
p.P_lim      = 20;       % [START] W of AC power drawn from the grid. Level 2
                         %         uses it directly; Level 1 also finds the
                         %         lowest limit the battery can hold all day
p.T_ems      = 1;        % [KEPT]  s, EMS decision period (Level 1 step is 1 min)
%  Mode codes used in both levels
p.IDLE = 0; p.CHARGE = 1; p.DISCHARGE = 2;
