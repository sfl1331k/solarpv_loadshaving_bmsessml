function make_figures(out, level, outdir, label)
%MAKE_FIGURES  Export the report figures (PNG + PDF) from a Simulink run.
%
%   out = sim('EMSLEVEL1');   make_figures(out, 1);
%   out = sim('EMSLEVEL2');   make_figures(out, 2);
%   make_figures(out, 1, 'figures_L1', 'Summer typical day (CEEW, scaled)')
%
%   out    result of sim(...) (Simulink.SimulationOutput with logged signals)
%   level  1 or 2
%   outdir folder for the files (default 'figures')
%   label  optional text added to every title, e.g. which profile was used
%
%   HOW TO LOG A SIGNAL: double-click the signal line and give it the exact
%   name below, then right-click the line and choose "Log Selected Signals".
%   Names are not case-sensitive. A figure whose signals are missing is
%   skipped with a warning; nothing else breaks.
%
%   Level 1 names:  P_grid_AC  P_grid_DC  P_PV_bus  P_bat_bus  P_DC_inv
%                   SOC  I_grid_RMS  PF_grid
%                   (PV_bubs and PDC_INV are also accepted)
%   Level 2 names:  vs  iac  Vlink  Vbus  P_grid_AC  ipv  ig  idis  soc  Ilim
%
%   The "without EMS" curve in Level 1 is computed from P_DC_inv and P_PV_bus
%   with the AC/DC loss model in params_ems.m, so no second run is needed.

if nargin < 3 || isempty(outdir), outdir = 'figures'; end
if nargin < 4, label = ''; end
if ~exist(outdir, 'dir'), mkdir(outdir); end
p = get_params();
switch level
    case 1, level1_figures(out, p, outdir, label);
    case 2, level2_figures(out, p, outdir, label);
    otherwise, error('make_figures:level', 'level must be 1 or 2.');
end
end

%% ===================================================================
%  LEVEL 1
%% ===================================================================
function level1_figures(out, p, outdir, label)
[tg, Pg] = getsig(out, {'P_grid_AC'});
if isempty(tg), error('make_figures:noSignal', 'P_grid_AC was not found in the run output.'); end
t_h = tg / 3600;
dt_min = median(diff(tg)) / 60;
Pg   = on_grid(tg, tg, Pg);
Pdc  = fetch(out, tg, {'P_DC_inv','PDC_INV'});
Ppv  = fetch(out, tg, {'P_PV_bus','PV_bubs','PV_bus'});
Pbat = fetch(out, tg, {'P_bat_bus'});
Pgd  = fetch(out, tg, {'P_grid_DC'});
soc  = fetch(out, tg, {'SOC'});
Ig   = fetch(out, tg, {'I_grid_RMS'});
pf   = fetch(out, tg, {'PF_grid'});

% Without-EMS grid power: no battery, grid covers whatever PV cannot
Pbase = [];
if ~isempty(Pdc) && ~isempty(Ppv)
    Pnet  = max(Pdc - Ppv, 0);
    Pbase = Pnet + p.lossACDC(Pnet);
end
Plim = p.P_lim;
ttl  = @(s) title_text(s, label);

% ---- Figure 1: grid AC power with and without the EMS (the main plot)
if ~isempty(Pbase)
    f = newfig();
    plot(t_h, Pbase, 'Color', [0.6 0.6 0.6], 'LineWidth', 1.2); hold on;
    plot(t_h, Pg, 'b', 'LineWidth', 1.5);
    yline(Plim, 'r--', sprintf('P_{lim} = %g W', Plim), 'LineWidth', 1.2);
    grid on; xlim([0 24]); xlabel('Time of day (h)'); ylabel('Grid AC power (W)');
    legend('Without EMS', 'With EMS', 'Location', 'northwest');
    title(ttl('Grid AC power with and without the EMS'));
    save_fig(f, outdir, 'L1_fig1_grid_power');
else
    warning('make_figures:skip', 'Figure 1 skipped: needs P_DC_inv and P_PV_bus.');
end

% ---- Figure 2: battery state of charge and battery power
if ~isempty(soc)
    f = newfig();
    subplot(2,1,1);
    plot(t_h, 100*soc, 'LineWidth', 1.5); hold on;
    yline(100*p.SOC_min, 'r--', 'SOC_{min}'); yline(100*p.SOC_max, 'g--', 'SOC_{max}');
    grid on; xlim([0 24]); ylabel('SOC (%)'); title(ttl('Battery state of charge'));
    subplot(2,1,2);
    if ~isempty(Pbat)
        plot(t_h, Pbat, 'LineWidth', 1.2);
    end
    grid on; xlim([0 24]); xlabel('Time of day (h)'); ylabel('Battery power to bus (W)');
    save_fig(f, outdir, 'L1_fig2_battery');
else
    warning('make_figures:skip', 'Figure 2 skipped: needs SOC.');
end

% ---- Figure 3: who supplies the DC bus
if ~isempty(Ppv) && ~isempty(Pgd) && ~isempty(Pbat) && ~isempty(Pdc)
    f = newfig();
    Pused = min(Ppv, Pdc);
    area(t_h, [Pused, Pgd, Pbat], 'LineStyle', 'none'); hold on;
    plot(t_h, Pdc, 'k', 'LineWidth', 1.2);
    grid on; xlim([0 24]); xlabel('Time of day (h)'); ylabel('Power on the DC bus (W)');
    legend('PV', 'Grid (after AC/DC)', 'Battery', 'Inverter DC input (demand)', 'Location', 'northwest');
    title(ttl('Sources supplying the DC bus'));
    save_fig(f, outdir, 'L1_fig3_bus_sources');
else
    warning('make_figures:skip', 'Figure 3 skipped: needs P_PV_bus, P_grid_DC, P_bat_bus, P_DC_inv.');
end

% ---- Figure 4: grid current and power factor
if ~isempty(Ig) && ~isempty(pf)
    f = newfig();
    subplot(2,1,1); plot(t_h, Ig, 'b', 'LineWidth', 1.2); grid on; xlim([0 24]);
    ylabel('Grid current (A RMS)'); title(ttl('Grid current and power factor'));
    subplot(2,1,2); plot(t_h, pf, 'LineWidth', 1.2); grid on; xlim([0 24]); ylim([0 1]);
    xlabel('Time of day (h)'); ylabel('Power factor');
    save_fig(f, outdir, 'L1_fig4_grid_current_pf');
else
    warning('make_figures:skip', 'Figure 4 skipped: needs I_grid_RMS and PF_grid.');
end

% ---- Figure 5: grid load-duration curve
if ~isempty(Pbase)
    f = newfig(); n = numel(Pg);
    plot((1:n)/n*100, sort(Pbase, 'descend'), 'Color', [0.6 0.6 0.6], 'LineWidth', 1.2); hold on;
    plot((1:n)/n*100, sort(Pg, 'descend'), 'b', 'LineWidth', 1.5);
    grid on; xlabel('Share of the day (%)'); ylabel('Grid AC power (W)');
    legend('Without EMS', 'With EMS'); title(ttl('Grid load-duration curve'));
    save_fig(f, outdir, 'L1_fig5_load_duration');
end

% ---- Metrics table (also written to CSV)
if ~isempty(Pbase)
    m = {'Peak grid AC power (W)',        max(Pbase),              max(Pg);
         'Mean grid AC power (W)',        mean(Pbase),             mean(Pg);
         'Load factor',                   mean(Pbase)/max(Pbase),  mean(Pg)/max(Pg);
         'Grid energy (Wh)',              sum(Pbase)*dt_min/60,    sum(Pg)*dt_min/60;
         'Minutes above P_lim',           sum(Pbase > Plim+0.5)*dt_min, sum(Pg > Plim+0.5)*dt_min};
    fid = fopen(fullfile(outdir, 'L1_metrics.csv'), 'w');
    fprintf(fid, 'metric,without_EMS,with_EMS\n');
    fprintf('\n%-28s %12s %12s\n', 'Level 1 metrics', 'without EMS', 'with EMS');
    for k = 1:size(m,1)
        fprintf(fid, '%s,%.4g,%.4g\n', m{k,1}, m{k,2}, m{k,3});
        fprintf('%-28s %12.4g %12.4g\n', m{k,1}, m{k,2}, m{k,3});
    end
    fclose(fid);
    fprintf('Peak reduction: %.1f %% (P_lim = %g W)\n', 100*(1 - max(Pg)/max(Pbase)), Plim);
end
end

%% ===================================================================
%  LEVEL 2
%% ===================================================================
function level2_figures(out, p, outdir, label)
ttl = @(s) title_text(s, label);
t_step = 0.8;  t_ems = 1.5;                       % load step and EMS start (s)

% ---- Figure 1: grid voltage and current waveforms, 3 cycles before the load step
[t1, vs]  = getsig(out, {'vs'});
[t2, iac] = getsig(out, {'iac'});
if ~isempty(t1) && ~isempty(t2)
    w1 = t1 >= 0.70 & t1 <= 0.76;  w2 = t2 >= 0.70 & t2 <= 0.76;
    f = newfig();
    subplot(2,1,1); plot(t1(w1), vs(w1), 'LineWidth', 1.2); grid on;
    ylabel('Grid voltage (V)'); title(ttl('Grid voltage and current (three cycles)'));
    subplot(2,1,2); plot(t2(w2), iac(w2), 'LineWidth', 1.2); grid on;
    ylabel('Grid current (A)'); xlabel('Time (s)');
    save_fig(f, outdir, 'L2_fig1_grid_waveforms');
else
    warning('make_figures:skip', 'Figure 1 skipped: needs vs and iac.');
end

% ---- Figure 2: DC-link voltage and DC-bus voltage
[tl, Vl] = getsig(out, {'Vlink'});
[tb, Vb] = getsig(out, {'Vbus'});
if ~isempty(tl) && ~isempty(tb)
    f = newfig();
    subplot(2,1,1); plot(tl(dec(tl)), Vl(dec(tl)), 'LineWidth', 1.2); grid on;
    ylabel('DC link (V)'); title(ttl('DC-link and DC-bus voltages'));
    subplot(2,1,2); plot(tb(dec(tb)), Vb(dec(tb)), 'LineWidth', 1.0); hold on; grid on;
    xline(t_step, 'k:', 'load step'); xline(t_ems, 'k:', 'EMS on');
    ylabel('DC bus (V)'); xlabel('Time (s)');
    save_fig(f, outdir, 'L2_fig2_voltages');
else
    warning('make_figures:skip', 'Figure 2 skipped: needs Vlink and Vbus.');
end

% ---- Figure 3: grid real power per cycle with the limit (the main plot)
[tp, Pg] = getsig(out, {'P_grid_AC'});
if ~isempty(tp)
    f = newfig();
    plot(tp(dec(tp)), Pg(dec(tp)), 'b', 'LineWidth', 1.5); hold on; grid on;
    yline(p.P_lim, 'r--', sprintf('P_{lim} = %g W', p.P_lim), 'LineWidth', 1.2);
    xline(t_step, 'k:', 'load step'); xline(t_ems, 'k:', 'EMS on');
    xlabel('Time (s)'); ylabel('Grid real power (W)');
    title(ttl('Grid real power, averaged over each 20 ms cycle'));
    save_fig(f, outdir, 'L2_fig3_grid_power');

    % Mean grid power in three windows (answer key for the three-phase test)
    win = {'before the load step (0.6-0.8 s)', 0.6, 0.8;
           'after the step, EMS off (1.3-1.5 s)', 1.3, 1.5;
           'EMS on, settled (2.5-3.0 s)', 2.5, 3.0};
    fid = fopen(fullfile(outdir, 'L2_grid_power_windows.csv'), 'w');
    fprintf(fid, 'window,mean_grid_AC_W\n');
    fprintf('\n%-40s %s\n', 'Level 2 grid AC power', 'mean (W)');
    for k = 1:size(win,1)
        sel = tp >= win{k,2} & tp <= win{k,3};
        v = mean(Pg(sel));
        fprintf(fid, '%s,%.4g\n', win{k,1}, v);
        fprintf('%-40s %8.3g\n', win{k,1}, v);
    end
    fclose(fid);
else
    warning('make_figures:skip', 'Figure 3 skipped: needs P_grid_AC.');
end

% ---- Figure 4: converter currents into the bus (20 ms moving average)
[ta, ipv]  = getsig(out, {'ipv'});
[~,  ig]   = getsig(out, {'ig'});
[~,  idis] = getsig(out, {'idis'});
if ~isempty(ta) && ~isempty(ig) && ~isempty(idis)
    w = max(1, round(0.02 / median(diff(ta))));
    sm = @(y) filter(ones(w,1)/w, 1, y);
    k = dec(ta);
    a1 = sm(ipv); a2 = sm(ig); a3 = sm(idis);
    f = newfig();
    plot(ta(k), a1(k), 'LineWidth', 1.3); hold on;
    plot(ta(k), a2(k), 'LineWidth', 1.3);
    plot(ta(k), a3(k), 'LineWidth', 1.3);
    xline(t_step, 'k:', 'load step'); xline(t_ems, 'k:', 'EMS on'); grid on;
    xlabel('Time (s)'); ylabel('Current into the bus (A, 20 ms average)');
    legend('PV', 'Grid converter', 'Battery', 'Location', 'northwest');
    title(ttl('Which converter supplies the bus'));
    save_fig(f, outdir, 'L2_fig4_bus_currents');
else
    warning('make_figures:skip', 'Figure 4 skipped: needs ipv, ig and idis.');
end

% ---- Figure 5: battery SOC and the EMS current limit
[ts, soc]  = getsig(out, {'soc'});
[tq, Ilim] = getsig(out, {'Ilim'});
if ~isempty(ts) && ~isempty(tq)
    f = newfig();
    subplot(2,1,1); plot(ts(dec(ts)), 100*soc(dec(ts)), 'LineWidth', 1.3); grid on;
    ylabel('SOC (%)'); title(ttl('Battery SOC and EMS current limit'));
    subplot(2,1,2); stairs(tq(dec(tq)), Ilim(dec(tq)), 'LineWidth', 1.3); grid on;
    ylabel('I_{lim} (A)'); xlabel('Time (s)');
    save_fig(f, outdir, 'L2_fig5_soc_ilim');
else
    warning('make_figures:skip', 'Figure 5 skipped: needs soc and Ilim.');
end
end

%% ===================================================================
%  HELPERS
%% ===================================================================
function p = get_params()
% Use the parameter struct in the base workspace, or load it.
try
    p = evalin('base', 'p');
catch
    evalin('base', 'params_ems');
    p = evalin('base', 'p');
end
end

function c = title_text(s, label)
if isempty(label), c = s; else c = {s, label}; end
end

function f = newfig()
f = figure('Color', 'w', 'Position', [100 100 900 520]);
end

function save_fig(f, outdir, name)
try, theme(f, 'light'); catch, end              % light theme for printing (newer MATLAB)
exportgraphics(f, fullfile(outdir, [name '.png']), 'Resolution', 300);
exportgraphics(f, fullfile(outdir, [name '.pdf']), 'ContentType', 'vector');
close(f);
fprintf('  saved %s\n', name);
end

function k = dec(t)
% Index vector that thins a long signal to about 20000 points for plotting.
step = max(1, floor(numel(t) / 20000));
k = 1:step:numel(t);
end

function y = fetch(out, tg, names)
% Signal by name, resampled onto the time vector tg ([] if not found).
[t, y] = getsig(out, names);
y = on_grid(tg, t, y);
end

function y = on_grid(tg, t, y)
if isempty(y), return; end
y = y(:); t = t(:);
if numel(t) == numel(tg) && max(abs(t - tg(:))) < 1e-9, return; end
[t, iu] = unique(t);
y = interp1(t, y(iu), tg, 'linear', 'extrap');
end

function [t, y] = getsig(out, names)
% Find a logged signal by name (not case-sensitive; several names allowed).
t = []; y = [];
if ischar(names), names = {names}; end
for k = 1:numel(names)
    nm = names{k};
    % 1) Signal logging: out.logsout
    ls = [];
    try, ls = out.logsout; catch, end
    if ~isempty(ls)
        el = ls.getElementNames();
        i = find(strcmpi(el, nm), 1);
        if ~isempty(i)
            v = ls.getElement(i).Values;
            t = v.Time(:); y = squeeze(v.Data); y = y(:);
            return
        end
    end
    % 2) A To Workspace variable called nm (timeseries), or a plain struct
    %    of timeseries-like fields (field names not case-sensitive)
    try
        if isstruct(out)
            fn = fieldnames(out); j = find(strcmpi(fn, nm), 1);
            if isempty(j), continue; end
            v = out.(fn{j});
        else
            v = out.(nm);
        end
        if isstruct(v) && isfield(v, 'Time')
            t = v.Time(:); y = squeeze(v.Data); y = y(:); return
        elseif isa(v, 'timeseries')
            t = v.Time(:); y = squeeze(v.Data); y = y(:); return
        end
    catch
    end
end
end
