%% make_profiles.m  --  creates the two input signals for EMS_Level1.slx
%  Run this BEFORE you press Run in Simulink. It creates two variables in
%  the base workspace:
%      load_ts   AC household load, watts, one sample per minute (timeseries)
%      pv_ts     PV power available at the panel, watts (timeseries)
%  Your two From Workspace blocks read these two names, so the model
%  itself does not change when you switch profile.
%
%  CHOOSE THE PROFILE (edit the next line only):
%     'synthetic'                     the original test day
%     'profile_summer_typical.csv'    CEEW Mathura, May-Aug, median household, average day
%     'profile_summer_realday.csv'    one measured summer day (spiky)
%     'profile_winter_typical.csv'    CEEW Mathura, Nov-Dec, median household, average day
%     'profile_winter_realday.csv'    one measured winter day (spiky)
%  The CSV files must be in the Current Folder (or give the full path).
profile_file = 'profile_day.csv';
show_plot    = true;      % draw a quick check plot

params_ems                % loads the parameter struct p

dt_s = 60;                % one sample per minute
t_s  = (0:1439)' * dt_s;  % seconds
t_h  = t_s / 3600;        % hours
N    = numel(t_s);

if ~strcmpi(profile_file,'synthetic') && isfile(profile_file)
    %% Real-data path: scaled load and PV, one row per minute
    T = readtable(profile_file);
    needed = {'P_load_ac_W','P_pv_avail_W'};
    assert(height(T) == 1440 && all(ismember(needed, T.Properties.VariableNames)), ...
        '%s must have 1440 rows and the columns P_load_ac_W and P_pv_avail_W.', profile_file);
    P_load_ac    = T.P_load_ac_W(:);
    P_pv_avail   = T.P_pv_avail_W(:);
    profile_name = profile_file;
else
    %% Synthetic test profile (same as before)
    if ~strcmpi(profile_file,'synthetic')
        warning('make_profiles:missingFile', ...
            '%s was not found, so the SYNTHETIC test profile is used instead.', profile_file);
    end
    P_load_ac = 6 * ones(N,1);                 % night base load
    P_load_ac(t_h >= 6    & t_h < 8)    = 18;  % morning peak
    P_load_ac(t_h >= 8    & t_h < 17)   = 10;  % daytime
    P_load_ac(t_h >= 17   & t_h < 18.5) = 18;  % evening build-up
    P_load_ac(t_h >= 18.5 & t_h < 22)   = 28;  % evening peak
    P_load_ac(t_h >= 19.5 & t_h < 21)   = 36;  % top of the evening peak
    P_load_ac(t_h >= 22)                = 10;  % late evening
    rng(1);                                    % repeatable "noise"
    P_load_ac  = max(0, P_load_ac + randn(N,1));
    P_pv_avail = 0.85 * p.Ppv_rated .* max(0, sin(pi*(t_h - 6.5)/12));
    profile_name = 'SYNTHETIC TEST PROFILE';
end

%% The two signals the From Workspace blocks read
load_ts = timeseries(P_load_ac,  t_s, 'Name', 'AC load (W)');
pv_ts   = timeseries(P_pv_avail, t_s, 'Name', 'PV available (W)');

fprintf('Profile: %s\n', profile_name);
fprintf('  load: peak %.1f W, mean %.1f W, energy %.0f Wh per day\n', ...
        max(P_load_ac), mean(P_load_ac), sum(P_load_ac)/60);
fprintf('  PV  : peak %.1f W, energy %.0f Wh per day\n', max(P_pv_avail), sum(P_pv_avail)/60);

if show_plot
    figure('Name','Input profiles','Color','w');
    plot(t_h, P_load_ac, 'b', t_h, P_pv_avail, 'r', 'LineWidth', 1.2);
    grid on; xlim([0 24]); xlabel('Time of day (h)'); ylabel('Power (W)');
    legend('AC load', 'PV available', 'Location', 'northwest');
    title(['Input profiles: ' strrep(profile_name,'_','\_')]);
end
