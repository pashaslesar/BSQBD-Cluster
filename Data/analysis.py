import pandas as pd
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
import warnings
warnings.filterwarnings('ignore')

plt.rcParams['figure.dpi'] = 110
plt.rcParams['axes.spines.top'] = False
plt.rcParams['axes.spines.right'] = False

import os
OUT = os.path.dirname(os.path.abspath(__file__))

dubai = pd.read_csv(os.path.join(OUT, 'dubai-restaurants.csv'))
usa   = pd.read_csv(os.path.join(OUT, 'fastfood-usa-restaurants.csv'))
india = pd.read_csv(os.path.join(OUT, 'indian-restaurants.csv'), encoding='utf-8-sig')
india = india.rename(columns=lambda c: c.strip().replace(' ', ''))

for col in ['lat','lng','polarity']:
    dubai[col] = pd.to_numeric(dubai[col], errors='coerce')
for col in ['latitude','longitude']:
    usa[col] = pd.to_numeric(usa[col], errors='coerce')
for col in ['rating','average_price','average_delivery_time',
            'south_indian_or_not','north_indian_or_not','fast_food_or_not',
            'street_food','biryani_or_not','bakery_or_not']:
    india[col] = pd.to_numeric(india[col], errors='coerce')

print(f'Dubai:  {len(dubai):>6} rows  |  {dubai.shape[1]} columns')
print(f'USA:    {len(usa):>6} rows  |  {usa.shape[1]} columns')
print(f'India:  {len(india):>6} rows  |  {india.shape[1]} columns')
print(f'Total:  {len(dubai)+len(usa)+len(india):>6} rows')

def missing_report(df, name):
    total = len(df)
    miss  = df.isnull().sum()
    pct   = (miss / total * 100).round(2)
    report = pd.DataFrame({'missing': miss, 'pct_%': pct})
    report = report[report['missing'] > 0].sort_values('missing', ascending=False)
    print(f'\n--- {name} ({total} rows) ---')
    print('  No missing values.' if report.empty else report.to_string())

missing_report(dubai, 'DUBAI')
missing_report(usa,   'USA')
missing_report(india, 'INDIA')

fig, axes = plt.subplots(1, 3, figsize=(15, 4))
for ax, (df, name, color) in zip(axes, [
    (dubai, 'Dubai', '#e07b54'), (usa, 'USA', '#5b8db8'), (india, 'India', '#6aaa64')
]):
    miss = (df.isnull().sum() / len(df) * 100)
    miss = miss[miss > 0].sort_values(ascending=True)
    if miss.empty:
        ax.text(0.5, 0.5, 'No missing\nvalues', ha='center', va='center', fontsize=13, transform=ax.transAxes)
        ax.set_title(name); ax.axis('off')
    else:
        miss.plot(kind='barh', ax=ax, color=color, edgecolor='white')
        ax.set_xlabel('% missing'); ax.set_title(f'{name} — missing values')
        ax.xaxis.set_major_formatter(mticker.PercentFormatter())
plt.tight_layout()
plt.savefig(os.path.join(OUT, 'missing_values.png'), bbox_inches='tight')
print('\n[saved] missing_values.png')

print('\n=== DUBAI — describe ===')
print(dubai[['lat','lng','polarity']].describe().round(4).to_string())
print('\n=== USA — describe ===')
print(usa[['latitude','longitude']].describe().round(4).to_string())
print('\n=== INDIA — describe ===')
print(india[['rating','average_price','average_delivery_time']].describe().round(4).to_string())
print(f'\nDuplicates — Dubai: {dubai.duplicated().sum()}  USA: {usa.duplicated().sum()}  India: {india.duplicated().sum()}')

top_cat = dubai['category'].value_counts().head(15)
fig, ax = plt.subplots(figsize=(12, 5))
top_cat.sort_values().plot(kind='barh', ax=ax, color='#e07b54', edgecolor='white')
ax.set_title('Dubai — Top 15 kategorií restaurací'); ax.set_xlabel('Počet restaurací')
for bar in ax.patches:
    ax.text(bar.get_width()+5, bar.get_y()+bar.get_height()/2, f'{int(bar.get_width())}', va='center', fontsize=9)
plt.tight_layout(); plt.savefig(os.path.join(OUT, 'dubai_categories.png'), bbox_inches='tight')
print('[saved] dubai_categories.png')

fig, axes = plt.subplots(1, 2, figsize=(13, 4))
dubai['polarity'].plot(kind='hist', bins=40, ax=axes[0], color='#e07b54', edgecolor='white')
axes[0].set_title('Dubai — distribuce polarity (sentimentu)')
axes[0].set_xlabel('Polarity score'); axes[0].set_ylabel('Počet restaurací')
pol_stats = dubai['polarity'].describe()
axes[1].axis('off')
stats_text = '\n'.join([f'{k}: {v:.3f}' for k,v in pol_stats.items()])
axes[1].text(0.1, 0.5, f'Statistiky polarity:\n\n{stats_text}', transform=axes[1].transAxes,
             fontsize=11, va='center', bbox=dict(boxstyle='round', facecolor='#fde8dc', alpha=0.6))
plt.tight_layout(); plt.savefig(os.path.join(OUT, 'dubai_polarity.png'), bbox_inches='tight')
neg = (dubai['polarity']<0).sum(); zero = (dubai['polarity']==0).sum(); pos = (dubai['polarity']>0).sum()
print(f'[saved] dubai_polarity.png  | neg={neg} ({neg/len(dubai)*100:.1f}%)  zero={zero}  pos={pos} ({pos/len(dubai)*100:.1f}%)')

fig, ax = plt.subplots(figsize=(10, 7))
sc = ax.scatter(dubai['lng'], dubai['lat'], c=dubai['polarity'], cmap='RdYlGn', s=4, alpha=0.5, vmin=-1, vmax=1)
plt.colorbar(sc, ax=ax, label='Polarity')
ax.set_title('Dubai — rozmístění restaurací (lat/lng), barva = polarity')
ax.set_xlabel('Longitude'); ax.set_ylabel('Latitude')
plt.tight_layout(); plt.savefig(os.path.join(OUT, 'dubai_geo.png'), bbox_inches='tight')
print('[saved] dubai_geo.png')

top_chains = usa['name'].value_counts().head(20)
fig, ax = plt.subplots(figsize=(12, 6))
top_chains.sort_values().plot(kind='barh', ax=ax, color='#5b8db8', edgecolor='white')
ax.set_title('USA — Top 20 fast food řetězců (počet poboček)'); ax.set_xlabel('Počet poboček')
for bar in ax.patches:
    ax.text(bar.get_width()+2, bar.get_y()+bar.get_height()/2, f'{int(bar.get_width())}', va='center', fontsize=8)
plt.tight_layout(); plt.savefig(os.path.join(OUT, 'usa_chains.png'), bbox_inches='tight')
print(f'[saved] usa_chains.png  | unique chains: {usa["name"].nunique()}')

top_states = usa['province'].value_counts().head(15)
fig, ax = plt.subplots(figsize=(12, 5))
top_states.sort_values().plot(kind='barh', ax=ax, color='#3a6b96', edgecolor='white')
ax.set_title('USA — Top 15 států podle počtu fast food poboček'); ax.set_xlabel('Počet poboček')
for bar in ax.patches:
    ax.text(bar.get_width()+2, bar.get_y()+bar.get_height()/2, f'{int(bar.get_width())}', va='center', fontsize=9)
plt.tight_layout(); plt.savefig(os.path.join(OUT, 'usa_states.png'), bbox_inches='tight')
print('[saved] usa_states.png')

top5_states = usa['province'].value_counts().head(5).index
top5_chains = usa['name'].value_counts().head(8).index
pivot = (usa[usa['province'].isin(top5_states) & usa['name'].isin(top5_chains)]
         .groupby(['province','name']).size().unstack(fill_value=0))
pivot.plot(kind='bar', stacked=True, figsize=(12, 5), colormap='tab10', edgecolor='white')
plt.title('USA — top 8 řetězců v top 5 státech'); plt.xlabel('Stát'); plt.ylabel('Počet poboček')
plt.xticks(rotation=0); plt.legend(bbox_to_anchor=(1.01,1), loc='upper left', fontsize=9)
plt.tight_layout(); plt.savefig(os.path.join(OUT, 'usa_chains_by_state.png'), bbox_inches='tight')
print('[saved] usa_chains_by_state.png')

fig, axes = plt.subplots(1, 2, figsize=(13, 4))
india['rating'].plot(kind='hist', bins=30, ax=axes[0], color='#6aaa64', edgecolor='white')
axes[0].set_title('India — distribuce hodnocení (rating)'); axes[0].set_xlabel('Rating'); axes[0].set_ylabel('Počet')
axes[0].axvline(india['rating'].mean(), color='darkgreen', lw=1.5, linestyle='--', label=f'Mean: {india["rating"].mean():.2f}')
axes[0].legend()
india['average_price'].plot(kind='hist', bins=40, ax=axes[1], color='#3d8c38', edgecolor='white')
axes[1].set_title('India — distribuce průměrné ceny (INR)'); axes[1].set_xlabel('Průměrná cena (INR)')
axes[1].axvline(india['average_price'].mean(), color='darkgreen', lw=1.5, linestyle='--', label=f'Mean: {india["average_price"].mean():.0f} INR')
axes[1].legend()
plt.tight_layout(); plt.savefig(os.path.join(OUT, 'india_rating_price.png'), bbox_inches='tight')
print('[saved] india_rating_price.png')

fig, ax = plt.subplots(figsize=(10, 4))
india['average_delivery_time'].plot(kind='hist', bins=35, ax=ax, color='#4daf4a', edgecolor='white')
ax.axvline(india['average_delivery_time'].mean(), color='darkgreen', lw=1.5, linestyle='--',
           label=f'Mean: {india["average_delivery_time"].mean():.1f} min')
ax.axvline(india['average_delivery_time'].median(), color='olive', lw=1.5, linestyle=':',
           label=f'Median: {india["average_delivery_time"].median():.1f} min')
ax.set_title('India — distribuce průměrné doby dovozu (minuty)'); ax.set_xlabel('min'); ax.set_ylabel('Počet')
ax.legend(); plt.tight_layout(); plt.savefig(os.path.join(OUT, 'india_delivery_time.png'), bbox_inches='tight')
print('[saved] india_delivery_time.png')

top_cities = india['location'].value_counts().head(15)
fig, ax = plt.subplots(figsize=(12, 5))
top_cities.sort_values().plot(kind='barh', ax=ax, color='#6aaa64', edgecolor='white')
ax.set_title('India — Top 15 měst podle počtu restaurací'); ax.set_xlabel('Počet restaurací')
for bar in ax.patches:
    ax.text(bar.get_width()+5, bar.get_y()+bar.get_height()/2, f'{int(bar.get_width())}', va='center', fontsize=9)
plt.tight_layout(); plt.savefig(os.path.join(OUT, 'india_cities.png'), bbox_inches='tight')
print(f'[saved] india_cities.png  | unique cities: {india["location"].nunique()}')

cuisine_cols   = ['south_indian_or_not','north_indian_or_not','fast_food_or_not','street_food','biryani_or_not','bakery_or_not']
cuisine_labels = ['South Indian','North Indian','Fast Food','Street Food','Biryani','Bakery']
cuisine_counts = india[cuisine_cols].sum().values
fig, ax = plt.subplots(figsize=(10, 4))
bars = ax.bar(cuisine_labels, cuisine_counts, color='#6aaa64', edgecolor='white')
for bar, val in zip(bars, cuisine_counts):
    ax.text(bar.get_x()+bar.get_width()/2, bar.get_height()+50,
            f'{int(val):,}\n({val/len(india)*100:.1f}%)', ha='center', va='bottom', fontsize=9)
ax.set_title('India — počet restaurací podle typu kuchyně'); ax.set_ylabel('Počet')
plt.tight_layout(); plt.savefig(os.path.join(OUT, 'india_cuisine_types.png'), bbox_inches='tight')
print('[saved] india_cuisine_types.png')

sample = india.sample(3000, random_state=42)
fig, ax = plt.subplots(figsize=(9, 6))
ax.scatter(sample['average_price'], sample['rating'], alpha=0.25, s=12, color='#6aaa64')
z = np.polyfit(india['average_price'], india['rating'], 1)
p = np.poly1d(z)
x_line = np.linspace(india['average_price'].min(), india['average_price'].max(), 200)
ax.plot(x_line, p(x_line), color='darkgreen', lw=1.5, linestyle='--', label=f'Trend (slope={z[0]:.5f})')
ax.set_title('India — závislost hodnocení na ceně'); ax.set_xlabel('Průměrná cena (INR)'); ax.set_ylabel('Hodnocení')
ax.legend(); plt.tight_layout(); plt.savefig(os.path.join(OUT, 'india_rating_vs_price.png'), bbox_inches='tight')
corr = india['average_price'].corr(india['rating'])
print(f'[saved] india_rating_vs_price.png  | Pearson corr: {corr:.4f}')

sizes = {'Dubai': len(dubai), 'USA': len(usa), 'India': len(india)}
colors = ['#e07b54','#5b8db8','#6aaa64']
fig, axes = plt.subplots(1, 2, figsize=(13, 5))
axes[0].bar(sizes.keys(), sizes.values(), color=colors, edgecolor='white')
for i,(k,v) in enumerate(sizes.items()):
    axes[0].text(i, v+200, f'{v:,}', ha='center', fontsize=11, fontweight='bold')
axes[0].set_title('Počet záznamů v každém datasetu'); axes[0].set_ylabel('Počet')
axes[1].pie(sizes.values(), labels=sizes.keys(), colors=colors,
            autopct='%1.1f%%', startangle=90, wedgeprops=dict(edgecolor='white', linewidth=2))
axes[1].set_title('Podíl datasetů')
plt.tight_layout(); plt.savefig(os.path.join(OUT, 'dataset_sizes.png'), bbox_inches='tight')
print('[saved] dataset_sizes.png')

summary = pd.DataFrame({
    'Dataset':       ['Dubai','USA','India'],
    'Rows':          [len(dubai), len(usa), len(india)],
    'Columns':       [dubai.shape[1], usa.shape[1], india.shape[1]],
    'Missing cells': [dubai.isnull().sum().sum(), usa.isnull().sum().sum(), india.isnull().sum().sum()],
    'Duplicates':    [dubai.duplicated().sum(), usa.duplicated().sum(), india.duplicated().sum()],
    'Unique names':  [dubai['name'].nunique(), usa['name'].nunique(), india['restaurant_name'].nunique()],
}).set_index('Dataset')
print('\n=== Summary ===')
print(summary.to_string())

try:
    from pymongo import MongoClient
    client = MongoClient('mongodb://admin:RestCluster2024!@localhost:27017/?authSource=admin',
                         serverSelectionTimeoutMS=4000)
    client.admin.command('ping')
    db  = client['restaurants']
    cfg = client['config']

    collections = ['dubai_restaurants','usa_fastfood','indian_restaurants']
    counts = {c: db[c].estimated_document_count() for c in collections}
    print('\n=== MongoDB document counts ===')
    for c,n in counts.items():
        print(f'  {c}: {n:,}')

    pipeline = [{'$group':{'_id':'$shard','chunks':{'$sum':1}}},{'$sort':{'_id':1}}]
    chunk_dist = list(cfg['chunks'].aggregate(pipeline))
    if chunk_dist:
        print('\n=== Chunk distribution ===')
        for d in chunk_dist:
            print(f'  {d["_id"]}: {d["chunks"]} chunks')

        fig, ax = plt.subplots(figsize=(8, 4))
        shards = [d['_id'] for d in chunk_dist]
        chunks = [d['chunks'] for d in chunk_dist]
        ax.bar(shards, chunks, color='#7b68ee', edgecolor='white')
        for i,v in enumerate(chunks):
            ax.text(i, v+0.1, str(v), ha='center', fontsize=11, fontweight='bold')
        ax.set_title('Distribuce chunků napříč shardy'); ax.set_ylabel('Počet chunků')
        plt.tight_layout(); plt.savefig(os.path.join(OUT, 'mongo_chunk_distribution.png'), bbox_inches='tight')
        print('[saved] mongo_chunk_distribution.png')

    stats_rows = []
    for col in collections:
        s = db.command('collStats', col)
        stats_rows.append({'collection': col,
                           'count': s.get('count',0),
                           'dataSize_MB': round(s.get('size',0)/1024**2, 2),
                           'storageSize_MB': round(s.get('storageSize',0)/1024**2, 2),
                           'avgObjSize_B': round(s.get('avgObjSize',0), 1),
                           'nindexes': s.get('nindexes',0)})
    stats_df = pd.DataFrame(stats_rows).set_index('collection')
    print('\n=== Collection stats ===')
    print(stats_df.to_string())
    client.close()
except Exception as e:
    print(f'\n[info] MongoDB not available: {e}')

print('\n✓ Analysis complete. All charts saved as PNG files in Data/')
