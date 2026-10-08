%% =====================================================================
%  level1_energy_balance.m  --  LEVEL 1 SIMULATION (energy balance)
%  Project : Intelligent Solar PV-Battery EMS for Peak Load Shaving
%  Grid    : 230 V, 50 Hz, single-phase AC  ->  AC/DC converter -> 12 V bus
%  Load    : 12 V bus -> DC/AC inverter -> 230 V AC load
% ======================================================================
%  WHAT LEVEL 1 IS
%    A whole day (24 h) simulated in 1-minute steps using POWER and
%    ENERGY only. No waveforms, no switching. It answers the project's
%    main question: how much does the EMS lower the peak AC power drawn
%    from the grid, and does the battery last through the peak?
%
%  WHAT IS REAL AND WHAT IS NOT
%    - Both converters are LOSS MODELS (P0 + k1*P + k2*P^2), not gains.
%    - Grid power factor comes from a PF-versus-power curve, so the grid
%      CURRENT is calculated, not assumed.
%    - The load and PV profiles below are a SYNTHETIC TEST PROFILE.
%      Replace them with scaled real data (CEEW load, PVWatts PV) by
%      putting a file named profile_day.csv next to this script with
%      columns: minute, P_load_ac_W, P_pv_avail_W  (1440 rows).
%
%  HOW TO RUN
%    Put params_ems.m in the same folder and press Run. Figures and a
%    results CSV are saved in the sub-folder results_level1.
%
%  STEPS IN THIS FILE
%    Step 1  Load parameters
%    Step 2  Build the 24 h load and PV profiles
%    Step 3  Run the BASELINE (battery disabled)
%    Step 4  Sweep P_lim to find the lowest limit the battery can hold
%    Step 5  Run the EMS with that limit, and with the 20 W starting limit
%    Step 6  Compute peak-shaving metrics
%    Step 7  Plot and save
%    Local function simulate_day() holds the energy balance and EMS rule
% ======================================================================

clear; clc; close all;

%% ---------------- Step 1: load parameters ----------------------------
params_ems;                       % creates struct p (shared with Level 2)
dt_min = 1;                       % time step, minutes
dt_h   = dt_min/60;               % same step in hours (energy = P*dt_h, Wh)
N      = 24*60/dt_min;            % 1440 steps in one day
t_h    = (0:N-1)'*dt_h;           % time axis in hours

outdir = fullfile(pwd,'results_level1');
if ~exist(outdir,'dir'), mkdir(outdir); end

%% ---------------- Step 2: build the 24 h profiles --------------------
if isfile('profile_day.csv')
    % 2a. Real data path: scaled household load and PV, one row per minute
    T = readtable('profile_day.csv');
    P_load_ac  = T.P_load_ac_W(:);
    P_pv_avail = T.P_pv_avail_W(:);
    profile_name = 'profile_day.csv (scaled real data)';
else
    % 2b. SYNTHETIC TEST PROFILE (label every graph made from it as such)
    %     AC load, watts, shaped like an Indian household day scaled to
    %     the 40 W prototype: low night, morning peak, flat day, long
    %     evening peak.
    h = t_h;
    P_load_ac = 6*ones(N,1);                        % night base load
    P_load_ac(h>=6   & h<8)   = 18;                 % morning peak
    P_load_ac(h>=8   & h<17)  = 10;                 % daytime
    P_load_ac(h>=17  & h<18.5)= 18;                 % evening build-up
    P_load_ac(h>=18.5& h<22)  = 28;                 % evening peak
    P_load_ac(h>=19.5& h<21)  = 36;                 % top of evening peak
    P_load_ac(h>=22)          = 10;                 % late evening
    rng(1);                                         % repeatable "noise"
    P_load_ac = max(0, P_load_ac + 1.0*randn(N,1)); % +/- 1 W fluctuation

    %     PV available AT THE PANEL: half-sine from 06:30 to 18:30.
    %     THEORY: on a clear day irradiance follows roughly a sine of the
    %     sun's elevation, so panel power ~ Prated*sin(pi*(t-sunrise)/daylength).
    %     0.85 is a derating for heat, dust and no MPPT [START].
    sunrise = 6.5; daylen = 12;
    P_pv_avail = 0.85*p.Ppv_rated*max(0, sin(pi*(h-sunrise)/daylen));
    profile_name = 'SYNTHETIC TEST PROFILE';
end

%% ---------------- Step 3: BASELINE run (battery disabled) ------------
%  The baseline answers "what would the grid supply without the EMS?"
%  Same profiles, same converters, but the battery never charges or
%  discharges. The difference between the baseline and the EMS run is
%  the proof that the EMS works.
base = simulate_day(p, P_load_ac, P_pv_avail, dt_h, p.P_lim, false);

%% ---------------- Step 4: P_lim sweep (choose the limit) -------------
%  THEORY - the "battery-sustainable limit":
%  A lower P_lim shaves more, but the battery must supply everything
%  above it. If the energy above the limit during the peak is larger
%  than the usable battery energy (SOC_max - SOC_min) x 84 Wh = 42 Wh,
%  the battery reaches SOC_min part-way through the peak, the EMS must
%  release the limit, and the grid takes the full load again: the day's
%  peak is then NOT reduced at all. So the limit is a design choice:
%  the lowest P_lim the battery can hold for the whole day.
%  (The ML forecast in the ML roadmap is a way to pick this every day.)
Plim_list = 10:1:50;
peak_sw = zeros(size(Plim_list)); viol_sw = peak_sw;
for i = 1:numel(Plim_list)
    r = simulate_day(p, P_load_ac, P_pv_avail, dt_h, Plim_list(i), true);
    peak_sw(i) = max(r.P_grid_ac);
    viol_sw(i) = sum(r.P_grid_ac > Plim_list(i)+0.5)*dt_min;
end
ok = find(viol_sw==0, 1, 'first');
if isempty(ok)
    P_lim_day = p.P_lim;
    fprintf('No P_lim in the sweep was held all day; using p.P_lim.\n');
else
    P_lim_day = Plim_list(ok);
end

%% ---------------- Step 5: EMS runs -----------------------------------
%  5a. EMS with the sustainable limit from Step 4 (the design case)
ems  = simulate_day(p, P_load_ac, P_pv_avail, dt_h, P_lim_day, true);
%  5b. EMS with the specification's starting limit p.P_lim, to show what
%      happens when the limit is set lower than the battery can hold
ems0 = simulate_day(p, P_load_ac, P_pv_avail, dt_h, p.P_lim, true);

%% ---------------- Step 6: peak-shaving metrics -----------------------
%  THEORY - the metrics (roadmap Part I), all on P_grid,AC:
%    Peak demand         = max of grid AC power over the day
%    Peak reduction (%)  = (peak_base - peak_ems)/peak_base * 100
%    Load factor         = mean / peak. Closer to 1 = flatter demand,
%                          which is what a utility wants
%    Minutes above limit = how long the EMS failed to hold its P_lim
%    Battery throughput  = energy that went out of the battery (Wh)
tol = 0.5;   % W, a reading this close to P_lim counts as "at the limit"
mrow = @(x, Pl) [max(x.P_grid_ac); max(x.I_grid); sum(x.P_grid_ac)*dt_h; ...
    mean(x.P_grid_ac)/max(x.P_grid_ac); sum(x.P_grid_ac > Pl+tol)*dt_min; ...
    sum(x.P_bat_dis_int)*dt_h; sum(x.P_curt)*dt_h; 100*min(x.SOC); 100*x.SOC(end)];
M = table();
M.Metric = {'Peak grid AC power (W)'; 'Peak grid current (A RMS)'; ...
    'Grid energy over the day (Wh)'; 'Load factor (mean/peak)'; ...
    'Minutes above its P_lim'; 'Battery energy discharged (Wh)'; ...
    'PV energy curtailed (Wh)'; 'Lowest SOC (%)'; 'Final SOC (%)'};
M.Baseline = mrow(base, Inf);
M.EMS_sustainable_limit = mrow(ems, P_lim_day);
M.EMS_starting_limit = mrow(ems0, p.P_lim);
peak_red  = 100*(max(base.P_grid_ac)-max(ems.P_grid_ac))/max(base.P_grid_ac);
peak_red0 = 100*(max(base.P_grid_ac)-max(ems0.P_grid_ac))/max(base.P_grid_ac);

fprintf('\n===== LEVEL 1 RESULTS  (%s) =====\n', profile_name);
fprintf('Sustainable limit from the sweep: P_lim = %d W AC (bus-side cap %.2f W DC)\n', ...
    P_lim_day, p.invACDC(P_lim_day));
disp(M);
fprintf('Peak reduction with P_lim = %d W: %.1f %%\n', P_lim_day, peak_red);
fprintf('Peak reduction with P_lim = %d W: %.1f %%  (battery runs out)\n', round(p.P_lim), peak_red0);

%% ---------------- Step 7: plots and saved results --------------------
lbl = sprintf('Level 1, %s', profile_name);

% Figure 1 - the "money plot": grid AC power with and without the EMS
f1 = figure('Name','Grid AC power','Color','w');
plot(t_h, base.P_grid_ac, 'Color',[0.6 0.6 0.6], 'LineWidth',1.2); hold on;
plot(t_h, ems.P_grid_ac, 'b', 'LineWidth',1.5);
plot(t_h, ems0.P_grid_ac, 'm--', 'LineWidth',1);
yline(P_lim_day,'r--',sprintf('P_{lim} = %d W',P_lim_day),'LineWidth',1.2);
plot(t_h, P_load_ac, 'k:', 'LineWidth',1);
xlabel('Time of day (h)'); ylabel('Power (W)'); xlim([0 24]); grid on;
legend('Without EMS',sprintf('With EMS, P_{lim} = %d W',P_lim_day), ...
    sprintf('With EMS, P_{lim} = %d W (too low)',round(p.P_lim)),'','P_{AC,load}','Location','northwest');
title({'Grid AC power: with and without EMS', lbl});

% Figure 2 - where the bus power comes from (EMS run)
f2 = figure('Name','DC bus sources','Color','w');
area(t_h, [ems.P_pv_used, ems.P_grid_dc, ems.P_bat_bus_dis], 'LineStyle','none'); hold on;
plot(t_h, ems.P_dc_inv, 'k', 'LineWidth',1.2);
xlabel('Time of day (h)'); ylabel('Power on the DC bus (W)'); xlim([0 24]); grid on;
legend('PV','Grid (after AC/DC)','Battery','Inverter DC input (demand)','Location','northwest');
title({'Sources supplying the DC bus (EMS run)', lbl});

% Figure 3 - SOC and EMS mode
f3 = figure('Name','SOC and mode','Color','w');
subplot(2,1,1); plot(t_h, 100*ems.SOC,'LineWidth',1.5); hold on;
yline(100*p.SOC_min,'r--','SOC_{min}'); yline(100*p.SOC_max,'g--','SOC_{max}');
ylabel('SOC (%)'); xlim([0 24]); grid on; title({'Battery state of charge', lbl});
subplot(2,1,2); stairs(t_h, ems.mode,'LineWidth',1.2);
yticks([0 1 2]); yticklabels({'IDLE','CHARGE','DISCHARGE'}); ylim([-0.3 2.3]);
xlabel('Time of day (h)'); xlim([0 24]); grid on; title('EMS mode');

% Figure 4 - grid current and power factor (the cost of a diode bridge)
f4 = figure('Name','Grid current and PF','Color','w');
yyaxis left;  plot(t_h, base.I_grid,'Color',[0.6 0.6 0.6]); hold on; plot(t_h, ems.I_grid,'b-');
ylabel('Grid current (A RMS)');
yyaxis right; plot(t_h, ems.PF,'LineWidth',1.2); ylabel('Power factor'); ylim([0 1]);
xlabel('Time of day (h)'); xlim([0 24]); grid on;
legend('I_{grid} without EMS','I_{grid} with EMS','PF with EMS','Location','northwest');
title({'Grid current calculated from P, PF and V', lbl});

% Figure 5 - P_lim sweep
f5 = figure('Name','P_lim sweep','Color','w');
yyaxis left;  plot(Plim_list, peak_sw,'o-'); ylabel('Peak grid AC power (W)');
yyaxis right; plot(Plim_list, viol_sw,'s-'); ylabel('Minutes above P_{lim}');
xline(P_lim_day,'k--','chosen'); xlabel('P_{lim} (W AC)'); grid on;
title({'Lower limit shaves more until the battery runs out', lbl});

% Figure 6 - load-duration curve
f6 = figure('Name','Load-duration curve','Color','w');
plot((1:N)/N*100, sort(base.P_grid_ac,'descend'),'Color',[0.6 0.6 0.6],'LineWidth',1.2); hold on;
plot((1:N)/N*100, sort(ems.P_grid_ac,'descend'),'b','LineWidth',1.5);
xlabel('Share of the day (%)'); ylabel('Grid AC power (W)'); grid on;
legend('Without EMS','With EMS'); title({'Grid load-duration curve', lbl});

figs = {f1,f2,f3,f4,f5,f6};
names = {'L1_fig1_grid_power','L1_fig2_bus_sources','L1_fig3_soc_mode', ...
         'L1_fig4_grid_current_pf','L1_fig5_plim_sweep','L1_fig6_load_duration'};
for i = 1:numel(figs)
    % Light theme for printing (newer MATLAB defaults to dark; older ignores this)
    try, theme(figs{i},'light'); catch, end
    exportgraphics(figs{i}, fullfile(outdir,[names{i} '.png']), 'Resolution',150);
end
R = table(t_h, P_load_ac, P_pv_avail, base.P_grid_ac, ems.P_grid_ac, ems.P_grid_dc, ...
    ems.I_grid, ems.PF, ems.P_bat_bus_dis, ems.P_chg_in, ems.SOC, ems.mode, ...
    'VariableNames',{'t_h','P_load_ac','P_pv_avail','P_grid_ac_base','P_grid_ac_ems', ...
    'P_grid_dc_ems','I_grid_ems','PF_ems','P_bat_dis_bus','P_charge_in','SOC','mode'});
writetable(R, fullfile(outdir,'level1_results.csv'));
writetable(M, fullfile(outdir,'level1_metrics.csv'));
fprintf('Saved figures and CSV files in %s\n', outdir);


%% =====================================================================
%  LOCAL FUNCTION: one simulated day
% ======================================================================
function r = simulate_day(p, P_load_ac, P_pv_avail, dt_h, P_lim, use_batt)
% Runs the energy balance and the EMS rule for every minute of the day.
%
% THEORY - the energy balance on the DC bus (power in = power out):
%     P_pv_used + P_grid,DC + P_bat = P_DC,inv
% with
%     P_DC,inv  = P_AC,load + loss_inv(P_AC,load)      (inverter input)
%     P_grid,AC = P_grid,DC + loss_ACDC(P_grid,DC)     (what the grid supplies)
%     I_grid    = P_grid,AC / (V_grid * PF)            (single-phase AC)
% The EMS chooses P_bat; the bus equation then fixes P_grid,DC.

N = numel(P_load_ac);
r.P_grid_ac = zeros(N,1); r.P_grid_dc = zeros(N,1); r.I_grid = zeros(N,1);
r.PF = zeros(N,1); r.P_dc_inv = zeros(N,1); r.P_pv_used = zeros(N,1);
r.P_bat_bus_dis = zeros(N,1); r.P_bat_dis_int = zeros(N,1);
r.P_chg_in = zeros(N,1); r.P_curt = zeros(N,1);
r.SOC = zeros(N,1); r.mode = zeros(N,1);

soc = p.SOC0;
dis_ok = soc > p.SOC_min;      % hysteresis flags (see Step D below)
chg_ok = soc < p.SOC_max;
cap = p.invACDC(P_lim);        % bus-side equivalent of the AC limit (W DC)

for k = 1:N
    % --- Step A: demand on the bus from the inverter -----------------
    P_dcinv = P_load_ac(k) + p.lossINV(P_load_ac(k));

    % --- Step B: PV available on the bus ----------------------------
    %     The PV converter has the highest set-point (12.6 V), so PV is
    %     always used first (DC-bus signalling).
    P_pv_bus = p.eta_pv * P_pv_avail(k);
    P_pv_used = min(P_pv_bus, P_dcinv);
    surplus_bus = P_pv_bus - P_pv_used;          % PV the load cannot use

    % --- Step C: net demand left for grid and battery ---------------
    P_net = P_dcinv - P_pv_bus;                  % roadmap: P_net = P_load - P_pv

    % --- Step D: SOC hysteresis -------------------------------------
    %  THEORY - hysteresis: with a single threshold, SOC hovering at 40 %
    %  would flip the relay every step (chatter). Two thresholds fix it:
    %  discharge stops at SOC_min and may restart only above
    %  SOC_min + 3 %; charging stops at SOC_max and restarts only below
    %  SOC_max - 3 %.
    if soc <= p.SOC_min,               dis_ok = false; end
    if soc >= p.SOC_min + p.SOC_hyst,  dis_ok = true;  end
    if soc >= p.SOC_max,               chg_ok = false; end
    if soc <= p.SOC_max - p.SOC_hyst,  chg_ok = true;  end

    % --- Step E: the EMS rule (roadmap Part E, AC-limit version) -----
    P_bat_bus = 0; P_chg_in = 0; mode = p.IDLE;
    if use_batt && P_net > cap && dis_ok
        mode = p.DISCHARGE;
        P_bat_bus = min(P_net - cap, p.Vref_dis*p.Idis_max);   % discharger limit
    elseif use_batt && P_net < 0 && chg_ok
        mode = p.CHARGE;
        % The charger takes PV power directly from the panel side; the
        % bus-side surplus is converted back to panel watts with eta_pv.
        P_chg_in = min(surplus_bus/p.eta_pv, p.Pchg_max/p.eta_chg);
        surplus_bus = surplus_bus - P_chg_in*p.eta_pv;
    end

    % --- Step F: grid supplies whatever is left (no export) ----------
    P_grid_dc = max(P_net - P_bat_bus, 0);
    P_grid_ac = P_grid_dc + p.lossACDC(P_grid_dc);
    pf = p.PFgrid(P_grid_ac);
    I_grid = P_grid_ac/(p.Vgrid_rms*pf);

    % --- Step G: update SOC (energy counting) -----------------------
    %  THEORY - coulomb counting: SOC changes by the charge moved divided
    %  by capacity. At Level 1 we count energy at nominal voltage, which
    %  is the same thing scaled by 12 V:  dSOC = -E_out/E_bat + E_in/E_bat.
    %  Discharge draws P_bat_bus/eta_dis from the cells; charging stores
    %  P_chg_in*eta_chg*eta_coul.
    P_dis_int = P_bat_bus/p.eta_dis;
    soc = soc - P_dis_int*dt_h/p.Ebat_Wh + P_chg_in*p.eta_chg*p.eta_coul*dt_h/p.Ebat_Wh;
    soc = min(max(soc,0),1);

    % --- Step H: log ------------------------------------------------
    r.P_grid_ac(k)=P_grid_ac; r.P_grid_dc(k)=P_grid_dc; r.I_grid(k)=I_grid; r.PF(k)=pf;
    r.P_dc_inv(k)=P_dcinv; r.P_pv_used(k)=P_pv_used; r.P_bat_bus_dis(k)=P_bat_bus;
    r.P_bat_dis_int(k)=P_dis_int; r.P_chg_in(k)=P_chg_in; r.P_curt(k)=max(surplus_bus,0)/p.eta_pv;
    r.SOC(k)=soc; r.mode(k)=mode;
end
end
