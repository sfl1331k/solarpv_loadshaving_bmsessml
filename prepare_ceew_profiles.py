"""
prepare_ceew_profiles.py
Builds 1-minute, prototype-scale daily profiles for Level 1 from the CEEW Mathura 2019
smart-meter data (38 homes, 3-minute readings, May-Dec 2019).

Outputs (columns exactly as level1_energy_balance.m expects):
    minute, P_load_ac_W, P_pv_avail_W

Two load variants per season
    typical : median household of the average day (smooth, shows the seasonal pattern)
    realday : one measured day of the median-energy household (spiky, a stress test)

Settings you may change are in the block below.
"""
import numpy as np, pandas as pd

SRC     = 'CEEW_-_Smart_meter_data_Mathura_2019.csv'
OUTDIR  = '.'
P_PEAK  = 36.0        # W   prototype AC-load peak after scaling (same as the synthetic day)
PV_PEAK = 0.85 * 20   # W   PV available peak = derate 0.85 x 20 W panel (as in params_ems.m)
SEASONS = {           # sunrise/sunset in local hours: APPROXIMATE, replace with irradiance data
    'summer': dict(months=[5, 6, 7, 8], sunrise=5 + 40/60, sunset=19 + 10/60),
    'winter': dict(months=[11, 12],     sunrise=7 + 10/60, sunset=17 + 30/60),
}

df = pd.read_csv(SRC)
df.columns = ['ts', 'kwh', 'volt', 'amp', 'freq', 'meter']
df['ts'] = pd.to_datetime(df['ts'])
# 0 V rows are grid outages; a few rows have impossible voltage/frequency readings
df['valid'] = df.volt.between(150, 300) & df.freq.between(49, 51) & (df.kwh >= 0)
df['P'] = np.where(df.valid, df.kwh * 1000 * 20, np.nan)     # W, mean power over the 3-min interval
df['date'] = df.ts.dt.date
df['bin'] = (df.ts.dt.hour * 60 + df.ts.dt.minute) // 3       # 0..479
df['month'] = df.ts.dt.month
print(f"rows {len(df)}, outage/bad rows {(~df.valid).sum()} ({(~df.valid).mean()*100:.1f} %)")

def pv_profile(sunrise, sunset):
    t = np.arange(1440) / 60
    return np.where((t >= sunrise) & (t <= sunset),
                    PV_PEAK * np.sin(np.pi * (t - sunrise) / (sunset - sunrise)), 0.0)

def to_minutes(p480):
    return np.repeat(p480, 3)                                 # hold each 3-min value for 3 minutes

rows = []
for name, cfg in SEASONS.items():
    d = df[df.month.isin(cfg['months'])]

    # ---- typical: per-meter average day (>= 10 valid samples per bin), median across meters
    cnt = d.groupby(['meter', 'bin']).P.count().unstack()      # valid samples only
    pm = d.groupby(['meter', 'bin']).P.mean().unstack().where(cnt >= 10)
    pm = pm.loc[pm.dropna(thresh=470).index]
    typical = pm.median(axis=0).interpolate().bfill().ffill().values

    # ---- realday: median-energy meter, its fully valid day closest to that meter's median energy
    g = d.groupby(['meter', 'date'])
    day = pd.DataFrame({'n': g.size(), 'nv': g['valid'].sum(), 'E_kWh': g['P'].sum() / 20 / 1000})
    ok = day[(day.n >= 480) & (day.nv >= 480)]
    med = ok.groupby('meter').E_kWh.median()
    meter = (med - med.median()).abs().idxmin()
    cand = ok.loc[meter]
    dstar = (cand.E_kWh - cand.E_kWh.median()).abs().idxmin()
    x = d[(d.meter == meter) & (d.date == dstar)].sort_values('bin')
    realday = x.P.values
    assert len(realday) == 480 and not np.isnan(realday).any()

    pv = pv_profile(cfg['sunrise'], cfg['sunset'])
    for variant, p480, tag in (('typical', typical, f'{len(pm)} meters, median household'),
                               ('realday', realday, f'meter {meter}, {dstar}')):
        pmin = to_minutes(p480)
        load = pmin * (P_PEAK / pmin.max())                   # peak-scaling rule from the roadmap
        out = pd.DataFrame({'minute': np.arange(1440),
                            'P_load_ac_W': load.round(3), 'P_pv_avail_W': pv.round(3)})
        fn = f'{OUTDIR}/profile_{name}_{variant}.csv'
        out.to_csv(fn, index=False)
        k = int(np.argmax(load))
        rows.append(dict(file=fn.split('/')[-1], source=tag,
                         real_peak_W=round(pmin.max()), scale=round(P_PEAK / pmin.max(), 4),
                         mean_W=round(load.mean(), 1), load_factor=round(load.mean() / load.max(), 2),
                         peak_at=f'{k//60:02d}:{k%60:02d}',
                         load_Wh=round(load.sum() / 60), pv_Wh=round(pv.sum() / 60)))
print(pd.DataFrame(rows).to_string(index=False))
