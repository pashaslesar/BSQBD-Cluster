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
      locations: { $addToSet: "$location" }
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

**Zadání:** Zjisti 10 největších fastfood řetězců v USA – počet poboček, počet pokrytých států a průměrnou zeměpisnou délku (indikátor, zda je řetězec spíše západní, centrální nebo východní).

```javascript
db.usa_fastfood.aggregate([
  { $group: {
      _id:           "$name",
      pocet_poboček: { $sum: 1 },
      staty:         { $addToSet: "$province" },
      avg_longitude: { $avg: "$longitude" },
      avg_latitude:  { $avg: "$latitude" }
  }},
  { $sort: { pocet_poboček: -1 } },
  { $limit: 10 },
  { $addFields: {
      geograficka_oblast: {
        $switch: {
          branches: [
            { case: { $lt: ["$avg_longitude", -100] }, then: "Západ USA" },
            { case: { $gt: ["$avg_longitude", -80]  }, then: "Východ USA" }
          ],
          default: "Střed USA"
        }
      }
  }},
  { $project: {
      _id: 0,
      retezec:          "$_id",
      pocet_poboček:    1,
      pocet_statu:      { $size: "$staty" },
      avg_longitude:    { $round: ["$avg_longitude", 2] },
      geograficka_oblast: 1
  }}
])
```

**Jak dotaz pracuje:** Po seskupení podle názvu řetězce pipeline přidá nové pole `geograficka_oblast` pomocí `$addFields` a `$switch`, které klasifikuje průměrnou zeměpisnou polohu. `$addToSet` sbírá unikátní státy. Využívá index `{ name: 1, province: 1 }`.

**Interpretace výsledku:** McDonald's a Subway dominují celkovým počtem poboček. Řetězce klasifikované jako „Střed USA" mají rovnoměrnější distribuci poboček přes celé USA, zatímco „Východ USA" odpovídá hustěji obydleným oblastem.

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
  { $addFields: { review_len: { $strLenCP: { $ifNull: ["$reviews", ""] } } } },
  { $group: {
      _id:         "$category",
      avg_rev_len: { $avg: "$review_len" },
      count:       { $sum: 1 }
  }},
  { $lookup: {
      from: "dubai_restaurants",
      let:  { kat: "$_id", avg_len: "$avg_rev_len" },
      pipeline: [
        { $addFields: { review_len: { $strLenCP: { $ifNull: ["$reviews", ""] } } } },
        { $match: { $expr: { $and: [
            { $eq: ["$category",  "$$kat"]     },
            { $gt: ["$review_len", "$$avg_len"] }
        ]}}},
        { $sort:    { review_len: -1 } },
        { $limit:   3 },
        { $project: { name: 1, review_len: 1, subCategory: 1, location: 1, _id: 0 } }
      ],
      as: "top_restaurace"
  }},
  { $match: { "top_restaurace.0": { $exists: true } } },
  { $sort:  { avg_rev_len: -1 } },
  { $limit: 8 },
  { $project: {
      _id: 0,
      kategorie:      "$_id",
      count:          1,
      avg_rev_len:    { $round: ["$avg_rev_len", 0] },
      top_restaurace: 1
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
      "dle_kategorie": [
        { $group: { _id: "$category", pocet: { $sum: 1 }, avg_polarity: { $avg: "$polarity" } } },
        { $sort:  { pocet: -1 } },
        { $limit: 5 }
      ],
      "dle_lokace": [
        { $group: { _id: "$location", pocet: { $sum: 1 } } },
        { $sort:  { pocet: -1 } },
        { $limit: 5 }
      ],
      "statistika_polarity": [
        { $group: {
            _id:       null,
            celkem:    { $sum: 1 },
            prumer:    { $avg: "$polarity" },
            maximum:   { $max: "$polarity" },
            minimum:   { $min: "$polarity" },
            pozitivni: { $sum: { $cond: [{ $gt:  ["$polarity", 0] }, 1, 0] } },
            negativni: { $sum: { $cond: [{ $lt:  ["$polarity", 0] }, 1, 0] } },
            neutralni: { $sum: { $cond: [{ $eq:  ["$polarity", 0] }, 1, 0] } }
        }},
        { $project: { _id: 0, celkem: 1, prumer: { $round: ["$prumer", 4] },
            maximum: 1, minimum: 1, pozitivni: 1, negativni: 1, neutralni: 1 } }
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
      retezec:         "$_id",
      usa_poboček:     "$usa_count",
      usa_statu:       { $size: "$usa_staty" },
      dubai_poboček:   { $size: "$dubai_pobocky" },
      dubai_sentiment: { $avg: "$dubai_pobocky.polarity" },
      dubai_detail:    "$dubai_pobocky"
  }},
  { $sort: { usa_poboček: -1 } }
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
      _id:          { $ifNull: ["$subCategory", "Nezařazeno"] },
      dubai_count:  { $sum: 1 },
      avg_polarity: { $avg: "$polarity" },
      lokace:       { $addToSet: "$location" }
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
      dubai_count:        1,
      avg_polarity:       { $round: ["$avg_polarity", 3] },
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

**Interpretace výsledku:** Každá Dubai fastfood subkategorie je doplněna absolutními čísly z indického fastfood segmentu. Ukazuje rozdíl v sentiment profilu (polarity v Dubaji) oproti hodnocení v Indii.

---

### Dotaz 10 – Globální přítomnost top 6 řetězců přes všechny tři datasety (triple $lookup)

**Zadání:** Pro McDonald's, Subway, KFC, Pizza Hut, Burger King a Domino's zjisti přítomnost a základní metriky ve všech třech datasetů najednou.

```javascript
db.usa_fastfood.aggregate([
  { $match: { name: { $in: ["McDonald's", "Subway", "KFC", "Pizza Hut", "Burger King", "Domino's"] } } },
  { $group: {
      _id:       "$name",
      usa_count: { $sum: 1 },
      usa_staty: { $addToSet: "$province" }
  }},
  { $lookup: {
      from: "dubai_restaurants",
      let:  { cname: "$_id" },
      pipeline: [
        { $match: { $expr: { $regexMatch: { input: "$name", regex: "$$cname", options: "i" } } } },
        { $group: { _id: null, count: { $sum: 1 }, avg_pol: { $avg: "$polarity" } } }
      ],
      as: "dubai"
  }},
  { $lookup: {
      from: "indian_restaurants",
      let:  { cname: "$_id" },
      pipeline: [
        { $match: { $expr: { $regexMatch: { input: "$restaurant_name", regex: "$$cname", options: "i" } } } },
        { $group: { _id: null, count: { $sum: 1 }, avg_rating: { $avg: "$rating" }, avg_price: { $avg: "$average_price" } } }
      ],
      as: "india"
  }},
  { $project: {
      _id: 0,
      retezec: "$_id",
      usa: {
        poboček: "$usa_count",
        statu:   { $size: "$usa_staty" }
      },
      dubai: {
        poboček:    { $ifNull: [{ $arrayElemAt: ["$dubai.count",   0] }, 0] },
        avg_sentiment: { $round: [{ $ifNull: [{ $arrayElemAt: ["$dubai.avg_pol", 0] }, 0] }, 3] }
      },
      india: {
        poboček:    { $ifNull: [{ $arrayElemAt: ["$india.count",      0] }, 0] },
        avg_rating: { $round: [{ $ifNull: [{ $arrayElemAt: ["$india.avg_rating", 0] }, 0] }, 2] },
        avg_cena_inr: { $round: [{ $ifNull: [{ $arrayElemAt: ["$india.avg_price", 0] }, 0] }, 0] }
      },
      globalni_datasety: {
        $sum: [
          { $cond: [{ $gt: ["$usa_count", 0] }, 1, 0] },
          { $cond: [{ $gt: [{ $size: "$dubai" }, 0] }, 1, 0] },
          { $cond: [{ $gt: [{ $size: "$india" }, 0] }, 1, 0] }
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
            _id:           null,
            dubai_indian:  { $sum: 1 },
            avg_polarity:  { $avg: "$polarity" }
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
        indickych_v_dubaji: { $ifNull: ["$dubai_indian_kontext.dubai_indian", 0] },
        avg_sentiment:      { $round: [{ $ifNull: ["$dubai_indian_kontext.avg_polarity", 0] }, 3] }
      }
  }}
])
```

**Jak dotaz pracuje:** Po agregaci biryani restaurací v Indii se připojí globální statistika o indické kuchyni v Dubaji jako kulturní přesah. `preserveNullAndEmptyArrays: true` zabrání ztrátě dat, i kdyby Dubai neměl žádné indické restaurace.

**Interpretace výsledku:** Hyderabad a Lucknow typicky dominují biryani nabídce. Sentiment indické kuchyně v Dubaji ukazuje, jak jsou indické chutě přijímány v multikulturním prostředí Arabského emirátu.

---

### Dotaz 12 – Geografická zonální analýza: hustota Dubai vs. USA restaurací ($group + $lookup přes souřadnice)

**Zadání:** Seskup Dubai restaurace do geografických zón (zaokrouhlení souřadnic) a zjisti, zda v téže zeměpisné zóně existují i USA fastfood záznamy.

```javascript
db.dubai_restaurants.aggregate([
  { $match: { lat: { $exists: true }, lng: { $exists: true } } },
  { $group: {
      _id: {
        lat_bin: { $floor: "$lat" },
        lng_bin: { $floor: "$lng" }
      },
      dubai_count:  { $sum: 1 },
      avg_polarity: { $avg: "$polarity" },
      kategorie:    { $addToSet: "$category" }
  }},
  { $lookup: {
      from: "usa_fastfood",
      let:  { lat_b: "$_id.lat_bin", lng_b: "$_id.lng_bin" },
      pipeline: [
        { $match: { $expr: { $and: [
            { $eq: [{ $floor: "$latitude"  }, "$$lat_b"] },
            { $eq: [{ $floor: "$longitude" }, "$$lng_b"] }
        ]}}},
        { $count: "usa_v_zone" }
      ],
      as: "usa_zona"
  }},
  { $project: {
      _id: 0,
      lat_zona:           "$_id.lat_bin",
      lng_zona:           "$_id.lng_bin",
      dubai_count:        1,
      avg_polarity:       { $round: ["$avg_polarity", 3] },
      pestrost_kategorii: { $size: "$kategorie" },
      usa_restauraci_v_zone: { $ifNull: [{ $arrayElemAt: ["$usa_zona.usa_v_zone", 0] }, 0] }
  }},
  { $sort: { dubai_count: -1 } },
  { $limit: 10 }
])
```

**Jak dotaz pracuje:** Koordináty jsou zaokrouhleny dolů na celá čísla – vzniknou buňky přibližně 111×111 km. `$lookup` poté pro každou buňku počítá, kolik USA záznamů leží ve stejné zóně. Výsledek odhalí geografické překryvy nebo ukazuje, jak jsou datasety prostorově odlišné.

**Interpretace výsledku:** Dubai leží přibližně na souřadnicích lat 25, lng 55. USA záznamy mají lng kolem -70 až -120. Výsledek tedy potvrdí nulový překryv a ukáže distribuci Dubai dat po čtvercové síti.

---

## KATEGORIE 3: Transformace a obohacení dat

---

### Dotaz 13 – Přidání sentiment štítků + $unset technických polí + přehled kvality dat

**Zadání:** Obohať Dubai záznamy o štítek kvality sentimentu, odstraň technická pole (details, reviews, id) a agreguj statistiku kvality dat (kolik % záznamů má souřadnice, subCategory).

```javascript
db.dubai_restaurants.aggregate([
  { $addFields: {
      sentiment_stitek: {
        $switch: {
          branches: [
            { case: { $gt: ["$polarity",  0.5]  }, then: "Velmi pozitivní" },
            { case: { $gt: ["$polarity",  0.1]  }, then: "Pozitivní"       },
            { case: { $gt: ["$polarity", -0.1]  }, then: "Neutrální"       },
            { case: { $gt: ["$polarity", -0.5]  }, then: "Negativní"       }
          ],
          default: "Velmi negativní"
        }
      },
      ma_souradnice: { $and: [{ $ne: ["$lat", null] }, { $ne: ["$lng", null] }] },
      ma_subkategorii: { $ne: ["$subCategory", null] }
  }},
  { $unset: ["details", "reviews", "id"] },
  { $group: {
      _id:                "$sentiment_stitek",
      pocet:              { $sum: 1 },
      avg_polarity:       { $avg: "$polarity" },
      kategorie_list:     { $addToSet: "$category" },
      se_souradnicemi:    { $sum: { $cond: ["$ma_souradnice",    1, 0] } },
      se_subkategorii:    { $sum: { $cond: ["$ma_subkategorii", 1, 0] } }
  }},
  { $sort: { avg_polarity: -1 } },
  { $project: {
      _id: 0,
      sentiment:       "$_id",
      pocet:           1,
      avg_polarity:    { $round: ["$avg_polarity", 4] },
      pestrost_kat:    { $size: "$kategorie_list" },
      souradnice_pct:  { $round: [{ $multiply: [{ $divide: ["$se_souradnicemi", "$pocet"] }, 100] }, 1] },
      subkat_pct:      { $round: [{ $multiply: [{ $divide: ["$se_subkategorii", "$pocet"] }, 100] }, 1] }
  }}
])
```

**Jak dotaz pracuje:** `$addFields` přidá tři nová pole bez zápisu do databáze. `$unset` odstraní technické URL pole z pipeline (nezapisuje do DB). `$group` poté agreguje čistá data. Ukazuje vzor transformace „in-pipeline" bez side-effectů.

**Interpretace výsledku:** Výsledek ukáže, jaký podíl záznamů v každé sentiment skupině má kompletní geodata a kategorii. Záznamy bez souřadnic nemohou být použity v mapových vizualizacích.

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
            { $cond: [{ $eq: ["$south_indian_or_not", 1] }, "South Indian", "$$REMOVE"] },
            { $cond: [{ $eq: ["$north_indian_or_not", 1] }, "North Indian", "$$REMOVE"] },
            { $cond: [{ $eq: ["$fast_food_or_not",   1] }, "Fast Food",    "$$REMOVE"] },
            { $cond: [{ $eq: ["$street_food",         1] }, "Street Food",  "$$REMOVE"] },
            { $cond: [{ $eq: ["$biryani_or_not",      1] }, "Biryani",      "$$REMOVE"] },
            { $cond: [{ $eq: ["$bakery_or_not",       1] }, "Bakery",       "$$REMOVE"] }
          ],
          as:   "tag",
          cond: { $ne: ["$$tag", "$$REMOVE"] }
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
      sub_norm:      { $trim: { input: { $toLower: "$subCategory" } } },
      polarity_band: {
        $cond: {
          if:   { $gt: ["$polarity", 0] },
          then: "pozitivni",
          else: {
            $cond: {
              if:   { $lt: ["$polarity", 0] },
              then: "negativni",
              else: "neutralni"
            }
          }
        }
      }
  }},
  { $group: {
      _id:   { sub: "$sub_norm", band: "$polarity_band" },
      count: { $sum: 1 },
      nazvy: { $push: "$name" }
  }},
  { $group: {
      _id:   "$_id.sub",
      total: { $sum: "$count" },
      distribuce: {
        $push: {
          band:   "$_id.band",
          count:  "$count",
          ukazky: { $slice: ["$nazvy", 2] }
        }
      }
  }},
  { $sort: { total: -1 } },
  { $limit: 12 },
  { $project: {
      _id: 0,
      subkategorie:    "$_id",
      celkem:          "$total",
      sentiment_dist:  "$distribuce"
  }}
])
```

**Jak dotaz pracuje:** Dvojúrovňový `$group` – první seskupuje podle kombinace (subkategorie, sentiment_band), druhý přeskupí výsledky jen podle subkategorie a vloží sentiment distribuci jako vnořené pole. Vzor „pivot" agregace v MongoDB.

**Interpretace výsledku:** Pro každou subkategorii (např. „coffee shop", „hotel", „bakery") ukazuje, jaký podíl restaurací má pozitivní vs. negativní sentiment. Subkategorie s vysokým podílem negativního sentimentu jsou oblasti, kde Dubaj zaostává za očekáváním zákazníků.

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
// Krok 1: Zobraz dostupné indexy na kolekci
db.dubai_restaurants.getIndexes()

// Krok 2: explain pro agregační dotaz
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
// Varianta A: Dotaz s compound indexem (efektivní pro range query)
db.dubai_restaurants.find(
  { category: "restaurant", polarity: { $gt: 0 } },
  { name: 1, polarity: 1, _id: 0 }
).hint({ category: 1, polarity: -1 }).explain("executionStats")

// Varianta B: Dotaz bez hint – MongoDB zvolí plán sám
db.dubai_restaurants.find(
  { category: "restaurant", polarity: { $gt: 0 } },
  { name: 1, polarity: 1, _id: 0 }
).explain("executionStats")

// Varianta C: Přímé vynucení hashed indexu (shard key)
db.dubai_restaurants.find(
  { name: "McDonald's" }
).hint({ name: "hashed" }).explain("executionStats")
```

**Jak dotaz pracuje:** `hint()` přepisuje query planner a vynutí použití konkrétního indexu. Hashed index je optimální pro **equality** dotazy na shard key (přesná shoda), ale nepomůže při range dotazech (`$gt`, `$lt`). Compound index je naopak efektivní pro range dotazy s prefixem.

**Interpretace výsledku:** Varianta A by měla vykazovat nejnižší `totalDocsExamined` pro range dotaz. Varianta C ukáže, že hashed index je efektivní pro přesnou shodu jména, ale nemůže být použit pro range podmínky – MongoDB by v takovém případě provedl COLLSCAN.

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
      _id:          "$zona",
      pocet:        { $sum: 1 },
      avg_polarity: { $avg: "$polarity" },
      kategorie:    { $addToSet: "$category" },
      ukazky:       { $push: "$name" }
  }},
  { $sort: { pocet: -1 } },
  { $project: {
      _id: 0,
      zona:          "$_id",
      pocet_restauraci: "$pocet",
      avg_sentiment: { $round: ["$avg_polarity", 3] },
      pestrost_kat:  { $size: "$kategorie" },
      ukazky:        { $slice: ["$ukazky", 3] }
  }}
])
```

**Jak dotaz pracuje:** `$match` na dvou číselných polích `lat` a `lng` s range podmínkami využívá compound index `{ lat: 1, lng: 1 }` – MongoDB prohledá jen relevantní část B-tree indexu. `$addFields` se `$switch` pak přiřadí každé restauraci konkrétní dubajskou čtvrť.

**Interpretace výsledku:** Výsledek ukáže rozložení a sentiment restaurací v různých dubajských čtvrtích. Turisticky orientované oblasti (JBR, Marina) typicky vykazují vyšší sentiment než okrajové oblasti.

---

### Dotaz 24 – explain() compound index { location: 1, rating: -1 } + targeted dotaz na Mumbaj

**Zadání:** Ověř efektivitu compound indexu pro dotaz na indické restaurace v Mumbaji s hodnocením ≥ 4.0. Zobraz top 5 restaurací a exekuční statistiky.

```javascript
// Krok 1: Targeted dotaz s explain
db.indian_restaurants.find(
  { location: "Mumbai", rating: { $gte: 4.0 } }
).hint({ location: 1, rating: -1 }).sort({ rating: -1, average_price: 1 }).explain("executionStats")

// Krok 2: Analytický dotaz s výsledky (bez explain)
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

db.chunks.aggregate([
  { $match: {
      ns: { $in: [
        "restaurants.dubai_restaurants",
        "restaurants.usa_fastfood",
        "restaurants.indian_restaurants"
      ]}
  }},
  { $group: {
      _id:         { ns: "$ns", shard: "$shard" },
      pocet_chunku: { $sum: 1 }
  }},
  { $group: {
      _id:          "$_id.ns",
      shardy: {
        $push: { shard: "$_id.shard", chunky: "$pocet_chunku" }
      },
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

**Jak dotaz pracuje:** `config.chunks` je systémová kolekce MongoDB která eviduje všechny chunky clusteru. Dvojúrovňový `$group` nejprve sečte chunky per (kolekce, shard) kombinaci, poté seskupí per kolekci s polem distribuce. Výsledek je dostupný pouze přes `mongos` nebo přes config server.

**Interpretace výsledku:** Rovnoměrná distribuce (stejný počet chunků na každém shardu) znamená, že balancer funguje správně. Odchylka > 2× naznačuje nevyvážený shard key nebo příliš velké chunky – záznamy se hromadí na jednom shardu (hotspot).

---

### Dotaz 26 – $collStats: storage statistiky a počty dokumentů na shardech

**Zadání:** Pro každou kolekci zjisti storage statistiky (velikost dat, počet dokumentů, průměrná velikost dokumentu) a aktuální stav indexů.

```javascript
use restaurants

// Dubai statistiky
db.dubai_restaurants.aggregate([
  { $collStats: {
      storageStats: { scale: 1024 },
      count:        {}
  }}
])

// USA statistiky
db.usa_fastfood.aggregate([
  { $collStats: {
      storageStats: { scale: 1024 },
      count:        {}
  }}
])

// India statistiky
db.indian_restaurants.aggregate([
  { $collStats: {
      storageStats: { scale: 1024 },
      count:        {}
  }}
])
```

**Jak dotaz pracuje:** `$collStats` je speciální aggregation stage (ne standardní fáze pipeline), která vrátí metadata o kolekci místo dokumentů dat. Při volání přes `mongos` vrátí statistiky každého shardu zvlášť – vidíme rozložení dat. `scale: 1024` převede bajty na kilobajty.

**Interpretace výsledku:** Výsledek obsahuje `count` (počet dokumentů), `storageSize` (fyzická velikost), `avgObjSize` (průměrná velikost dokumentu) a `nindexes` (počet indexů). Per-shard breakdown odhalí nerovnoměrné rozložení dat – větší shardové fragmenty na jednom uzlu indikují nevyvážený cluster.

---

### Dotaz 27 – Přehled stavu clusteru: listShards + serverStatus + sh.status()

**Zadání:** Zobraz kompletní přehled stavu MongoDB sharded clusteru – seznam shardů, jejich stav, verze a konfiguraci balanceru.

```javascript
// Krok 1: Seznam shardů a jejich stav
use admin
db.adminCommand({ listShards: 1 })

// Krok 2: Stav mongos serveru
db.adminCommand({ serverStatus: 1 })

// Krok 3: Kompletní přehled shardingu (přes mongos)
sh.status()

// Krok 4: Konfigurace balanceru
use config
db.settings.find({ _id: "balancer" }).pretty()
db.settings.find({ _id: "chunksize" }).pretty()

// Krok 5: Přehled kolekcí a jejich shard keys
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
// Připojení přímo na shard (ne přes mongos)
// mongosh --host shard1-1 --port 27018 -u admin -p RestCluster2024! --authenticationDatabase admin

// Krok 1: Kompletní stav replica setu
rs.status()

// Krok 2: Přehled replication lag pro každý člen
rs.status().members.forEach(function(m) {
  print("Člen: " + m.name +
        " | Stav: " + m.stateStr +
        " | Optime: " + (m.optimeDate ? m.optimeDate : "N/A") +
        " | Lag: " + (m.lastHeartbeatMessage || "primary/self"));
})

// Krok 3: Replication lag v sekundách (porovnání optimeDate primary vs secondary)
var status    = rs.status();
var primary   = status.members.find(m => m.stateStr === "PRIMARY");
var secondary = status.members.find(m => m.stateStr === "SECONDARY");
if (primary && secondary) {
  var lagSec = (primary.optimeDate - secondary.optimeDate) / 1000;
  print("Replication lag: " + lagSec + " sekund");
}

// Krok 4: Konfigurace replica setu
rs.conf()
```

**Jak dotaz pracuje:** `rs.status()` vrátí aktuální stav všech členů replica setu včetně posledního aplikovaného oplog záznamu (`optimeDate`). Replication lag = rozdíl `optimeDate` primary vs. secondary v milisekundách. Nulový nebo velmi malý lag znamená, že secondary jsou synchronizovány.

**Interpretace výsledku:** V klidném clusteru bez zátěže by replication lag měl být < 1 sekunda. Záznamy s `stateStr: "SECONDARY"` a `health: 1` indikují zdravý stav. `rs.conf()` potvrdí konfiguraci voličů (votes) a priorit členů.

---

### Dotaz 29 – Simulace výpadku primary uzlu (rs.stepDown) + sledování nové volby

**Zadání:** Nasimuluj výpadek primary uzlu v replica setu rs1 pomocí `rs.stepDown()`. Sleduj průběh volby nového primary a ověř, že cluster zůstane dostupný.

```javascript
// ===== PŘÍPRAVA: Připojit se přímo na shard1-1 (aktuální primary) =====
// mongosh --host shard1-1 --port 27018 -u admin -p RestCluster2024! --authenticationDatabase admin

// Krok 1: Ověř, kdo je primary před výpadkem
rs.isMaster()

// Krok 2: Vyvolej stepDown (primary se vzdá role na 60 sekund)
// Upozornění: tím se přeruší aktuální připojení
rs.stepDown(60)

// Krok 3: Po reconnect – zjisti nového primary (může trvat 10-30 sekund)
// Znovu spusť: mongosh --host shard1-1 --port 27018 ...
rs.status()

// Krok 4: Ověř dostupnost z mongos i po výpadku
// Připojit přes mongos:
// mongosh --host mongos --port 27017 -u admin -p RestCluster2024! --authenticationDatabase admin
use restaurants
db.dubai_restaurants.countDocuments()
db.dubai_restaurants.findOne({ polarity: { $gt: 0.5 } })

// Krok 5: Sleduj stav replica setu každých 5 sekund
var i = 0;
while (i < 6) {
  var s = rs.status();
  s.members.forEach(function(m) {
    print(m.name + " -> " + m.stateStr);
  });
  print("---");
  sleep(5000);
  i++;
}

// Krok 6: Ověř oplog pro případ ztráty zápisu
use local
db.oplog.rs.find().sort({ $natural: -1 }).limit(5).pretty()
```

**Jak dotaz pracuje:** `rs.stepDown()` je bezpečná metoda simulace výpadku – primary se dobrovolně vzdá role a spustí se election protokol (Raft-based). Zbývající dva secondary uzly (musejí mít quorum = 2 z 3 hlasů) zvolí nového primary. Celý proces typicky trvá 10–30 sekund. Data jsou při tomto procesu dostupná přes mongos díky read-preference `primaryPreferred`.

**Interpretace výsledku:** Po `rs.stepDown()` jeden ze secondary uzlů přejde do stavu `PRIMARY`. Původní primary se vrátí jako `SECONDARY`. Dotazy přes mongos (`countDocuments()`) by měly stále fungovat – to je důkazem vysoké dostupnosti (HA) replica set architektury. Nulová ztráta dat potvrzuje durability zápisů.

---

### Dotaz 30 – Balancer statistiky a validace dat: chunk migrace + schema compliance

**Zadání:** Zkontroluj historii migrací balanceru v config databázi a ověř konzistenci dat oproti validačnímu schématu (počet dokumentů bez povinných polí).

```javascript
// Krok 1: Historie migrací chunků (balancer log)
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

// Krok 2: Validace – záznamy bez povinných polí v dubai_restaurants
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

// Krok 3: Počty dokumentů na jednotlivých shardech (per kolekce)
db.dubai_restaurants.aggregate([
  { $collStats: { count: {} } },
  { $project: { shard: 1, count: 1, _id: 0 } }
])
```

**Jak dotaz pracuje:** `config.changelog` uchovává historii všech balancer operací. `$match` na `what: "moveChunk.commit"` filtruje dokončené migrace za posledních 24 hodin. Druhá část pipeline ověří datovou konzistenci – spočítá, kolik dokumentů porušuje validační schéma (chybějící povinná pole). Třetí část ukáže aktuální rozložení počtů dokumentů na shardech přes `$collStats`.

**Interpretace výsledku:** Nulový nebo nízký počet migrací = cluster je v rovnováze, balancer nepotřebuje přesouvat chunky. Nenulový počet chybějících povinných polí ukazuje, že data byla importována před aktivací validačního schématu s `validationAction: "error"`. Počty dokumentů na shardech by měly být přibližně rovnoměrné (±20 %) – to potvrzuje, že hashed shard key efektivně distribuuje data.
