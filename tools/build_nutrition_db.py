#!/usr/bin/env python3
"""Genera assets/db/nutrition.db a partir de USDA FoodData Central (SR Legacy).

Uso:
    python tools/build_nutrition_db.py                 # descarga y construye
    python tools/build_nutrition_db.py --src carpeta   # usa CSV ya descargados

La salida es una base SQLite con las tablas que lee la app:
    nutrient, food, food_nutrient, food_portion, meta
"""
from __future__ import annotations

import argparse
import io
import os
import re
import sqlite3
import sys
import unicodedata
import urllib.request
import zipfile
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))
from es_dictionary import (  # noqa: E402
    CATEGORY_MAP,
    EXCLUDED_CATEGORIES,
    PORTION_WORDS,
    SEARCH_ALIASES,
    SEGMENTS,
    WORDS,
)

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "db" / "nutrition.db"
CACHE = Path(__file__).resolve().parent / "_cache"

SR_URLS = [
    "https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_csv_2018-04.zip",
    "https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_csv_%202019-04-02.zip",
]

# id app, código, nombre, unidad, tipo, ids FDC (en orden de preferencia)
NUTRIENTS = [
    (1, "energy_kcal", "Energía", "kcal", "macro", [1008, 2047, 2048]),
    (2, "protein_g", "Proteínas", "g", "macro", [1003]),
    (3, "fat_g", "Grasas totales", "g", "macro", [1004]),
    (4, "sat_fat_g", "Grasas saturadas", "g", "macro", [1258]),
    (5, "carbs_g", "Carbohidratos", "g", "macro", [1005, 1050]),
    (6, "fiber_g", "Fibra", "g", "macro", [1079]),
    (7, "sugars_g", "Azúcares totales", "g", "macro", [2000, 1063]),
    (8, "sodium_mg", "Sodio", "mg", "micro", [1093]),
    (9, "potassium_mg", "Potasio", "mg", "micro", [1092]),
    (10, "calcium_mg", "Calcio", "mg", "micro", [1087]),
    (11, "iron_mg", "Hierro", "mg", "micro", [1089]),
    (12, "magnesium_mg", "Magnesio", "mg", "micro", [1090]),
    (13, "zinc_mg", "Zinc", "mg", "micro", [1095]),
    (14, "vit_a_ug", "Vitamina A (RAE)", "µg", "micro", [1106]),
    (15, "vit_c_mg", "Vitamina C", "mg", "micro", [1162]),
    (16, "vit_d_ug", "Vitamina D", "µg", "micro", [1114]),
    (17, "vit_b12_ug", "Vitamina B12", "µg", "micro", [1178]),
    (18, "folate_ug", "Folato (DFE)", "µg", "micro", [1190]),
]

US_CUP_ML = 236.588
US_TBSP_ML = 14.787
US_TSP_ML = 4.929
US_FLOZ_ML = 29.574


# ----------------------------------------------------------------- texto

def normalize(s: str) -> str:
    s = s.lower()
    s = unicodedata.normalize("NFKD", s)
    return "".join(c for c in s if not unicodedata.combining(c))


def _word_translate(seg: str) -> str | None:
    words = seg.split()
    if not words or not all(w in WORDS for w in words):
        return None
    return " ".join(WORDS[w] for w in words)


def translate_description(desc: str) -> str | None:
    """Traduce una descripción de SR. Devuelve None si no se pudo traducir
    el alimento principal (primer segmento)."""
    segs = [s.strip() for s in desc.split(",") if s.strip()]
    low = [s.lower() for s in segs]
    out: list[str] = []
    i = 0
    head_ok = False
    while i < len(segs):
        matched = False
        for n in range(min(4, len(segs) - i), 0, -1):
            key = ", ".join(low[i : i + n])
            if key in SEGMENTS:
                out.append(SEGMENTS[key])
                if i == 0:
                    head_ok = True
                i += n
                matched = True
                break
        if matched:
            continue
        w = _word_translate(low[i])
        if w is not None:
            out.append(w)
            if i == 0:
                head_ok = True
        else:
            out.append(segs[i])
        i += 1
    if not head_ok:
        return None
    name = ", ".join(out)
    return name[0].upper() + name[1:]


def search_text(name_en: str, name_es: str | None) -> str:
    low = name_en.lower()
    extra = [v for k, v in SEARCH_ALIASES.items() if re.search(rf"\b{re.escape(k)}", low)]
    return normalize(" ".join([name_en, name_es or "", *extra]))


def portion_label(amount: float, modifier: str, description: str) -> str:
    text = (modifier or description or "").strip()
    low = text.lower()
    # Primero frases largas, después palabras.
    for k in sorted(PORTION_WORDS, key=len, reverse=True):
        low = re.sub(rf"\b{re.escape(k)}\b", PORTION_WORDS[k], low)
    amt = f"{amount:g}".replace(".", ",") if amount else "1"
    return f"{amt} {low}".strip()


def shop_category(usda_cat: str) -> str:
    for key, val in CATEGORY_MAP:
        if key.lower() in (usda_cat or "").lower():
            return val
    return "Almacén"


# ----------------------------------------------------------------- datos

def find_csv(base: Path, name: str) -> Path:
    hits = list(base.rglob(name))
    if not hits:
        raise FileNotFoundError(f"No encontré {name} en {base}")
    return hits[0]


def download_sr() -> Path:
    target = CACHE / "sr_legacy"
    if any(target.rglob("food.csv")):
        return target
    target.mkdir(parents=True, exist_ok=True)
    last_err: Exception | None = None
    for url in SR_URLS:
        try:
            print(f"Descargando {url}")
            req = urllib.request.Request(url, headers={"User-Agent": "recetas-app-build"})
            with urllib.request.urlopen(req, timeout=180) as r:
                data = r.read()
            zipfile.ZipFile(io.BytesIO(data)).extractall(target)
            return target
        except Exception as e:  # noqa: BLE001
            print(f"  falló: {e}")
            last_err = e
    raise RuntimeError(f"No se pudo descargar SR Legacy: {last_err}")


def build(src: Path, out: Path) -> None:
    food = pd.read_csv(find_csv(src, "food.csv"), low_memory=False)
    fn = pd.read_csv(find_csv(src, "food_nutrient.csv"), low_memory=False,
                     usecols=["fdc_id", "nutrient_id", "amount"])
    cats = pd.read_csv(find_csv(src, "food_category.csv"))
    try:
        portions = pd.read_csv(find_csv(src, "food_portion.csv"), low_memory=False)
    except FileNotFoundError:
        portions = pd.DataFrame(columns=["fdc_id", "amount", "modifier",
                                         "portion_description", "gram_weight"])

    cat_name = dict(zip(cats["id"], cats["description"]))
    food["usda_cat"] = food["food_category_id"].map(cat_name).fillna("")
    mask = ~food["usda_cat"].apply(lambda c: any(x.lower() in c.lower() for x in EXCLUDED_CATEGORIES))
    food = food[mask].copy()
    print(f"Alimentos: {len(food)}")

    # --- nutrientes
    fdc_to_app: dict[int, tuple[int, int]] = {}
    for app_id, _code, _n, _u, _k, fdc_ids in NUTRIENTS:
        for rank, f in enumerate(fdc_ids):
            fdc_to_app[f] = (app_id, rank)
    fn = fn[fn["nutrient_id"].isin(fdc_to_app.keys()) & fn["fdc_id"].isin(food["fdc_id"])].copy()
    fn["app_id"] = fn["nutrient_id"].map(lambda x: fdc_to_app[x][0])
    fn["rank"] = fn["nutrient_id"].map(lambda x: fdc_to_app[x][1])
    fn = fn.dropna(subset=["amount"])
    fn = fn.sort_values("rank").drop_duplicates(["fdc_id", "app_id"], keep="first")

    # --- porciones y densidad
    portions = portions[portions["fdc_id"].isin(food["fdc_id"])].copy()
    for col, default in (("modifier", ""), ("portion_description", ""), ("amount", 1)):
        if col not in portions.columns:
            portions[col] = default
    portions["modifier"] = portions["modifier"].fillna("").astype(str)
    portions["portion_description"] = portions["portion_description"].fillna("").astype(str)
    portions["amount"] = pd.to_numeric(portions["amount"], errors="coerce").fillna(1)
    portions["gram_weight"] = pd.to_numeric(portions["gram_weight"], errors="coerce")
    portions = portions.dropna(subset=["gram_weight"])
    portions = portions[portions["gram_weight"] > 0]

    density: dict[int, float] = {}
    for fdc_id, grp in portions.groupby("fdc_id"):
        for unit_ml, pat in ((US_CUP_ML, r"^cups?\b"), (US_TBSP_ML, r"^tbsp\b"),
                             (US_TSP_ML, r"^tsp\b"), (US_FLOZ_ML, r"^fl oz\b")):
            hit = grp[grp["modifier"].str.lower().str.match(pat)]
            if len(hit):
                row = hit.iloc[0]
                d = row["gram_weight"] / (row["amount"] * unit_ml)
                if 0.1 <= d <= 2.0:
                    density[int(fdc_id)] = round(float(d), 4)
                break

    # --- escribir
    out.parent.mkdir(parents=True, exist_ok=True)
    if out.exists():
        out.unlink()
    con = sqlite3.connect(out)
    cur = con.cursor()
    cur.executescript(
        """
        CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);
        CREATE TABLE nutrient (
          id INTEGER PRIMARY KEY, code TEXT UNIQUE NOT NULL, name_es TEXT NOT NULL,
          unit TEXT NOT NULL, kind TEXT NOT NULL, display_order INTEGER NOT NULL);
        CREATE TABLE food (
          id INTEGER PRIMARY KEY, name_es TEXT, name_en TEXT NOT NULL,
          category TEXT NOT NULL, source TEXT NOT NULL, source_id TEXT,
          density_g_ml REAL, edible_fraction REAL NOT NULL DEFAULT 1.0,
          search_text TEXT NOT NULL);
        CREATE TABLE food_nutrient (
          food_id INTEGER NOT NULL, nutrient_id INTEGER NOT NULL, per_100g REAL NOT NULL,
          PRIMARY KEY (food_id, nutrient_id)) WITHOUT ROWID;
        CREATE TABLE food_portion (
          id INTEGER PRIMARY KEY, food_id INTEGER NOT NULL, label TEXT NOT NULL, grams REAL NOT NULL);
        """
    )
    cur.executemany(
        "INSERT INTO nutrient VALUES (?,?,?,?,?,?)",
        [(a, c, n, u, k, a) for a, c, n, u, k, _ in NUTRIENTS],
    )

    translated = 0
    rows = []
    for r in food.itertuples(index=False):
        fid = int(r.fdc_id)
        name_en = str(r.description)
        name_es = translate_description(name_en)
        translated += name_es is not None
        rows.append((fid, name_es, name_en, shop_category(r.usda_cat), "fdc_sr", str(fid),
                     density.get(fid), 1.0, search_text(name_en, name_es)))
    cur.executemany("INSERT INTO food VALUES (?,?,?,?,?,?,?,?,?)", rows)

    cur.executemany(
        "INSERT INTO food_nutrient VALUES (?,?,?)",
        [(int(a), int(b), float(c)) for a, b, c in fn[["fdc_id", "app_id", "amount"]].itertuples(index=False)],
    )

    prow = []
    seen = set()
    for r in portions.itertuples(index=False):
        label = portion_label(float(r.amount), r.modifier, r.portion_description)
        key = (int(r.fdc_id), label)
        if key in seen or not label:
            continue
        seen.add(key)
        prow.append((int(r.fdc_id), label, round(float(r.gram_weight), 2)))
    cur.executemany("INSERT INTO food_portion (food_id, label, grams) VALUES (?,?,?)", prow)

    cur.execute("CREATE INDEX idx_portion_food ON food_portion(food_id)")
    cur.executemany("INSERT INTO meta VALUES (?,?)", [
        ("source", "USDA FoodData Central SR Legacy (dominio público)"),
        ("foods", str(len(rows))),
    ])
    con.commit()

    # --- validación
    problems = validate(con)
    con.execute("VACUUM")
    con.close()
    size_mb = out.stat().st_size / 1e6
    print(f"OK {out} · {len(rows)} alimentos · {translated} con nombre en español · "
          f"{len(fn)} valores · {len(prow)} porciones · {size_mb:.1f} MB")
    print(f"Alimentos fuera de tolerancia de kcal (informativo): {problems}")
    if len(rows) < int(os.environ.get("MIN_FOODS", "2000")):
        raise SystemExit("La base tiene menos de 2000 alimentos")


def validate(con: sqlite3.Connection) -> int:
    neg = con.execute("SELECT COUNT(*) FROM food_nutrient WHERE per_100g < 0").fetchone()[0]
    if neg:
        raise SystemExit(f"Hay {neg} valores negativos")
    q = """
    SELECT f.id,
      MAX(CASE WHEN n.nutrient_id=1 THEN n.per_100g END) AS kcal,
      MAX(CASE WHEN n.nutrient_id=2 THEN n.per_100g END) AS p,
      MAX(CASE WHEN n.nutrient_id=3 THEN n.per_100g END) AS g,
      MAX(CASE WHEN n.nutrient_id=5 THEN n.per_100g END) AS c
    FROM food f JOIN food_nutrient n ON n.food_id = f.id GROUP BY f.id
    """
    bad = 0
    for _id, kcal, p, g, c in con.execute(q):
        if None in (kcal, p, g, c) or kcal < 20:
            continue
        est = 4 * p + 4 * c + 9 * g
        if abs(est - kcal) / kcal > 0.15:
            bad += 1
    return bad


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", type=Path, help="carpeta con los CSV de SR Legacy")
    ap.add_argument("--out", type=Path, default=OUT)
    a = ap.parse_args()
    src = a.src or download_sr()
    build(src, a.out)


if __name__ == "__main__":
    main()
