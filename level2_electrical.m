%% =====================================================================
%  level2_electrical.m  --  LEVEL 2 SIMULATION (electrical, time domain)
%  Project : Intelligent Solar PV-Battery EMS for Peak Load Shaving
% ======================================================================
%  WHAT LEVEL 2 IS
%    A 3-second time-domain simulation with a 5-microsecond step. The
%    grid-side diode bridge and DC-link capacitor are modelled as REAL
%    components, so the grid current waveform, its RMS value, real and
%    reactive power and power factor are COMPUTED from waveforms, not
%    assumed. The flyback DC/DC, PV converter, battery converter and
%    inverter are AVERAGE models: they move the right power with the
%    right control behaviour, but their 20-65 kHz switching is not
%    simulated (that is Level 3).
%
%  WHY A SCRIPT AND NOT SIMSCAPE BLOCKS
%    Every equation is visible and commented, so the team can explain
%    each line in the viva. The same circuit can later be drawn in
%    Simscape Electrical using the block list in the specification,
%    section 7, and its results compared with this script.
%
%  SCENARIO (what happens during the 3 s)
%    0.00 s  Grid switched on. Inrush resistor limits the capacitor charge
%    0.15 s  Inrush resistor bypassed
%    0.00 s  AC load = 2 steps (20 W). PV gives 10 W. Battery off
%    0.80 s  AC load steps to 4 steps (40 W): the "peak"
%    1.50 s  EMS switched on: it must hold P_grid,AC at P_lim = 20 W
%    3.00 s  End
%    Before 1.5 s the system behaves as the BASELINE (no battery);
%    after 1.5 s it behaves as the EMS case. Compare the two halves.
%
%  STEPS IN THIS FILE
%    Step 1  Parameters and scenario
%    Step 2  Run the main scenario            (local function run_level2)
%    Step 3  Print per-cycle grid measurements before and after the EMS
%    Step 4  Plot waveforms and per-cycle quantities
%    Step 5  Characterisation sweep: PF and efficiency of the grid
%            converter at several loads, and a least-squares fit of the
%            loss model to paste back into params_ems.m for Level 1
%
%  Run time: about 10-40 s on a laptop (the sweep is most of it).
% ======================================================================

clear; clc; close all;

%% ---------------- Step 1: parameters and scenario --------------------
params_ems;                         % shared parameters, struct p
outdir = fullfile(pwd,'results_level2');
if ~exist(outdir,'dir'), mkdir(outdir); end

sc = struct();
sc.dt        = 5e-6;   % s. THEORY: the time step must be much shorter than
                       % the fastest thing we resolve. The diode conduction
                       % pulse lasts about 1-2 ms and L/R = 2 ms, so 5 us
                       % gives several hundred points per pulse.
sc.t_end     = 3.0;    % s
sc.t_step    = 0.8;    % s, load step time
sc.n_before  = 2;      % load steps (x10 W) before t_step
sc.n_after   = 4;      % load steps after t_step
sc.P_pv      = 10;     % W available at the PV panel (constant here)
sc.t_ems_on  = 1.5;    % s, EMS enabled from this time
sc.T_ems     = 0.1;    % s, EMS period. THEORY: the real EMS runs every
                       % 1 s. A 3 s window would then contain only one
                       % decision, so the period is shortened to 0.1 s.
                       % The rule is identical; only its clock is faster.
sc.batt_on   = true;   % battery stage available to the EMS
sc.log_every = 4;      % keep every 4th sample for plots (20 us)

%% ---------------- Step 2: run the main scenario ----------------------
tic; r = run_level2(p, sc); fprintf('Main run: %.1f s of computing\n', toc);

%% ---------------- Step 3: per-cycle measurements ---------------------
%  Average the last 10 cycles (0.2 s) before the EMS starts and the last
%  10 cycles of the run, so start-up and transients are excluded.
c = r.cyc;
iB = find(c.t_end > sc.t_ems_on-0.2 & c.t_end <= sc.t_ems_on);   % baseline
iE = find(c.t_end > sc.t_end-0.2);                                % with EMS
show = @(name,v) fprintf('%-34s %10.3f %10.3f\n', name, mean(v(iB)), mean(v(iE)));
fprintf('\n===== LEVEL 2: GRID MEASUREMENTS (mean of 10 cycles) =====\n');
fprintf('%-34s %10s %10s\n','Quantity','Baseline','With EMS');
show('1  Grid RMS voltage (V)',          c.Vrms);
show('2  Grid RMS current (A)',          c.Irms);
show('3  Grid frequency (Hz)',           c.f);
show('4  Grid real power P (W)',         c.P);
show('5a Grid reactive power Q1 (var)',  c.Q1);
show('5b Non-active power N (var)',      c.N);
show('6  Apparent power S (VA)',         c.S);
show('7  Power factor P/S',              c.PF);
show('8  Converter input power (W)',     c.Pconv_in);
show('9  Converter output power (W)',    c.Pconv_out);
show('10 Converter efficiency',          c.eta);
show('   Current THD (%)',               100*c.THD);
show('   DC bus voltage (V)',            c.Vbus);
show('   Battery power to bus (W)',      c.Pbat);
fprintf('P_lim = %.1f W.  Check: with EMS, row 4 should sit at P_lim.\n', p.P_lim);

%% ---------------- Step 4: plots --------------------------------------
L = r.log; tt = L.t;
lbl = 'Level 2, scenario: 20 W -> 40 W load step, EMS on at 1.5 s';

% Figure 1 - grid voltage and current, 3 cycles before and after the EMS
f1 = figure('Name','Grid waveforms','Color','w');
w1 = tt>=1.40 & tt<1.46;  w2 = tt>=2.90 & tt<2.96;
subplot(2,1,1);
yyaxis left;  plot(tt(w1)*1e3, L.vs(w1)); ylabel('v_{grid} (V)'); ylim([-400 400]);
yyaxis right; plot(tt(w1)*1e3, L.iac(w1),'LineWidth',1.2); ylabel('i_{grid} (A)');
grid on; xlabel('Time (ms)'); title({'Baseline: grid current flows in short pulses at the voltage peaks', lbl});
subplot(2,1,2);
yyaxis left;  plot(tt(w2)*1e3, L.vs(w2)); ylabel('v_{grid} (V)'); ylim([-400 400]);
yyaxis right; plot(tt(w2)*1e3, L.iac(w2),'LineWidth',1.2); ylabel('i_{grid} (A)');
grid on; xlabel('Time (ms)'); title('With EMS: smaller pulses, same shape');

% Figure 2 - per-cycle grid AC power against the limit (the key result)
f2 = figure('Name','Grid AC power per cycle','Color','w');
plot(c.t_end, c.P,'b.-'); hold on;
yline(p.P_lim,'r--','P_{lim}'); xline(sc.t_step,'k:','load step'); xline(sc.t_ems_on,'k--','EMS on');
xlabel('Time (s)'); ylabel('P_{grid,AC} (W), one value per 20 ms cycle'); grid on; ylim([0 60]);
title({'Real power drawn from the 230 V grid', lbl});

% Figure 3 - RMS current and power factor per cycle
f3 = figure('Name','Grid current and PF','Color','w');
yyaxis left;  plot(c.t_end, c.Irms,'.-'); ylabel('I_{grid,RMS} (A)');
yyaxis right; plot(c.t_end, c.PF,'.-'); ylabel('Power factor'); ylim([0 1]);
xline(sc.t_step,'k:'); xline(sc.t_ems_on,'k--'); xlabel('Time (s)'); grid on;
title({'Grid current and power factor from the waveforms', lbl});

% Figure 4 - DC link (intermediate DC) and DC bus voltages
f4 = figure('Name','DC voltages','Color','w');
subplot(2,1,1); plot(tt, L.vlink); ylabel('v_{link} (V)'); grid on;
title({'Intermediate DC link after the bridge (about 310 V)', lbl});
subplot(2,1,2); plot(tt, L.vbus); ylabel('v_{bus} (V)'); xlabel('Time (s)'); grid on; ylim([11.4 13]);
yline(p.Vref_pv,':','12.6 PV'); yline(p.Vref_grid,':','12.4 grid'); yline(p.Vref_dis,':','12.0 battery');
title('12 V DC bus: the set-point that wins shows which source is in charge');

% Figure 5 - currents into the bus from each source
f5 = figure('Name','Bus currents','Color','w');
plot(tt, L.ipv, tt, L.ig, tt, L.idis, tt, L.iinv); grid on;
legend('PV converter','Grid converter (AC/DC)','Battery discharger','Inverter draw','Location','northwest');
xlabel('Time (s)'); ylabel('Current on the 12 V bus (A)');
title({'Who supplies the bus (inverter draw ripples at 100 Hz)', lbl});

% Figure 6 - 100 Hz ripple on the bus (zoom)
f6 = figure('Name','Bus ripple','Color','w');
w3 = tt>=2.90 & tt<2.96;
yyaxis left;  plot(tt(w3)*1e3, L.vbus(w3)); ylabel('v_{bus} (V)');
yyaxis right; plot(tt(w3)*1e3, L.iinv(w3)); ylabel('i_{inverter} (A)');
xlabel('Time (ms)'); grid on;
title({'Single-phase inverter draws power at twice line frequency (100 Hz)', lbl});

% Figure 7 - inverter output to the AC load
f7 = figure('Name','AC load','Color','w');
w4 = tt>=2.90 & tt<2.94;
yyaxis left;  plot(tt(w4)*1e3, L.vload(w4)); ylabel('v_{load} (V)');
yyaxis right; plot(tt(w4)*1e3, L.iload(w4)); ylabel('i_{load} (A)');
xlabel('Time (ms)'); grid on; title({'Inverter output: 230 V, 50 Hz, resistive AC load', lbl});

% Figure 8 - battery
f8 = figure('Name','Battery','Color','w');
subplot(2,1,1); plot(tt, L.ibat); ylabel('i_{bat} (A, + = discharge)'); grid on;
title({'Battery current and EMS mode', lbl});
subplot(2,1,2); stairs(tt, L.mode); yticks([0 1 2]); yticklabels({'IDLE','CHARGE','DISCHARGE'});
ylim([-0.3 2.3]); xlabel('Time (s)'); grid on;

figs = {f1,f2,f3,f4,f5,f6,f7,f8};
names = {'L2_fig1_grid_waveforms','L2_fig2_grid_power','L2_fig3_current_pf', ...
    'L2_fig4_dc_voltages','L2_fig5_bus_currents','L2_fig6_bus_ripple', ...
    'L2_fig7_ac_load','L2_fig8_battery'};
for i = 1:numel(figs)
    % Light theme for printing (newer MATLAB defaults to dark; older ignores this)
    try, theme(figs{i},'light'); catch, end
    exportgraphics(figs{i}, fullfile(outdir,[names{i} '.png']), 'Resolution',150);
end
writetable(struct2table(c), fullfile(outdir,'level2_per_cycle.csv'));

%% ---------------- Step 5: characterisation sweep ---------------------
%  Purpose: replace Level 1's [START] values with values computed here.
%  The grid converter alone supplies the bus (no PV, no battery) at
%  several AC loads. At steady state we read its power factor and its
%  input and output power, then fit P_in - P_out = P0 + k1*P + k2*P^2.
%
%  THEORY - least-squares fit: with several (P_out, P_loss) points, the
%  three unknowns P0, k1, k2 are chosen to minimise the sum of squared
%  errors. In MATLAB this is one line: coefficients = A \ P_loss, where
%  each row of A is [1, P_out, P_out^2].
fprintf('\n===== LEVEL 2: GRID CONVERTER CHARACTERISATION =====\n');
sw = sc; sw.t_end = 0.6; sw.t_step = 99; sw.P_pv = 0; sw.batt_on = false;
sw.t_ems_on = 99; sw.log_every = 1000;
steps = [0 1 2 3 4];               % AC load steps of 10 W
Pin = zeros(size(steps)); Pout = Pin; PFs = Pin; Pac = Pin; Ir = Pin;
for i = 1:numel(steps)
    sw.n_before = steps(i);
    rs = run_level2(p, sw);
    k = rs.cyc.t_end > sw.t_end - 0.2;          % last 10 cycles
    Pac(i)  = mean(rs.cyc.P(k));
    Pin(i)  = mean(rs.cyc.Pconv_in(k));
    Pout(i) = mean(rs.cyc.Pconv_out(k));
    PFs(i)  = mean(rs.cyc.PF(k));
    Ir(i)   = mean(rs.cyc.Irms(k));
    fprintf('AC load %2d W: P_grid,AC %6.2f W  I %5.3f A  PF %5.3f  eta %5.3f\n', ...
        10*steps(i), Pac(i), Ir(i), PFs(i), Pout(i)/Pac(i));
end
%  Overall AC->DC loss includes the bridge diodes and source resistance,
%  so fit it against P_grid,AC (what Level 1 needs).
A = [ones(numel(Pout),1), Pout(:), Pout(:).^2];
coef = A \ (Pac(:) - Pout(:));
fprintf('\nPaste into params_ems.m to update Level 1:\n');
fprintf('p.acdc_P0 = %.3f;  p.acdc_k1 = %.4f;  p.acdc_k2 = %.6f;\n', coef);
fprintf('p.PF_table_P  = [%s];\n', sprintf('%.1f ', Pac));
fprintf('p.PF_table_pf = [%s];\n', sprintf('%.3f ', PFs));

f9 = figure('Name','Characterisation','Color','w');
subplot(1,2,1); plot(Pac, PFs,'o-'); xlabel('P_{grid,AC} (W)'); ylabel('Power factor'); grid on;
title('PF of the bridge rectifier vs load');
subplot(1,2,2); plot(Pout, Pout./Pac,'o-'); xlabel('DC output (W)'); ylabel('\eta_{AC/DC}'); grid on;
title('AC/DC efficiency vs load');
try, theme(f9,'light'); catch, end
exportgraphics(f9, fullfile(outdir,'L2_fig9_characterisation.png'),'Resolution',150);
fprintf('Saved figures and CSV in %s\n', outdir);


%% =====================================================================
%  LOCAL FUNCTION: the time-domain model
% ======================================================================
function r = run_level2(p, sc)
% ------------------------------------------------------------------
% STATE VARIABLES (quantities with memory, updated every time step)
%   iac    grid current through the source R-L (A)
%   vlink  intermediate DC-link capacitor voltage (V)
%   vbus   12 V DC bus capacitor voltage (V)
%   xg, xpv, xd   integrator states of the three converter PI loops
%   soc    battery state of charge
%   Ilim   grid-converter output-current limit set by the EMS (A)
%
% THEORY - numerical integration (forward Euler):
%   Every state obeys dx/dt = f(x, t). Over a small step dt,
%   x(t+dt) = x(t) + f(x,t)*dt. It is accurate when dt is much smaller
%   than every time constant in the circuit, which 5 us is here.
% ------------------------------------------------------------------
dt = sc.dt; N = round(sc.t_end/dt); w = 2*pi*p.f_grid;
Ncyc_s = round(1/p.f_grid/dt);       % samples per 20 ms cycle (4000)

% initial conditions
iac = 0; vlink = 0; vbus = p.Vref_grid; xg = 0; xpv = 0; xd = 0;
soc = p.SOC0; ibat = 0; mode = p.IDLE; Ilim = p.Imax_g;
fly_on = false; dis_ok = true; ems_started = false;
s = 0;                                % bridge conduction sign (+1, -1, 0)

% PI controller gains for the three bus converters
% THEORY - PI control: output = Kp*error + Ki*integral(error).
%   Kp reacts to the present error, the integral removes steady-state
%   error. "Anti-windup": when the output hits its limit the integral is
%   frozen, otherwise it keeps growing and the converter overshoots when
%   it comes off the limit.
%   With C_bus = 22 mF, Kp = 2 A/V gives a loop bandwidth of about
%   Kp/(2*pi*C) = 14 Hz: slow enough to ignore the 100 Hz ripple.
Kp = 2; Ki = 40;

% Inverter: AC load and its DC power demand
% THEORY - power of a single-phase AC load:
%   v = Vpk*sin(wt), i = Ipk*sin(wt) (resistive) so
%   p(t) = v*i = Vpk*Ipk*sin^2(wt) = P*(1 - cos(2wt)),  P = Vrms*Irms.
%   Instantaneous power swings between 0 and 2P at TWICE line frequency
%   (100 Hz). The inverter passes this pulsation to its DC side, so the
%   12 V bus sees a 100 Hz current ripple that the bus capacitor absorbs.

% per-cycle measurement accumulators (reset every 20 ms)
acc = zeros(1,16); kc = 0; nc = 0;
maxc = floor(N/Ncyc_s);
C = struct('t_end',zeros(maxc,1),'Vrms',0,'Irms',0,'f',0,'P',0,'Q1',0,'N',0, ...
           'S',0,'PF',0,'Pconv_in',0,'Pconv_out',0,'eta',0,'THD',0,'Vbus',0,'Pbat',0,'Pinv',0,'Ppv',0);
fn = fieldnames(C); for q = 2:numel(fn), C.(fn{q}) = zeros(maxc,1); end
lastP = 0; lastPinv = 0; lastPpv = 0; vprev = 0; zc = 0;

% logging
nl = floor(N/sc.log_every); li = 0;
LG = struct('t',zeros(nl,1),'vs',zeros(nl,1),'iac',zeros(nl,1),'vlink',zeros(nl,1), ...
    'vbus',zeros(nl,1),'ipv',zeros(nl,1),'ig',zeros(nl,1),'idis',zeros(nl,1), ...
    'iinv',zeros(nl,1),'ibat',zeros(nl,1),'mode',zeros(nl,1),'vload',zeros(nl,1),'iload',zeros(nl,1));

for n = 1:N
    t = n*dt;

    % ===== Step A: grid source and protection =======================
    vs = p.Vgrid_pk*sin(w*t);                    % 230 V RMS, 50 Hz
    R  = p.R_src + (t < p.t_bypass)*p.R_inrush;  % inrush resistor at start-up

    % ===== Step B: diode bridge (AC -> DC) ==========================
    % THEORY - full-wave diode bridge with a capacitor:
    %   Two diodes conduct when |v_grid| exceeds v_link + 2*Vf. Then
    %   L di/dt = v_s - R*i - sign*(v_link + 2*Vf). The current can
    %   only flow forward through the diodes: when it falls to zero the
    %   bridge switches off and stays off until the next voltage peak.
    %   This on/off behaviour is what makes the current pulsed and the
    %   power factor low.
    vth = vlink + 2*p.Vf_diode;
    if s == 0 && abs(vs) > vth
        s = sign(vs);                            % bridge turns on
    end
    if s ~= 0
        iac = iac + dt*(vs - R*iac - s*vth)/p.L_src;
        if s*iac <= 0, iac = 0; s = 0; end       % diodes turn off
    end
    irect = abs(iac);                            % current into the DC link

    % ===== Step C: load steps and inverter demand ===================
    nsteps = sc.n_before; if t >= sc.t_step, nsteps = sc.n_after; end
    Pac_load = nsteps*p.P_step;                  % mean AC load power
    vload = p.Vgrid_pk*sin(w*t);                 % inverter output, 230 V
    iload = 0; if nsteps > 0, iload = vload/(p.R_step/nsteps); end
    pinv_dc = Pac_load*(1 - cos(2*w*t)) + p.lossINV(Pac_load);   % DC side, W
    iinv = pinv_dc/vbus;

    % ===== Step D: PV converter (set-point 12.6 V) ==================
    % THEORY - DC-bus signalling: every converter regulates the SAME bus
    %   to its OWN set-point. The highest set-point (PV, 12.6 V) is
    %   satisfied first; if it cannot hold the bus up, the bus falls to
    %   the next one (grid, 12.4 V), and then to the battery (12.0 V).
    %   No communication is needed for this priority.
    Ipv_max = p.eta_pv*sc.P_pv/vbus;
    [ipv, xpv] = pi_step(p.Vref_pv - vbus, xpv, Kp, Ki, dt, Ipv_max);

    % ===== Step E: grid converter (isolated flyback, 12.4 V) ========
    % THEORY - average model of a DC/DC converter: over many switching
    %   periods, power in = power out + losses. So the converter takes
    %   i_link = P_in / v_link from the 310 V capacitor and delivers
    %   i_g into the 12 V bus. The PI loop sets i_g; the EMS's I_lim
    %   clamps it. UVLO: it starts only once v_link > V_uvlo.
    if ~fly_on && vlink > p.V_uvlo, fly_on = true; end
    if fly_on && vlink < 0.75*p.V_uvlo, fly_on = false; end
    if fly_on
        [ig, xg] = pi_step(p.Vref_grid - vbus, xg, Kp, Ki, dt, min(Ilim, p.Imax_g));
        Pg_out = vbus*ig;
        Pg_in  = Pg_out + p.fly_P0 + p.fly_k1*Pg_out + p.fly_k2*Pg_out^2;   % flyback losses only
        ilink  = Pg_in/vlink;
    else
        ig = 0; Pg_out = 0; Pg_in = 0; ilink = 0; xg = 0;
    end
    vlink = vlink + dt*(irect - ilink)/p.C_link;   % C dv/dt = i_in - i_out

    % ===== Step F: battery discharger (LTC3780, 12.0 V) =============
    % THEORY - battery as an internal-resistance (Rint) model:
    %   v_bat = OCV(SOC) - R0*i_bat. OCV falls as the battery empties.
    %   Coulomb counting: dSOC/dt = -i_bat / (3600*Ah).
    if sc.batt_on && mode == p.DISCHARGE
        [idis, xd] = pi_step(p.Vref_dis - vbus, xd, Kp, Ki, dt, p.Idis_max);
    else
        idis = 0; xd = 0;
    end
    vbat = p.OCV(soc) - p.R0_bat*ibat;
    ibat = (vbus*idis/p.eta_dis)/vbat;             % current drawn from the cells
    soc  = soc - ibat*dt/(3600*p.Cbat_Ah);

    % ===== Step G: DC bus capacitor =================================
    vbus = vbus + dt*(ipv + ig + idis - iinv)/p.C_bus;

    % ===== Step H: per-cycle measurements ===========================
    % THEORY - AC quantities over one full cycle T = 20 ms:
    %   Vrms = sqrt(mean(v^2)), Irms = sqrt(mean(i^2))
    %   Real power      P  = mean(v*i)
    %   Apparent power  S  = Vrms*Irms
    %   Power factor    PF = P/S
    %   Fundamental phasors by a one-frequency Fourier transform:
    %     X1 = (2/T) * integral of x(t)*exp(-j*w*t) dt
    %   Fundamental reactive power Q1 = Im(V1*conj(I1))/2.
    %   With a diode bridge most of S that is not P is HARMONIC current,
    %   not phase shift, so N = sqrt(S^2 - P^2) (non-active power) is
    %   reported beside Q1. THD = harmonic RMS / fundamental RMS.
    %   Frequency: count positive-going zero crossings of v per second.
    cs = cos(w*t); sn = sin(w*t);
    acc = acc + [vs*iac, vs^2, iac^2, vs*cs, vs*sn, iac*cs, iac*sn, ...
                 R*iac^2, Pg_out, vbus, vbus*idis, pinv_dc, vbus*ipv, 0, 0, 0];
    if vprev < 0 && vs >= 0, zc = zc + 1; end
    vprev = vs; kc = kc + 1;
    if kc == Ncyc_s
        nc = nc + 1; a = acc/kc;
        Vr = sqrt(a(2)); Ir = sqrt(a(3)); P = a(1); S = Vr*Ir;
        V1 = 2*complex(a(4), -a(5)); I1 = 2*complex(a(6), -a(7));
        Q1 = imag(V1*conj(I1))/2; I1rms = abs(I1)/sqrt(2);
        C.t_end(nc) = t; C.Vrms(nc) = Vr; C.Irms(nc) = Ir; C.P(nc) = P;
        C.f(nc) = zc/(kc*dt); C.S(nc) = S; C.PF(nc) = P/max(S,1e-9);
        C.Q1(nc) = Q1; C.N(nc) = sqrt(max(S^2-P^2,0));
        C.THD(nc) = sqrt(max(Ir^2 - I1rms^2,0))/max(I1rms,1e-9);
        C.Pconv_in(nc) = P - a(8);  C.Pconv_out(nc) = a(9);
        C.eta(nc) = a(9)/max(P - a(8),1e-9);
        C.Vbus(nc) = a(10); C.Pbat(nc) = a(11); C.Pinv(nc) = a(12); C.Ppv(nc) = a(13);
        lastP = P; lastPinv = a(12); lastPpv = a(13);
        acc(:) = 0; kc = 0; zc = 0;
    end

    % ===== Step I: the EMS (every T_ems once enabled) ================
    % Same rule as Level 1, using MEASURED per-cycle values:
    %   P_net = P_DC,inv - P_pv ; cap = bus-side equivalent of P_lim
    %   DISCHARGE if P_net > cap and SOC allows; otherwise IDLE.
    %   In DISCHARGE the EMS also trims I_lim with a slow integral loop
    %   so that the MEASURED P_grid,AC settles at P_lim (closing the
    %   limit on AC power, as the specification requires).
    %   Charging is not exercised in this 3 s scenario (no PV surplus).
    if t >= sc.t_ems_on && mod(n, round(sc.T_ems/dt)) == 0 && nc > 0
        cap = p.invACDC(p.P_lim);
        P_net = lastPinv - lastPpv;
        if soc <= p.SOC_min, dis_ok = false; end
        if soc >= p.SOC_min + p.SOC_hyst, dis_ok = true; end
        if sc.batt_on && P_net > cap && dis_ok
            if mode ~= p.DISCHARGE
                mode = p.DISCHARGE;
                Ilim = cap/vbus;                    % first guess from the loss model
            else
                Ki_ems = 0.2;                       % A per (W*s)
                Ilim = Ilim + Ki_ems*(p.P_lim - lastP)*sc.T_ems;
            end
            Ilim = min(max(Ilim,0), p.Imax_g);
        else
            mode = p.IDLE; Ilim = p.Imax_g;         % no limit needed
        end
        ems_started = true;
    end

    % ===== Step J: log ===============================================
    if mod(n, sc.log_every) == 0
        li = li + 1;
        LG.t(li)=t; LG.vs(li)=vs; LG.iac(li)=iac; LG.vlink(li)=vlink; LG.vbus(li)=vbus;
        LG.ipv(li)=ipv; LG.ig(li)=ig; LG.idis(li)=idis; LG.iinv(li)=iinv; LG.ibat(li)=ibat;
        LG.mode(li)=mode; LG.vload(li)=vload; LG.iload(li)=iload;
    end
end
for q = 1:numel(fn), C.(fn{q}) = C.(fn{q})(1:nc); end
r.cyc = C; r.log = LG; r.soc_end = soc; r.ems_started = ems_started;
end

function [u, x] = pi_step(e, x, Kp, Ki, dt, umax)
% One step of a PI controller with output limits [0, umax] and
% anti-windup (the integral stops growing while the output is limited).
u_unsat = Kp*e + x;
u = min(max(u_unsat, 0), umax);
if u == u_unsat || (u_unsat > umax && e < 0) || (u_unsat < 0 && e > 0)
    x = x + Ki*e*dt;
end
x = min(max(x, -umax), umax);
end
