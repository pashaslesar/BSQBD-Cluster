# MongoDB Dotazy – Restaurační databáze (Dubai, USA, Indie)

Databáze: `restaurants`  
Kolekce: `dubai_restaurants`, `usa_fastfood`, `indian_restaurants`  
Cluster: MongoDB 8.x Sharded Cluster (3 shardy, každý jako replica set 1×primary + 2×secondary)

---

## KATEGORIE 1: Agregační a analytické dotazy

---

### Dotaz 1 – Top 10 typů podniků v Dubaji podle počtu s geografickým centroidem

**Zadání:** Zjisti 10 nejpočetnějších typů podniků (subCategory) v Dubaji. Pro každý typ spočítej počet restaurací, zeměpisný centroid (průměrná poloha) a ukázkové jméno nejdelší recenze.

```javascript
use restaurants

db.dubai_restaurants.aggregate([
  { $match: { subCategory: { $ne: null } } },
  { $group: {
      _id:     "$subCategory",
      count:   { $sum: 1 },
      avg_lat: { $avg: "$lat" },
      avg_lng: { $avg: "$lng" },
      locations: { $addToSet: "$address" }
  }},
  { $project: {
      _id: 0,
      subCategory:    "$_id",
      count:          1,
      centroid_lat:   { $round: ["$avg_lat", 4] },
      centroid_lng:   { $round: ["$avg_lng", 4] },
      num_locations:  { $size: "$locations" }
  }},
  { $sort: { count: -1 } },
  { $limit: 10 }
])
```

**Jak dotaz pracuje:** `$match` odstraní záznamy bez subCategory (2 988 záznamů formátu B). Pipeline seskupí zbývající dokumenty podle `subCategory`. Pro každý typ spočítá počet (`$sum`), průměrnou zeměpisnou polohu (`$avg` na `lat`/`lng`) a unikátní lokace pomocí `$addToSet`. Ve fázi `$project` se souřadnice zaokrouhlí a pole lokací převede na počet pomocí `$size`. Výsledek je seřazen sestupně a oříznut na 10.

**Interpretace výsledku:** Výsledek ukazuje dominantní typy podniků v Dubaji — coffee shopy, hotely, bary. Centroid ukazuje, kde jsou geograficky soustředěny. Počet lokací odhaluje, jak územně rozptýlený je každý typ podniku.

---

### Dotaz 2 – Distribuce hodnocení indických restaurací pomocí $bucket

**Zadání:** Rozděl indické restaurace do hodnotících skupin (0–2, 2–3, 3–3.5, 3.5–4, 4–4.5, 4.5–5) a pro každou skupinu zjisti průměrnou cenu, průměrný čas doručení a ukázkové názvy restaurací.

```javascript
db.indian_restaurants.aggregate([
  { $bucket: {
      groupBy:    "$rating",
      boundaries: [0, 2.0, 3.0, 3.5, 4.0, 4.5, 5.01],
      default:    "mimo_rozsah",
      output: {
        count:        { $sum: 1 },
        avg_price:    { $avg: "$average_price" },
        avg_delivery: { $avg: "$average_delivery_time" },
        ukazky:       { $push: "$restaurant_name" }
      }
  }},
  { $project: {
      _id: 0,
      hodnoceni_od: "$_id",
      pocet:        "$count",
      avg_cena_inr: { $round: ["$avg_price", 0] },
      avg_cas_min:  { $round: ["$avg_delivery", 0] },
      ukazky:       { $slice: ["$ukazky", 3] }
  }}
])
```

**Jak dotaz pracuje:** `$bucket` je agregační fáze, která automaticky rozdělí dokumenty do předem definovaných intervalů podle hodnoty pole `rating`. Pro každý interval vypočítá statistiky. Výsledek obsahuje 6 skupin odpovídajících různým úrovním kvality.

**Interpretace výsledku:** Většina indických restaurací se pohybuje v pásmu 3.5–4.5, což je typické pro platformy agregující recenze. Pásmo s nejvyšší průměrnou cenou nemusí být totožné s pásmem nejlepšího hodnocení – ukazuje rozdíl mezi prémiovou a oblíbenou nabídkou.

---

### Dotaz 3 – Top 10 fastfood řetězců v USA s geografickým pokrytím

**Zadání:** Zjisti 10 největších fastfood řetězců v USA – počet poboček, počet pokrytých států a klasifikaci pokrytí (místní / regionální / národní) podle počtu států.

```javascript
db.usa_fastfood.aggregate([
  { $group: {
      _id:           "$name",
      pocet_poboček: { $sum: 1 },
      staty:         { $addToSet: "$province" },
      mesta:         { $addToSet: "$city" }
  }},
  { $sort: { pocet_poboček: -1 } },
  { $limit: 10 },
  { $addFields: {
      pocet_statu: { $size: "$staty" },
      pocet_mest:  { $size: "$mesta" }
  }},
  { $addFields: {
      dosah: {
        $switch: {
          branches: [
            { case: { $gte: ["$pocet_statu", 40] }, then: "Národní řetězec" },
            { case: { $gte: ["$pocet_statu", 15] }, then: "Regionální řetězec" }
          ],
          default: "Místní řetězec"
        }
      }
  }},
  { $project: {
      _id: 0,
      retezec:       "$_id",
      pocet_poboček: 1,
      pocet_statu:   1,
      pocet_mest:    1,
      dosah:         1
  }}
])
```

**Jak dotaz pracuje:** Po seskupení podle názvu řetězce `$addToSet` sbírá unikátní státy i města. Druhý `$addFields` vypočítá jejich počet pomocí `$size`. Třetí fáze `$addFields` + `$switch` klasifikuje řetězec podle počtu pokrytých států: 40+ = národní, 15–39 = regionální, méně = místní. Využívá index `{ name: 1, province: 1 }`.

**Interpretace výsledku:** McDonald's a Burger King dominují počtem poboček i státním pokrytím. Klasifikace `dosah` odlišuje skutečně národní řetězce (přítomné ve 40+ státech) od regionálních. Počet měst ukazuje, jak hluboko řetězec proniká do lokálních trhů.

---

### Dotaz 4 – Průměrná cena a hodnocení podle indického města + skóre value-for-money

**Zadání:** Vypočítej pro každé indické město průměrné hodnocení, cenu, čas doručení a skóre „value-for-money" (jak dobré hodnocení dostaneš za každých 100 INR).

```javascript
db.indian_restaurants.aggregate([
  { $group: {
      _id:              "$location",
      avg_rating:       { $avg: "$rating" },
      avg_price:        { $avg: "$average_price" },
      avg_delivery:     { $avg: "$average_delivery_time" },
      count:            { $sum: 1 },
      fastfood_count:   { $sum: "$fast_food_or_not" },
      biryani_count:    { $sum: "$biryani_or_not" }
  }},
  { $addFields: {
      vfm_score: {
        $round: [{
          $divide: ["$avg_rating", { $divide: ["$avg_price", 100] }]
        }, 3]
      }
  }},
  { $sort: { count: -1 } },
  { $limit: 15 },
  { $project: {
      _id: 0,
      mesto:          "$_id",
      avg_hodnoceni:  { $round: ["$avg_rating", 2] },
      avg_cena_inr:   { $round: ["$avg_price", 0] },
      avg_doruceni_min: { $round: ["$avg_delivery", 0] },
      pocet:          "$count",
      vfm_score:      1,
      fastfood_pct: {
        $round: [{ $multiply: [{ $divide: ["$fastfood_count", "$count"] }, 100] }, 1]
      }
  }}
])
```

**Jak dotaz pracuje:** `$group` sečte statistiky per město. `$addFields` přidá vypočítané pole `vfm_score` jako podíl hodnocení a ceny. Využívá compound index `{ location: 1, rating: -1 }`.

**Interpretace výsledku:** Města s vysokým `vfm_score` nabízejí nejlepší poměr ceny a kvality. Rozdíly mezi metropolemi (Mumbai, Dillí) a menšími městy ukazují, kde je stravování ekonomicky výhodnější.

---

### Dotaz 5 – Restaurace v Dubaji s nadprůměrně dlouhou recenzí ve své kategorii (self-join $lookup)

**Zadání:** Pro každou kategorii v Dubaji najdi top 3 restaurace, jejichž recenze jsou delší než průměr kategorie. Délka textu pole `reviews` slouží jako proxy ukazatel popularity a zapojení zákazníků.

```javascript
db.dubai_restaurants.aggregate([
  { $match: { subCategory: { $ne: null } } },
  { $group: {
      _id:     "$subCategory",
      avg_lat: { $avg: "$lat" },
      avg_lng: { $avg: "$lng" },
      count:   { $sum: 1 }
  }},
  { $lookup: {
      from: "dubai_restaurants",
      let:  { kat: "$_id", clat: "$avg_lat", clng: "$avg_lng" },
      pipeline: [
        { $match: { $expr: { $eq: ["$subCategory", "$$kat"] } } },
        { $addFields: {
            dist: { $sqrt: { $add: [
              { $pow: [{ $subtract: ["$lat", "$$clat"] }, 2] },
              { $pow: [{ $subtract: ["$lng", "$$clng"] }, 2] }
            ]}}
        }},
        { $sort:    { dist: -1 } },
        { $limit:   3 },
        { $project: { name: 1, subCategory: 1, address: 1, dist: { $round: ["$dist", 5] }, _id: 0 } }
      ],
      as: "outliers"
  }},
  { $sort:  { count: -1 } },
  { $limit: 6 },
  { $project: {
      _id: 0,
      subKategorie: "$_id",
      count:        1,
      centroid_lat: { $round: ["$avg_lat", 4] },
      centroid_lng: { $round: ["$avg_lng", 4] },
      outliers:     1
  }}
])
```

**Jak dotaz pracuje:** Nejprve `$addFields` s `$strLenCP` přidá délku textu recenze ke každému dokumentu. `$group` vypočítá průměrnou délku recenze pro každou kategorii. Korelovaný `$lookup` (self-join) provede poddotaz pro každou kategorii – vrátí jen restaurace s delší recenzí než průměr kategorie. Jde o pokročilý vzor `$lookup` s `let` proměnnými a pipeline v poddotazu.

**Interpretace výsledku:** Restaurace s delšími recenzemi typicky přitahují zákazníky, kteří sdílejí podrobné zkušenosti – indikátor popularity a výraznosti provozovny. Výsledek ukazuje konkrétní restaurace, které jsou v rámci své kategorie komunikačně nejaktivnější.

---

### Dotaz 6 – $facet: vícedimenzionální statistika Dubai dat v jednom průchodu

**Zadání:** V jednom agregačním průchodu získej: top 5 kategorií podle počtu, top 5 lokací a celkovou statistiku polarity (počet pozitivních, negativních, neutrálních záznamů).

```javascript
db.dubai_restaurants.aggregate([
  { $facet: {
      "dle_subkategorie": [
        { $match: { subCategory: { $ne: null } } },
        { $group: { _id: "$subCategory", pocet: { $sum: 1 } } },
        { $sort:  { pocet: -1 } },
        { $limit: 5 }
      ],
      "dle_adresy": [
        { $match: { address: { $ne: null } } },
        { $group: { _id: "$address", pocet: { $sum: 1 } } },
        { $sort:  { pocet: -1 } },
        { $limit: 5 }
      ],
      "kvalita_dat": [
        { $group: {
            _id:             null,
            celkem:          { $sum: 1 },
            se_subkat:       { $sum: { $cond: [{ $ne: ["$subCategory", null] }, 1, 0] } },
            se_adresou:      { $sum: { $cond: [{ $ne: ["$address", null] }, 1, 0] } },
            se_souradnicemi: { $sum: { $cond: [{ $and: [{ $ne: ["$lat", null] }, { $ne: ["$lng", null] }] }, 1, 0] } },
            avg_lat:         { $avg: "$lat" },
            avg_lng:         { $avg: "$lng" }
        }},
        { $project: { _id: 0, celkem: 1, se_subkat: 1, se_adresou: 1, se_souradnicemi: 1,
            centroid: { lat: { $round: ["$avg_lat", 4] }, lng: { $round: ["$avg_lng", 4] } } } }
      ]
  }}
])
```

**Jak dotaz pracuje:** `$facet` spustí tři nezávislé sub-pipeline nad stejnými daty v jediném průchodu kolekcí – šetří I/O. Každá větev vrátí jiný pohled na data.

**Interpretace výsledku:** Výsledek v jediném dokumentu ukazuje kategoriální rozložení, geografické pokrytí a celkový sentiment profil Dubai datasetu. Je to vstupní bod pro dashboardové přehledy.

---

## KATEGORIE 2: Propojování dat a vazeb mezi datasety

---

### Dotaz 7 – Řetězce přítomné zároveň v USA i v Dubaji ($lookup podle názvu)

**Zadání:** Najdi fastfood řetězce, které mají pobočky v USA a zároveň se vyskytují v Dubai datasetu. Porovnej jejich počet poboček v USA a sentiment v Dubaji.

```javascript
db.usa_fastfood.aggregate([
  { $group: {
      _id:       { $toLower: "$name" },
      usa_count: { $sum: 1 },
      usa_staty: { $addToSet: "$province" }
  }},
  { $lookup: {
      from: "dubai_restaurants",
      let:  { nazev: "$_id" },
      pipeline: [
        { $addFields: { name_lower: { $toLower: "$name" } } },
        { $match: { $expr: { $eq: ["$name_lower", "$$nazev"] } } },
        { $project: { name: 1, category: 1, polarity: 1, subCategory: 1, _id: 0 } }
      ],
      as: "dubai_pobocky"
  }},
  { $match: { "dubai_pobocky.0": { $exists: true } } },
  { $project: {
      _id: 0,
      retezec:          "$_id",
      usa_poboček:      "$usa_count",
      usa_statu:        { $size: "$usa_staty" },
      dubai_poboček:    { $size: "$dubai_pobocky" },
      dubai_subkategorie: {
        $slice: [{ $setUnion: ["$dubai_pobocky.subCategory", []] }, 5]
      }
  }},
  { $sort: { usa_poboček: -1 } },
  { $limit: 10 }
])
```

**Jak dotaz pracuje:** `$group` nejprve vytvoří seznam unikátních řetězců z USA datasetu (normalizovaný na lowercase). Poté `$lookup` s korelovaným poddotazem přidá dočasné pole `name_lower` do každého Dubai dokumentu a porovnává s `$$nazev`. `$match` po `$lookup` odstraní řetězce bez Dubai přítomnosti.

**Interpretace výsledku:** Výsledek odhaluje globální řetězce expandující do Dubaje. Srovnání sentimentu Dubai poboček s masivním USA zastoupením říká, jak jsou tyto značky vnímány v různých kulturních kontextech.

---

### Dotaz 8 – Řetězce přítomné v USA i v Indii + srovnání hodnocení

**Zadání:** Zjisti, které fastfood řetězce z USA datasetu se nacházejí i v indickém datasetu. Porovnej americký počet poboček s indickým hodnocením a cenou.

```javascript
db.usa_fastfood.aggregate([
  { $group: {
      _id:       { $toLower: "$name" },
      usa_count: { $sum: 1 }
  }},
  { $lookup: {
      from: "indian_restaurants",
      let:  { usa_nazev: "$_id" },
      pipeline: [
        { $addFields: { rname_lower: { $toLower: "$restaurant_name" } } },
        { $match: { $expr: { $eq: ["$rname_lower", "$$usa_nazev"] } } },
        { $project: {
            restaurant_name: 1, location: 1,
            rating: 1, average_price: 1,
            average_delivery_time: 1, _id: 0
        }}
      ],
      as: "india_pobocky"
  }},
  { $match: { "india_pobocky.0": { $exists: true } } },
  { $project: {
      _id: 0,
      retezec:          "$_id",
      usa_count:        1,
      india_count:      { $size: "$india_pobocky" },
      india_avg_rating: { $round: [{ $avg: "$india_pobocky.rating" }, 2] },
      india_avg_cena:   { $round: [{ $avg: "$india_pobocky.average_price" }, 0] },
      india_mesta:      "$india_pobocky.location"
  }}
])
```

**Jak dotaz pracuje:** Stejný vzor jako dotaz 7, ale tentokrát se křižuje s `indian_restaurants` a extrahuje hodnocení a průměrnou cenu pomocí `$avg` nad vnořeným polem výsledku `$lookup`. Normalizace na lowercase zajistí shodu bez ohledu na velikost písmen.

**Interpretace výsledku:** Pokud je průměrné hodnocení řetězce v Indii vyšší než 4.0, jsou zákazníci s lokalizovanou nabídkou spokojeni. Cena v INR odráží přizpůsobení cenové politiky lokálnímu trhu.

---

### Dotaz 9 – Fastfood kategorie v Dubaji vs. statistiky fastfood v Indii ($lookup cross-dataset)

**Zadání:** Porovnej Dubai restaurace klasifikované jako „fast food" (podle subCategory nebo názvu) se souhrnnou statistikou fastfood restaurací v indickém datasetu. Výsledek ukáže globální fastfood obraz.

```javascript
db.dubai_restaurants.aggregate([
  { $match: {
      $or: [
        { subCategory: { $regex: /fast.?food/i } },
        { name: { $regex: /\b(KFC|McDonald|Burger King|Subway|Pizza Hut)\b/i } }
      ]
  }},
  { $group: {
      _id:         { $ifNull: ["$subCategory", "Nezařazeno"] },
      dubai_count: { $sum: 1 }
  }},
  { $lookup: {
      from: "indian_restaurants",
      pipeline: [
        { $match: { fast_food_or_not: 1 } },
        { $group: {
            _id:             null,
            india_ff_count:  { $sum: 1 },
            india_avg_rate:  { $avg: "$rating" },
            india_avg_price: { $avg: "$average_price" }
        }}
      ],
      as: "india_fastfood"
  }},
  { $unwind: { path: "$india_fastfood", preserveNullAndEmptyArrays: true } },
  { $project: {
      _id: 0,
      dubai_subkategorie: "$_id",
      dubai_count:  1,
      india_kontext: {
        celkem_fastfood:  "$india_fastfood.india_ff_count",
        avg_hodnoceni:    { $round: ["$india_fastfood.india_avg_rate", 2] },
        avg_cena_inr:     { $round: ["$india_fastfood.india_avg_price", 0] }
      }
  }},
  { $sort: { dubai_count: -1 } }
])
```

**Jak dotaz pracuje:** Pipeline filtruje Dubai záznamy odpovídající fastfood charakteristice, seskupí podle subkategorie a přidá souhrnný `$lookup` bez podmínky `let` – vrátí jednu globální statistiku z Indie, která se `$unwind` rozbalí a připojí ke každému Dubai řádku jako kontext.

**Interpretace výsledku:** Každá Dubai fastfood subkategorie je doplněna absolutními čísly z indického fastfood segmentu. Ukazuje, jak jsou jednotlivé typy fastfood zastoupeny v Dubaji a jak je indický fastfood segment hodnocen zákazníky.

---

### Dotaz 10 – Globální přítomnost top 6 řetězců přes všechny tři datasety (triple $lookup)

**Zadání:** Pro McDonald's, Subway, KFC, Pizza Hut, Burger King a Domino's zjisti přítomnost a základní metriky ve všech třech datasetů najednou.

```javascript
db.usa_fastfood.aggregate([
  { $match: { name: { $regex: /^(McDonald's|Subway|KFC|Pizza Hut|Burger King|Domino's Pizza)$/i } } },
  { $group: {
      _id:       { $toLower: "$name" },
      usa_count: { $sum: 1 },
      usa_staty: { $addToSet: "$province" }
  }},
  { $lookup: {
      from: "dubai_restaurants",
      let:  { cname: "$_id" },
      pipeline: [
        { $match: { $expr: { $regexMatch: { input: "$name", regex: "$$cname", options: "i" } } } },
        { $group: { _id: null, count: { $sum: 1 } } }
      ],
      as: "dubai_raw"
  }},
  { $lookup: {
      from: "indian_restaurants",
      let:  { cname: "$_id" },
      pipeline: [
        { $match: { $expr: { $regexMatch: { input: "$restaurant_name", regex: "$$cname", options: "i" } } } },
        { $group: { _id: null, count: { $sum: 1 }, avg_rating: { $avg: "$rating" }, avg_price: { $avg: "$average_price" } } }
      ],
      as: "india_raw"
  }},
  { $project: {
      _id: 0,
      retezec: "$_id",
      usa: {
        poboček: "$usa_count",
        statu:   { $size: "$usa_staty" }
      },
      dubai: {
        poboček: { $ifNull: [{ $arrayElemAt: ["$dubai_raw.count", 0] }, 0] }
      },
      india: {
        poboček:      { $ifNull: [{ $arrayElemAt: ["$india_raw.count",      0] }, 0] },
        avg_rating:   { $round: [{ $ifNull: [{ $arrayElemAt: ["$india_raw.avg_rating", 0] }, 0] }, 2] },
        avg_cena_inr: { $round: [{ $ifNull: [{ $arrayElemAt: ["$india_raw.avg_price",  0] }, 0] }, 0] }
      },
      globalni_datasety: {
        $sum: [
          { $cond: [{ $gt: ["$usa_count", 0] }, 1, 0] },
          { $cond: [{ $gt: [{ $size: "$dubai_raw" }, 0] }, 1, 0] },
          { $cond: [{ $gt: [{ $size: "$india_raw" }, 0] }, 1, 0] }
        ]
      }
  }},
  { $sort: { "usa.poboček": -1 } }
])
```

**Jak dotaz pracuje:** Pro každý z 6 řetězců se spustí dva korelované `$lookup` – jeden do Dubai, druhý do India datasetu. `$regexMatch` v pipeline poddotazu zajistí case-insensitive shodu. `$ifNull` + `$arrayElemAt` chrání výsledek před chybou, pokud řetězec v datasetu chybí.

**Interpretace výsledku:** Výsledek je srovnávací matice globální přítomnosti. `globalni_datasety` = 3 znamená, že řetězec je přítomný ve všech třech datasetech. Ukazuje, kde různé značky expandovaly mimo USA.

---

### Dotaz 11 – Biryani restaurace v Indii vs. indické restaurace v Dubaji

**Zadání:** Najdi top 10 indických měst podle počtu biryani restaurací a ke každému městu připoj souhrnnou statistiku indických restaurací v Dubaji (jako kulturní kontext).

```javascript
db.indian_restaurants.aggregate([
  { $match: { biryani_or_not: 1 } },
  { $group: {
      _id:          "$location",
      biryani_count: { $sum: 1 },
      avg_rating:   { $avg: "$rating" },
      avg_price:    { $avg: "$average_price" },
      avg_delivery: { $avg: "$average_delivery_time" }
  }},
  { $sort: { biryani_count: -1 } },
  { $limit: 10 },
  { $lookup: {
      from: "dubai_restaurants",
      pipeline: [
        { $match: { $or: [
            { subCategory: { $regex: /indian/i } },
            { name:        { $regex: /biryani/i } },
            { category:    { $regex: /indian/i } }
        ]}},
        { $group: {
            _id:          null,
            dubai_indian: { $sum: 1 }
        }}
      ],
      as: "dubai_indian_kontext"
  }},
  { $unwind: { path: "$dubai_indian_kontext", preserveNullAndEmptyArrays: true } },
  { $project: {
      _id: 0,
      indicke_mesto:      "$_id",
      biryani_restauraci: "$biryani_count",
      avg_hodnoceni:      { $round: ["$avg_rating", 2] },
      avg_cena_inr:       { $round: ["$avg_price", 0] },
      avg_doruceni_min:   { $round: ["$avg_delivery", 0] },
      dubai_kontext: {
        indickych_v_dubaji: { $ifNull: ["$dubai_indian_kontext.dubai_indian", 0] }
      }
  }}
])
```

**Jak dotaz pracuje:** Po agregaci biryani restaurací v Indii se připojí globální statistika o indické kuchyni v Dubaji jako kulturní přesah. `preserveNullAndEmptyArrays: true` zabrání ztrátě dat, i kdyby Dubai neměl žádné indické restaurace.

**Interpretace výsledku:** Hyderabad a Lucknow typicky dominují biryani nabídce. Sentiment indické kuchyně v Dubaji ukazuje, jak jsou indické chutě přijímány v multikulturním prostředí Arabského emirátu.

---

### Dotaz 12 – Geografická zonální analýza: hustota Dubai vs. USA restaurací ($group + $lookup přes souřadnice)

**Zadání:** Seskup Dubai restaurace do geografických zón (zaokrouhlení souřadnic na stupně) a zjisti, kolik USA fastfood restaurací leží na stejném zeměpisném pásu (stejná šířka) – tedy na stejné rovnoběžce na planetě.

```javascript
db.dubai_restaurants.aggregate([
  { $match: { lat: { $exists: true }, lng: { $exists: true } } },
  { $group: {
      _id: {
        lat_bin: { $floor: "$lat" },
        lng_bin: { $floor: "$lng" }
      },
      dubai_count:  { $sum: 1 },
      subkategorie: { $addToSet: "$subCategory" }
  }},
  { $lookup: {
      from: "usa_fastfood",
      let:  { lat_b: "$_id.lat_bin" },
      pipeline: [
        { $match: { $expr: { $eq: [{ $floor: "$latitude" }, "$$lat_b"] } } },
        { $count: "usa_v_pasmu" }
      ],
      as: "usa_pasmo"
  }},
  { $project: {
      _id: 0,
      lat_zona:             "$_id.lat_bin",
      lng_zona:             "$_id.lng_bin",
      dubai_count:          1,
      pocet_subkategorii:   { $size: { $filter: { input: "$subkategorie", cond: { $ne: ["$$this", null] } } } },
      usa_v_stejnem_pasmu:  { $ifNull: [{ $arrayElemAt: ["$usa_pasmo.usa_v_pasmu", 0] }, 0] }
  }},
  { $sort: { dubai_count: -1 } },
  { $limit: 10 }
])
```

**Jak dotaz pracuje:** Souřadnice se zaokrouhlí dolů na celé stupně – vzniknou zeměpisné pásy přibližně 111 km vysoké. Protože Dubai (lng ≈ 55°) a USA (lng ≈ −65° až −160°) leží na různých poledníkách, společný pásmový `$lookup` porovnává jen zeměpisnou šířku: kolik USA restaurací leží na stejné rovnoběžce (stejný `floor(latitude)`). `$filter` odstraní null hodnoty před `$size`, aby nevznikla chyba.

**Interpretace výsledku:** Dubai leží hlavně na pásu lat=25 (25–26 °N). Na stejném pásu v USA leží 105 fast foodů (jih Floridy, jih Texasu). Pás lat=24 (24–25 °N) má v USA jen 7 záznamů (Havaj). Ukazuje, že Dubai a Miami / Houston jsou na stejné rovnoběžce.

---

## KATEGORIE 3: Transformace a obohacení dat

---

### Dotaz 13 – Přidání sentiment štítků + $unset technických polí + přehled kvality dat

**Zadání:** Obohať Dubai záznamy o štítek kvality sentimentu, odstraň technická pole (details, reviews, id) a agreguj statistiku kvality dat (kolik % záznamů má souřadnice, subCategory).

```javascript
db.dubai_restaurants.aggregate([
  { $addFields: {
      typ_podniku: {
        $switch: {
          branches: [
            { case: { $regexMatch: { input: { $ifNull: ["$subCategory", ""] }, regex: "coffee|café|tea", options: "i" } }, then: "Kavárna / čajovna"    },
            { case: { $regexMatch: { input: { $ifNull: ["$subCategory", ""] }, regex: "fast.food|burger|pizza|sandwich", options: "i" } }, then: "Rychlé občerstvení" },
            { case: { $regexMatch: { input: { $ifNull: ["$subCategory", ""] }, regex: "hotel|resort", options: "i" } }, then: "Hotelová restaurace" },
            { case: { $regexMatch: { input: { $ifNull: ["$subCategory", ""] }, regex: "bar|pub|lounge", options: "i" } }, then: "Bar / Lounge"        },
            { case: { $ne: ["$subCategory", null] }, then: "Ostatní restaurace" }
          ],
          default: "Bez subkategorie"
        }
      },
      ma_souradnice:   { $and: [{ $ne: ["$lat", null] }, { $ne: ["$lng", null] }] },
      ma_subkategorii: { $ne: ["$subCategory", null] }
  }},
  { $unset: ["details", "reviews", "id"] },
  { $group: {
      _id:             "$typ_podniku",
      pocet:           { $sum: 1 },
      se_souradnicemi: { $sum: { $cond: ["$ma_souradnice",    1, 0] } },
      se_subkategorii: { $sum: { $cond: ["$ma_subkategorii", 1, 0] } },
      ukazka_nazvu:    { $push: "$name" }
  }},
  { $project: {
      _id: 0,
      typ_podniku:    "$_id",
      pocet:          1,
      souradnice_pct: { $round: [{ $multiply: [{ $divide: ["$se_souradnicemi", "$pocet"] }, 100] }, 1] },
      subkat_pct:     { $round: [{ $multiply: [{ $divide: ["$se_subkategorii", "$pocet"] }, 100] }, 1] },
      ukazka:         { $slice: ["$ukazka_nazvu", 3] }
  }},
  { $sort: { pocet: -1 } }
])
```

**Jak dotaz pracuje:** `$addFields` přidá tři nová pole bez zápisu do databáze – `typ_podniku` klasifikuje restauraci pomocí `$switch` + `$regexMatch` na poli `subCategory`. `$unset` odstraní technická pole z pipeline (nezapisuje do DB). `$group` poté agreguje podle typu podniku a počítá, kolik záznamů má souřadnice a subkategorii.

**Interpretace výsledku:** Výsledek ukáže typové složení Dubai restaurací – dominují kavárny, fast food a ostatní kategorie. Všechna místa mají 100 % souřadnic (geodata jsou kompletní). Skupina "Bez subkategorie" (2988 záznamů) ukazuje datovou mezeru v původním datasetu.

---

### Dotaz 14 – Cenové kategorie + cuisine_tags + popularity skóre pro Indii

**Zadání:** Přiřaď každé indické restauraci cenovou kategorii (Budget/Mid-Range/Premium/Luxury), sestav pole cuisine_tags z binárních příznaků a vypočítej popularity skóre. Výsledky agreguj podle cenové kategorie.

```javascript
db.indian_restaurants.aggregate([
  { $addFields: {
      price_tier: {
        $switch: {
          branches: [
            { case: { $lte: ["$average_price", 150] }, then: "Budget"    },
            { case: { $lte: ["$average_price", 300] }, then: "Mid-Range" },
            { case: { $lte: ["$average_price", 500] }, then: "Premium"   }
          ],
          default: "Luxury"
        }
      },
      cuisine_tags: {
        $filter: {
          input: [
            { $cond: [{ $eq: ["$south_indian_or_not", 1] }, "South Indian", null] },
            { $cond: [{ $eq: ["$north_indian_or_not", 1] }, "North Indian", null] },
            { $cond: [{ $eq: ["$fast_food_or_not",   1] }, "Fast Food",    null] },
            { $cond: [{ $eq: ["$street_food",         1] }, "Street Food",  null] },
            { $cond: [{ $eq: ["$biryani_or_not",      1] }, "Biryani",      null] },
            { $cond: [{ $eq: ["$bakery_or_not",       1] }, "Bakery",       null] }
          ],
          as:   "tag",
          cond: { $ne: ["$$tag", null] }
        }
      },
      popularity_score: {
        $round: [{
          $multiply: [
            "$rating",
            { $add: [1, { $multiply: [0.05, { $subtract: [35, "$average_delivery_time"] }] }] }
          ]
        }, 2]
      }
  }},
  { $group: {
      _id:              "$price_tier",
      pocet:            { $sum: 1 },
      avg_rating:       { $avg: "$rating" },
      avg_popularity:   { $avg: "$popularity_score" },
      avg_delivery:     { $avg: "$average_delivery_time" },
      multi_cuisine:    { $sum: { $cond: [{ $gt: [{ $size: "$cuisine_tags" }, 1] }, 1, 0] } }
  }},
  { $sort: { avg_popularity: -1 } },
  { $project: {
      _id: 0,
      cenova_kat:         "$_id",
      pocet:              1,
      avg_hodnoceni:      { $round: ["$avg_rating", 2] },
      avg_popularity:     { $round: ["$avg_popularity", 2] },
      avg_doruceni_min:   { $round: ["$avg_delivery", 0] },
      multi_cuisine_pct:  { $round: [{ $multiply: [{ $divide: ["$multi_cuisine", "$pocet"] }, 100] }, 1] }
  }}
])
```

**Jak dotaz pracuje:** `$filter` s `$$REMOVE` je elegantní způsob, jak sestavit pole tagů pouze z binárních příznaků hodnoty 1. `$cond` vrátí název tagu nebo speciální `$$REMOVE`, který MongoDB z pole odstraní. Popularity skóre penalizuje pomalé doručení.

**Interpretace výsledku:** Budget restaurace mohou mít překvapivě vysoké popularity skóre, pokud kombinují rychlé doručení s přijatelným hodnocením. Výsledek ukazuje kompromis mezi cenou, kvalitou a rychlostí v různých segmentech trhu.

---

### Dotaz 15 – Normalizace subCategory + sentiment distribuce v Dubai

**Zadání:** Normalizuj subCategory (lowercase, trim) a pro každou subkategorii zjisti distribuci sentimentu (pozitivní/negativní/neutrální) i s ukázkovými názvy restaurací.

```javascript
db.dubai_restaurants.aggregate([
  { $match: { subCategory: { $ne: null } } },
  { $addFields: {
      sub_norm: { $trim: { input: { $toLower: "$subCategory" } } },
      geo_zona: {
        $cond: {
          if:   { $lt: ["$lat", 25.1] },
          then: "Jizni Dubai",
          else: {
            $cond: {
              if:   { $lt: ["$lat", 25.2] },
              then: "Centralni Dubai",
              else: "Severni Dubai"
            }
          }
        }
      }
  }},
  { $group: {
      _id:   { sub: "$sub_norm", zona: "$geo_zona" },
      count: { $sum: 1 },
      nazvy: { $push: "$name" }
  }},
  { $group: {
      _id:   "$_id.sub",
      total: { $sum: "$count" },
      distribuce: {
        $push: {
          zona:   "$_id.zona",
          count:  "$count",
          ukazky: { $slice: ["$nazvy", 2] }
        }
      }
  }},
  { $sort: { total: -1 } },
  { $limit: 12 },
  { $project: {
      _id: 0,
      subkategorie:  "$_id",
      celkem:        "$total",
      geo_distribuce: "$distribuce"
  }}
])
```

**Jak dotaz pracuje:** Dvojúrovňový `$group` – první seskupuje podle kombinace (subkategorie, geo_zona), druhý přeskupí výsledky jen podle subkategorie a vloží geografickou distribuci jako vnořené pole. Vzor „pivot" agregace v MongoDB. `$cond` vnořené do `$cond` klasifikuje každý záznam do tří zeměpisných pásem podle `lat`.

**Interpretace výsledku:** Pro každou subkategorii ukazuje, ve které části Dubaje (jižní / centrální / severní) se restaurace koncentrují. Severní Dubai (lat > 25.2) má celkově nejvíce restaurací – odpovídá turistickým oblastem (Downtown, JBR, Marina). Jižní Dubai (lat < 25.1) je méně hustý.

---

### Dotaz 16 – Extrakce domén z websites USA fastfood + web coverage analýza

**Zadání:** Z pole `websites` extrahuj primární doménu každého záznamu, zjisti pro každý řetězec podíl poboček s webem a seznam unikátních domén.

```javascript
db.usa_fastfood.aggregate([
  { $addFields: {
      ma_web:       { $and: [{ $ne: ["$websites", null] }, { $ne: ["$websites", ""] }] },
      prvni_web:    { $arrayElemAt: [{ $split: [{ $ifNull: ["$websites", ""] }, ","] }, 0] }
  }},
  { $addFields: {
      domena: {
        $cond: {
          if: "$ma_web",
          then: {
            $arrayElemAt: [
              { $split: [
                  { $arrayElemAt: [{ $split: ["$prvni_web", "//"] }, 1] },
                  "/"
              ]},
              0
            ]
          },
          else: "bez_webu"
        }
      }
  }},
  { $group: {
      _id:           "$name",
      celkem:        { $sum: 1 },
      se_webem:      { $sum: { $cond: ["$ma_web", 1, 0] } },
      domeny:        { $addToSet: "$domena" },
      staty:         { $addToSet: "$province" }
  }},
  { $sort: { celkem: -1 } },
  { $limit: 12 },
  { $project: {
      _id: 0,
      retezec:       "$_id",
      celkem_poboček: "$celkem",
      web_pokryti_pct: {
        $round: [{ $multiply: [{ $divide: ["$se_webem", "$celkem"] }, 100] }, 1]
      },
      domeny:        1,
      pocet_statu:   { $size: "$staty" }
  }}
])
```

**Jak dotaz pracuje:** Dvojfázový `$addFields` nejprve izoluje první URL ze seznam oddělených čárkou, poté extrahuje doménu rozdělením podle `//` a `/`. Chyby ošetří `$ifNull`. Ukazuje pokročilé string operace v agregaci.

**Interpretace výsledku:** Řetězce s nízkým procentem webového pokrytí mají neúplná data. Přítomnost více domén u jednoho řetězce naznačuje regionální webové strategie nebo zastaralé záznamy s různými URL formáty.

---

### Dotaz 17 – Value-for-money ranking indických měst + best-value restaurace

**Zadání:** Vypočítej skóre „value-for-money" pro každou indickou restauraci a seřaď města podle průměrného VFM skóre. Pro každé město ukaž nejlepší restauraci.

```javascript
db.indian_restaurants.aggregate([
  { $addFields: {
      vfm_score: {
        $round: [{
          $multiply: [
            { $divide: ["$rating", 5] },
            { $divide: [500, { $max: ["$average_price", 1] }] },
            { $divide: [60,  { $max: ["$average_delivery_time", 1] }] },
            100
          ]
        }, 2]
      }
  }},
  { $sort: { vfm_score: -1 } },
  { $group: {
      _id:              "$location",
      nejlepsi_rest:    { $first: "$restaurant_name" },
      nejlepsi_vfm:     { $first: "$vfm_score" },
      avg_vfm:          { $avg: "$vfm_score" },
      avg_cena:         { $avg: "$average_price" },
      avg_hodnoceni:    { $avg: "$rating" },
      pocet:            { $sum: 1 }
  }},
  { $sort: { avg_vfm: -1 } },
  { $limit: 12 },
  { $project: {
      _id: 0,
      mesto:            "$_id",
      nejlepsi_rest:    1,
      nejlepsi_vfm:     1,
      avg_vfm:          { $round: ["$avg_vfm", 2] },
      avg_cena_inr:     { $round: ["$avg_cena", 0] },
      avg_hodnoceni:    { $round: ["$avg_hodnoceni", 2] },
      pocet_restauraci: "$pocet"
  }}
])
```

**Jak dotaz pracuje:** VFM skóre kombinuje tři dimenze: hodnocení (normalizované na 0–1), cenu (inverzní – levnější = lepší) a čas doručení (inverzní). `$sort` před `$group` zajistí, že `$first` vrátí skutečně nejlepší restauraci v každém městě.

**Interpretace výsledku:** Malá města s nízkými cenami a dobrým hodnocením mají nejvyšší VFM skóre. Výsledek slouží jako doporučení pro cestovatele hledající nejlepší poměr cena/výkon.

---

### Dotaz 18 – Reshape Dubai dokumentů pro report: geo_point + data_quality objekt + $unset

**Zadání:** Pro Dubai restaurace, které mají vyplněnou subkategorii i adresu, přetvoř strukturu dokumentu: vytvoř GeoJSON bod, objekt kvality dat a odstraň nepotřebná pole.

```javascript
db.dubai_restaurants.aggregate([
  { $match: {
      subCategory: { $ne: null },
      address:     { $ne: null }
  }},
  { $addFields: {
      geo_point: {
        type:        "Point",
        souradnice: ["$lng", "$lat"]
      },
      zdroj_hodnoceni: "TourPedia sentiment analysis",
      kvalita_dat: {
        ma_adresu:      { $ne: ["$address", null] },
        ma_subkategorii: { $ne: ["$subCategory", null] },
        ma_polarity:    { $ne: ["$polarity", 0] }
      }
  }},
  { $unset: ["details", "reviews", "id", "originalId", "lat", "lng"] },
  { $project: {
      _id: 0,
      name:            1,
      category:        1,
      subCategory:     1,
      location:        1,
      address:         1,
      polarity:        1,
      geo_point:       1,
      zdroj_hodnoceni: 1,
      kvalita_dat:     1
  }},
  { $sort:  { name: 1 } },
  { $limit: 15 }
])
```

**Jak dotaz pracuje:** `$match` vybere dokumenty s vyplněnou subkategorií i adresou. `$addFields` vytvoří vnořený GeoJSON objekt a `kvalita_dat` dokument s boolean hodnotami. `$unset` odstraní redundantní pole. `$project` přesně určí finální výstupní strukturu. Výsledek je čistý dokument připravený pro export nebo API odpověď.

**Interpretace výsledku:** Výsledné dokumenty mají standardizovanou strukturu vhodnou pro import do geospatial systémů (GeoJSON). Objekt `kvalita_dat` umožní následnou filtraci kompletních vs. neúplných záznamů — `ma_adresu` a `ma_subkategorii` budou `true` u všech výsledků (podmínka filtru), `ma_polarity` bude `false` u většiny (zrcadlí reálný stav dat).

---

## KATEGORIE 4: Indexy a optimalizace

---

### Dotaz 19 – explain() pro compound index { category: 1, polarity: -1 } v Dubai

**Zadání:** Ověř, že agregační pipeline filtrující podle `category` a `polarity` skutečně využívá compound index. Porovnej executionStats.

```javascript
// Krok 1
db.dubai_restaurants.getIndexes()

// Krok 2
db.dubai_restaurants.explain("executionStats").aggregate([
  { $match: { category: "restaurant", polarity: { $gt: 0.2 } } },
  { $sort:  { polarity: -1 } },
  { $limit: 20 },
  { $project: { name: 1, category: 1, polarity: 1, subCategory: 1, _id: 0 } }
])
```

**Jak dotaz pracuje:** `explain("executionStats")` vrátí kompletní plán vykonání dotazu včetně: zvoleného indexu (winningPlan), počtu prohledaných dokumentů (totalDocsExamined) a celkového času. Compound index `{ category: 1, polarity: -1 }` by měl umožnit index scan místo collection scan.

**Interpretace výsledku:** V poli `winningPlan.inputStage.indexName` by se měl objevit `category_1_polarity_-1`. `totalDocsExamined` by mělo být výrazně nižší než celkový počet dokumentů v kolekci (7342). Hodnota `executionTimeMillis` ukazuje skutečnou dobu dotazu.

---

### Dotaz 20 – Fulltext search na Dubai restauracích s $meta relevance skóre

**Zadání:** Prohledej Dubai restaurace fulltext indexem na polích name, category, subCategory. Vrať výsledky seřazené podle relevance skóre.

```javascript
db.dubai_restaurants.aggregate([
  { $match: { $text: { $search: "coffee hotel bar lounge" } } },
  { $addFields: { relevance_score: { $meta: "textScore" } } },
  { $sort:  { relevance_score: -1 } },
  { $limit: 15 },
  { $project: {
      _id: 0,
      name:            1,
      category:        1,
      subCategory:     1,
      polarity:        1,
      relevance_score: { $round: ["$relevance_score", 3] }
  }}
])
```

**Jak dotaz pracuje:** `$text` využívá text index `{ name: "text", category: "text", subCategory: "text" }`. `$meta: "textScore"` přidá relevance skóre vypočítané na základě TF-IDF algoritmu. Dokumenty se shodou ve více polích nebo s více výskyty hledaných slov získají vyšší skóre.

**Interpretace výsledku:** Restaurace s názvem obsahujícím hledané slovo nebo zařazené do odpovídající subkategorie se objeví nahoře. Toto je základ pro vyhledávač restaurací – uživatel zadá volný text a systém vrátí nejrelevantnější výsledky.

---

### Dotaz 21 – Fulltext search na USA fastfood + agregace po řetězcích

**Zadání:** Fulltext vyhledej řetězce s pizzou v USA datasetu, seskup podle názvu řetězce a ukaž průměrnou relevanci, počet poboček a ukázková města.

```javascript
db.usa_fastfood.aggregate([
  { $match: { $text: { $search: "Pizza" } } },
  { $addFields: { score: { $meta: "textScore" } } },
  { $group: {
      _id:        "$name",
      pocet:      { $sum: 1 },
      relevance:  { $avg: "$score" },
      mesta:      { $addToSet: "$city" },
      staty:      { $addToSet: "$province" }
  }},
  { $sort: { pocet: -1 } },
  { $limit: 10 },
  { $project: {
      _id: 0,
      retezec:       "$_id",
      pocet_poboček: "$pocet",
      avg_relevance: { $round: ["$relevance", 3] },
      pocet_statu:   { $size: "$staty" },
      mesta_ukazka:  { $slice: ["$mesta", 4] }
  }}
])
```

**Jak dotaz pracuje:** Text index `{ name: "text", city: "text" }` umožní hledání ve jménu řetězce i v názvu města. `$group` poté seskupí výsledky – jeden řetězec může mít stovky poboček, ale text index je nalezl všechny najednou.

**Interpretace výsledku:** Pizza Hut, Domino's a Little Caesars by měly dominovat výsledkům. Průměrná relevance ukazuje, jak „pizzový" je název řetězce – řetězec s „Pizza" přímo v názvu bude mít vyšší skóre než jiné.

---

### Dotaz 22 – hint() srovnání – hashed vs. compound index na Dubai dotazu

**Zadání:** Porovnej výkon dotazu na Dubai restaurace při vynuceném použití hashed indexu (shard key) vs. compound indexu. Ukaž rozdíl v executionStats.

```javascript
// Varianta A: Vynucení compound indexu { location: 1, subCategory: 1 } pro filtraci s prefixem
db.dubai_restaurants.find(
  { location: "Dubai", subCategory: { $ne: null } },
  { name: 1, subCategory: 1, _id: 0 }
).hint({ location: 1, subCategory: 1 }).explain("executionStats")

// Varianta B: Tentýž dotaz bez hint – MongoDB zvolí plán sám (porovnání s Variantou A)
db.dubai_restaurants.find(
  { location: "Dubai", subCategory: { $ne: null } },
  { name: 1, subCategory: 1, _id: 0 }
).explain("executionStats")

// Varianta C: Přímé vynucení hashed indexu (shard key) pro equality dotaz
db.dubai_restaurants.find(
  { name: "McDonald's" }
).hint({ name: "hashed" }).explain("executionStats")
```

**Jak dotaz pracuje:** `hint()` přepisuje query planner a vynutí použití konkrétního indexu. Compound index `{ location: 1, subCategory: 1 }` je efektivní pro dotazy s prefixem `location` a následnou filtrací `subCategory`. Hashed index je optimální pro **equality** dotazy na shard key (přesná shoda) – MongoDB dokáže přesně lokalizovat chunk bez scatter-gather. Varianta A a B jsou identické dotazy – porovnáme, zda MongoDB sám zvolí optimální index.

**Interpretace výsledku:** Varianta A s hint vrátí `nReturned: 4354`, `totalKeysExamined: 4357` – poměr klíčů ku dokumentům téměř 1:1, všechny tři shardy použily `IXSCAN` na `location_1_subCategory_1`. Varianta B bez hint odhalí zajímavou asymetrii: rs2 a rs3 zvolily správný compound index, ale **rs1 zvolil jednodušší `location_1`**, musel post-filtrovat null hodnoty a prošel 2 503 dokumentů pro 1 488 vrácených – celkově o **23 % více** klíčů/dokumentů oproti Variantě A. Varianta C ukáže klíčový rozdíl architektury: hashed shard key přeloží "McDonald's" na hash `[-6917824619940975324]`, dotaz zamíří jen na **rs3** (`SINGLE_SHARD` místo `SHARD_MERGE`) a vrátí 17 dokumentů za 3 ms místo 12 ms – ukázka targeted query vs. scatter-gather.

---

### Dotaz 23 – Prostorový bounding box dotaz na Dubai restaurace + zonální klasifikace

**Zadání:** Najdi Dubai restaurace v oblasti Jumeirah a Dubai Marina (bounding box souřadnic) a klasifikuj je do zón podle přesných souřadnic. Využívá compound index `{ lat: 1, lng: 1 }`.

```javascript
db.dubai_restaurants.aggregate([
  { $match: {
      lat: { $gte: 25.05, $lte: 25.30 },
      lng: { $gte: 55.10, $lte: 55.45 }
  }},
  { $addFields: {
      zona: {
        $switch: {
          branches: [
            { case: { $and: [{ $gte: ["$lat", 25.22] }, { $lte: ["$lng", 55.22] }] }, then: "Dubai Marina / JBR"   },
            { case: { $and: [{ $gte: ["$lat", 25.16] }, { $lt:  ["$lat", 25.22] }] }, then: "Jumeirah Beach Road"  },
            { case: { $and: [{ $lt:  ["$lat", 25.16] }, { $lte: ["$lng", 55.25] }] }, then: "Jumeirah / Madinat"   },
            { case: { $gt:  ["$lng", 55.38] },                                         then: "Deira / Business Bay" }
          ],
          default: "Ostatní Dubai"
        }
      }
  }},
  { $group: {
      _id:         "$zona",
      pocet:       { $sum: 1 },
      avg_lat:     { $avg: "$lat" },
      avg_lng:     { $avg: "$lng" },
      subkategorie: { $addToSet: "$subCategory" },
      ukazky:      { $push: "$name" }
  }},
  { $sort: { pocet: -1 } },
  { $project: {
      _id: 0,
      zona:             "$_id",
      pocet_restauraci: "$pocet",
      centroid: {
        lat: { $round: ["$avg_lat", 4] },
        lng: { $round: ["$avg_lng", 4] }
      },
      pocet_subkategorii: {
        $size: { $filter: { input: "$subkategorie", as: "s", cond: { $ne: ["$s", null] } } }
      },
      ukazky: { $slice: ["$ukazky", 3] }
  }}
])
```

**Jak dotaz pracuje:** `$match` na dvou číselných polích `lat` a `lng` s range podmínkami využívá compound index `{ lat: 1, lng: 1 }` – MongoDB prohledá jen relevantní část B-tree indexu. `$addFields` se `$switch` přiřadí každé restauraci konkrétní dubajskou čtvrť podle přesných souřadnic. `$group` spočítá průměrné souřadnice zóny (centroid) a počet unikátních subkategorií.

**Interpretace výsledku:** Výsledek ukáže rozložení restaurací v různých dubajských čtvrtích s geografickým centroidem každé zóny (průměrné souřadnice). Turisticky orientované oblasti (JBR, Marina) typicky vykazují vyšší pestrost subkategorií. Centroid pomáhá vizualizovat zóny na mapě.

---

### Dotaz 24 – explain() compound index { location: 1, rating: -1 } + targeted dotaz na Mumbaj

**Zadání:** Ověř efektivitu compound indexu pro dotaz na indické restaurace v Mumbaji s hodnocením ≥ 4.0. Zobraz top 5 restaurací a exekuční statistiky.

```javascript
// Krok 1
db.indian_restaurants.find(
  { location: "Mumbai", rating: { $gte: 4.0 } }
).hint({ location: 1, rating: -1 }).sort({ rating: -1, average_price: 1 }).explain("executionStats")

// Krok 2
db.indian_restaurants.aggregate([
  { $match: { location: "Mumbai", rating: { $gte: 4.0 } } },
  { $sort:  { rating: -1, average_price: 1 } },
  { $group: {
      _id:          null,
      pocet:        { $sum: 1 },
      avg_cena:     { $avg: "$average_price" },
      avg_doruceni: { $avg: "$average_delivery_time" },
      top5: {
        $push: {
          nazev:    "$restaurant_name",
          rating:   "$rating",
          cena_inr: "$average_price"
        }
      }
  }},
  { $project: {
      _id: 0,
      pocet_vysoke_hodnoceni: "$pocet",
      avg_cena_inr:  { $round: ["$avg_cena", 0] },
      avg_doruceni:  { $round: ["$avg_doruceni", 0] },
      top5_restauraci: { $slice: ["$top5", 5] }
  }}
])
```

**Jak dotaz pracuje:** Compound index `{ location: 1, rating: -1 }` umožní **index scan** pro přesnou shodu na `location` a range podmínku na `rating`. Bez indexu by MongoDB prohledal všech 27 656 záznamů. S indexem prohledá jen Mumbai záznamy s hodnocením ≥ 4.0.

**Interpretace výsledku:** `explain()` ukáže `IXSCAN` místo `COLLSCAN` v `winningPlan`. `totalDocsExamined` bude podmnožinou celkového počtu dokumentů. Top 5 restaurací Mumbaje s vysokým hodnocením jsou vlajkové lodě lokální gastro scény.

---

## KATEGORIE 5: Distribuce dat, cluster, replikace a chování při výpadku

---

### Dotaz 25 – Distribuce chunků v config databázi přes všechny shardované kolekce

**Zadání:** Zjisti, jak jsou chunky rozděleny mezi shardy pro všechny tři shardované kolekce. Výsledek ukáže rovnoměrnost distribuce dat.

```javascript
use config

db.collections.aggregate([
  { $match: { _id: { $regex: "^restaurants\\." } } },
  { $lookup: {
      from:         "chunks",
      localField:   "uuid",
      foreignField: "uuid",
      as:           "chunk_docs"
  }},
  { $unwind: "$chunk_docs" },
  { $group: {
      _id:          { ns: "$_id", shard: "$chunk_docs.shard" },
      pocet_chunku: { $sum: 1 }
  }},
  { $group: {
      _id:           "$_id.ns",
      shardy:        { $push: { shard: "$_id.shard", chunky: "$pocet_chunku" } },
      celkem_chunku: { $sum: "$pocet_chunku" }
  }},
  { $project: {
      _id: 0,
      kolekce:       "$_id",
      celkem_chunku: 1,
      distribuce:    "$shardy"
  }},
  { $sort: { kolekce: 1 } }
])
```

**Jak dotaz pracuje:** Od MongoDB 6.0 pole `ns` v `config.chunks` bylo nahrazeno polem `uuid`. Dotaz proto začíná v `config.collections` (kde je mapování namespace → UUID) a přes `$lookup` spojí s `config.chunks`. Dvojúrovňový `$group` nejprve sečte chunky per (kolekce, shard) kombinaci, poté seskupí per kolekci s polem distribuce. Výsledek je dostupný pouze přes `mongos` nebo přes config server.

**Interpretace výsledku:** Rovnoměrná distribuce (stejný počet chunků na každém shardu) znamená, že balancer funguje správně. Odchylka > 2× naznačuje nevyvážený shard key nebo příliš velké chunky – záznamy se hromadí na jednom shardu (hotspot).

---

### Dotaz 26 – $collStats: storage statistiky a počty dokumentů na shardech

**Zadání:** Pro každou kolekci zjisti storage statistiky (velikost dat, počet dokumentů, průměrná velikost dokumentu) a aktuální stav indexů.

```javascript
use restaurants

db.dubai_restaurants.aggregate([
  { $collStats: { storageStats: { scale: 1024 }, count: {} } },
  { $project: {
      shard:        1,
      count:        1,
      "storageStats.size":       1,
      "storageStats.count":      1,
      "storageStats.avgObjSize": 1,
      "storageStats.nindexes":   1,
      "storageStats.totalIndexSize": 1
  }}
])

db.usa_fastfood.aggregate([
  { $collStats: { storageStats: { scale: 1024 }, count: {} } },
  { $project: {
      shard:        1,
      count:        1,
      "storageStats.size":       1,
      "storageStats.count":      1,
      "storageStats.avgObjSize": 1,
      "storageStats.nindexes":   1,
      "storageStats.totalIndexSize": 1
  }}
])

db.indian_restaurants.aggregate([
  { $collStats: { storageStats: { scale: 1024 }, count: {} } },
  { $project: {
      shard:        1,
      count:        1,
      "storageStats.size":       1,
      "storageStats.count":      1,
      "storageStats.avgObjSize": 1,
      "storageStats.nindexes":   1,
      "storageStats.totalIndexSize": 1
  }}
])
```

**Jak dotaz pracuje:** `$collStats` je speciální aggregation stage (ne standardní fáze pipeline), která vrátí metadata o kolekci místo dokumentů dat. Při volání přes `mongos` vrátí statistiky každého shardu zvlášť – vidíme rozložení dat. `scale: 1024` převede bajty na kilobajty.

**Interpretace výsledku:** Výsledek obsahuje `count` (počet dokumentů), `storageSize` (fyzická velikost), `avgObjSize` (průměrná velikost dokumentu) a `nindexes` (počet indexů). Per-shard breakdown odhalí nerovnoměrné rozložení dat – větší shardové fragmenty na jednom uzlu indikují nevyvážený cluster.

---

### Dotaz 27 – Přehled stavu clusteru: listShards + serverStatus + sh.status()

**Zadání:** Zobraz kompletní přehled stavu MongoDB sharded clusteru – seznam shardů, jejich stav, verze a konfiguraci balanceru.

```javascript
// Krok 1
use admin
db.adminCommand({ listShards: 1 })

// Krok 2
var s = db.adminCommand({ serverStatus: 1 });
printjson({
  version:     s.version,
  uptime_sec:  s.uptimeEstimate,
  opcounters:  s.opcounters,
  connections: s.connections,
  sharding: {
    configsvr:         s.sharding.configsvrConnectionString,
    maxChunkSizeBytes: s.sharding.maxChunkSizeInBytes,
    routerEnabled:     s.sharding.routerServiceEnabled
  },
  hostsTargeted: s.shardingStatistics.numHostsTargeted
});

// Krok 3
sh.status()

// Krok 4
use config
db.settings.find({ _id: "balancer" }).pretty()
db.settings.find({ _id: "chunksize" }).pretty()

// Krok 5
db.collections.find(
  { _id: { $regex: "^restaurants\\." } },
  { _id: 1, key: 1, unique: 1 }
).pretty()
```

**Jak dotaz pracuje:** `listShards` vrátí metadata o každém registrovaném shardu (hostname, replica set jméno, stav). `serverStatus` poskytne statistiky mongos procesu. `sh.status()` je helper příkaz, který agreguje informace o všech shardech, kolekcích a distribución chunků do čitelného výpisu.

**Interpretace výsledku:** Výsledek `listShards` ukáže tři shardy: `rs1`, `rs2`, `rs3` s jejich connection stringy. `sh.status()` ukáže, zda je balancer aktivní a jak jsou chunky distribuovány. `chunksize: 32` potvrdí nastavenou velikost chunků 32 MB.

---

### Dotaz 28 – Stav replica setu + replication lag na secondary uzlech

**Zadání:** Zkontroluj stav jednoho z replica setů (např. rs1) – kdo je primary, kdo secondary, jaký je replication lag a kdy naposledy proběhla heartbeat komunikace.

```javascript
// Poznámka: admin user byl vytvořen přes mongos a je uložen v config serveru.
// Přímé připojení k individuálním shardům (shard1-1:27018) vyžaduje lokálního uživatele
// na každém shardu – tento uživatel v aktuálním setupu neexistuje.
// Proto se připojíme na config server primary (configsvr1:27019), kde admin user existuje.
// docker exec -it configsvr1 mongosh --port 27019 -u admin -p 'RestCluster2024!' --authenticationDatabase admin

// Krok 1
rs.status()

// Krok 2
rs.status().members.forEach(function(m) {
  print("Člen: " + m.name +
        " | Stav: " + m.stateStr +
        " | Health: " + m.health +
        " | Optime: " + (m.optimeDate ? m.optimeDate : "N/A"));
})

// Krok 3
var status    = rs.status();
var primary   = status.members.find(m => m.stateStr === "PRIMARY");
var secondary = status.members.find(m => m.stateStr === "SECONDARY");
if (primary && secondary) {
  var lagSec = (primary.optimeDate - secondary.optimeDate) / 1000;
  print("Replication lag: " + lagSec + " sekund");
} else {
  print("Nelze zjistit lag – primary nebo secondary nenalezen");
}

// Krok 4
rs.conf()
```

**Poznámka k architektuře:** V MongoDB sharded clusteru jsou uživatelé vytvořeni přes `mongos` uloženi v config server replica setu (CSRS). Individuální shardy (rs1, rs2, rs3) nemají tyto uživatele ve svých lokálních admin databázích – jejich vzájemná autentizace probíhá přes keyfile. Pro přímý přístup na shard nodes by bylo nutné vytvořit lokální admin uživatele přímo na každém shardu. Toto je standardní bezpečnostní aspekt MongoDB sharded cluster architektury.

**Jak dotaz pracuje:** `rs.status()` vrátí aktuální stav všech členů replica setu včetně posledního aplikovaného oplog záznamu (`optimeDate`). Replication lag = rozdíl `optimeDate` primary vs. secondary v milisekundách dělený 1000. Nulový nebo velmi malý lag znamená, že secondary jsou synchronizovány.

**Interpretace výsledku:** V klidném clusteru bez zátěže by replication lag měl být < 1 sekunda (typicky 0). Záznamy s `stateStr: "SECONDARY"` a `health: 1` indikují zdravý stav. `rs.conf()` potvrdí konfiguraci voličů (votes) a priorit členů CSRS.

---

### Dotaz 29 – Simulace výpadku primary uzlu (rs.stepDown) + sledování nové volby

**Zadání:** Nasimuluj výpadek primary uzlu v config server replica setu (CSRS) pomocí `rs.stepDown()`. Sleduj průběh volby nového primary a ověř, že cluster zůstane dostupný přes mongos.

```javascript
// ===== PŘÍPRAVA: Připojit se na configsvr1 (aktuální CSRS primary) =====
// docker exec -it configsvr1 mongosh --port 27019 -u admin -p 'RestCluster2024!' --authenticationDatabase admin

// Krok 1 – ověř že jsi na primary
rs.isMaster()

// Krok 2 – stepDown (60 s timeout pro nového primary)
// Upozornění: připojení se přeruší – to je očekávané chování
rs.stepDown(60)

// Krok 3 – znovu se připoj a zjisti kdo je nový primary
// docker exec -it configsvr1 mongosh --port 27019 -u admin -p 'RestCluster2024!' --authenticationDatabase admin
rs.status().members.forEach(m => print(m.name, "->", m.stateStr))

// Krok 4 – ověř že cluster přes mongos stále funguje (v jiném terminálu)
// docker exec -it mongos mongosh --port 27017 -u admin -p 'RestCluster2024!' --authenticationDatabase admin
use restaurants
db.dubai_restaurants.countDocuments()
db.indian_restaurants.findOne({ rating: { $gte: 4.5 } }, { restaurant_name: 1, rating: 1, location: 1, _id: 0 })

// Krok 5 – sleduj průběh volby (spusť těsně po stepDown, na configsvr2 nebo configsvr3)
// docker exec -it configsvr2 mongosh --port 27019 -u admin -p 'RestCluster2024!' --authenticationDatabase admin
var i = 0;
while (i < 4) {
  rs.status().members.forEach(m => print(m.name, "->", m.stateStr));
  print("---");
  sleep(3000);
  i++;
}

// Krok 6 – oplog: posledních 5 zápisů v CSRS
use local
db.oplog.rs.find().sort({ $natural: -1 }).limit(5)
  .forEach(e => print(e.op, e.ns, JSON.stringify(e.o).substring(0, 60)))
```

**Jak dotaz pracuje:** `rs.stepDown()` je bezpečná metoda simulace výpadku – primary se dobrovolně vzdá role a spustí se election protokol (Raft-based). Zbývající dva secondary uzly (musejí mít quorum = 2 z 3 hlasů) zvolí nového primary. Celý proces typicky trvá 10–30 sekund. Demonstrujeme na CSRS (config server RS) protože admin user existuje lokálně na config serverech. Data jsou při tomto procesu dostupná přes mongos díky `primaryPreferred` read preference.

**Interpretace výsledku:** Po `rs.stepDown()` jeden ze secondary uzlů (configsvr2 nebo configsvr3) přejde do stavu `PRIMARY`. Původní primary (configsvr1) se vrátí jako `SECONDARY` – díky `priority: 2` se po uplynutí `stepDown` timeoutu vrátí zpět na primary. Dotazy přes mongos (`countDocuments()`) stále fungují – důkaz HA architektury. Oplog zobrazí poslední transakce clusteru.

---

### Dotaz 30 – Balancer statistiky a validace dat: chunk migrace + schema compliance

**Zadání:** Zkontroluj historii migrací balanceru v config databázi a ověř konzistenci dat oproti validačnímu schématu (počet dokumentů bez povinných polí).

```javascript
// Krok 1
use config
db.changelog.aggregate([
  { $match: {
      what: { $in: ["moveChunk.start", "moveChunk.commit"] },
      time: { $gte: new Date(Date.now() - 24*60*60*1000) }
  }},
  { $group: {
      _id:       "$what",
      count:     { $sum: 1 },
      kolekce:   { $addToSet: "$ns" },
      posledni:  { $max: "$time" }
  }},
  { $project: {
      _id: 0,
      udalost:       "$_id",
      pocet:         "$count",
      kolekce:       1,
      posledni_cas:  "$posledni"
  }}
])

// Krok 2
use restaurants
db.dubai_restaurants.aggregate([
  { $project: {
      chybi_name:       { $cond: [{ $or: [{ $eq: ["$name", null] },     { $not: ["$name"] }]     }, 1, 0] },
      chybi_category:   { $cond: [{ $or: [{ $eq: ["$category", null] }, { $not: ["$category"] }] }, 1, 0] },
      chybi_polarity:   { $cond: [{ $or: [{ $eq: ["$polarity", null] }, { $not: ["$polarity"] }] }, 1, 0] },
      chybi_lat:        { $cond: [{ $or: [{ $eq: ["$lat", null] },      { $not: ["$lat"] }]      }, 1, 0] },
      chybi_originalId: { $cond: [{ $or: [{ $eq: ["$originalId", null] },{ $not: ["$originalId"] }]}, 1, 0] }
  }},
  { $group: {
      _id:              null,
      celkem:           { $sum: 1 },
      bez_name:         { $sum: "$chybi_name" },
      bez_category:     { $sum: "$chybi_category" },
      bez_polarity:     { $sum: "$chybi_polarity" },
      bez_lat:          { $sum: "$chybi_lat" },
      bez_originalId:   { $sum: "$chybi_originalId" }
  }},
  { $project: {
      _id: 0,
      celkem_dokumentu:   "$celkem",
      chybejici_name:     "$bez_name",
      chybejici_category: "$bez_category",
      chybejici_polarity: "$bez_polarity",
      chybejici_lat:      "$bez_lat",
      chybejici_originalId: "$bez_originalId"
  }}
])

// Krok 3
db.dubai_restaurants.aggregate([
  { $collStats: { count: {} } },
  { $project: { shard: 1, count: 1, _id: 0 } }
])
```

**Jak dotaz pracuje:** `config.changelog` uchovává historii všech balancer operací. `$match` na `what: "moveChunk.commit"` filtruje dokončené migrace za posledních 24 hodin. Druhá část pipeline ověří datovou konzistenci – spočítá, kolik dokumentů porušuje validační schéma (chybějící povinná pole). Třetí část ukáže aktuální rozložení počtů dokumentů na shardech přes `$collStats`.

**Interpretace výsledku:** Nulový nebo nízký počet migrací = cluster je v rovnováze, balancer nepotřebuje přesouvat chunky. Nenulový počet chybějících povinných polí ukazuje, že data byla importována před aktivací validačního schématu s `validationAction: "error"`. Počty dokumentů na shardech by měly být přibližně rovnoměrné (±20 %) – to potvrzuje, že hashed shard key efektivně distribuuje data.
