#!/usr/bin/env python3
"""
update_world_leaders.py

Fetches all world leaders (heads of state / heads of government) from Wikipedia
and adds/updates them in the ModernDay scenario (map_data/polities.json and map_data/significant_figures.json).
Also downloads and crops official portraits (512x512 PNG) from Wikipedia for
each leader into starts/ModernDay/assets/portraits/<Country>/<Leader>.png.

Usage:
    python utils/update_world_leaders.py [--dry-run] [--no-portraits] [--force-all] [--no-cache]
"""

import os
import sys
import time
import json
import re
import shutil
import argparse
import unicodedata
import urllib.request
import urllib.parse
from concurrent.futures import ThreadPoolExecutor, as_completed
from io import BytesIO
from bs4 import BeautifulSoup
from PIL import Image

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
MAP_DATA_DIR = os.path.join(REPO_ROOT, "starts", "ModernDay", "map_data")
POLITIES_PATH = os.path.join(MAP_DATA_DIR, "polities.json")
FIGURES_PATH = os.path.join(MAP_DATA_DIR, "significant_figures.json")
PORTRAITS_DIR = os.path.join(REPO_ROOT, "starts", "ModernDay", "assets", "portraits")
CACHE_FILE = os.path.join(REPO_ROOT, "utils", ".wiki_leaders_cache.html")

WIKI_URL = (
    "https://en.wikipedia.org/w/api.php?action=parse&page=List_of_current_heads_of_state_and_government"
    "&format=json&prop=text"
)

BROWSER_UA = (
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/124.0.0.0 Safari/537.36 SpiritsOfSteelMod/1.0"
)

# Explicit mappings from game polity names to Wikipedia state names
POLITY_ALIASES = {
    "Czechia": "Czech Republic",
    "Vatican_city": "Vatican City(Holy See)",
    "Turkish_cyprus": "Northern Cyprus",
    "Libya": "Libya(GNU)",
    "Palestine": "Palestine(Palestinian Authority)",
    "Western_sahara": "Sahrawi Arab Democratic Republic",
    "Sudan": "Sudan(TSC)",
    "Yemen": "Yemen(PLC)",
    "Cabo_verde": "Cape Verde",
    "St_kitts_and_nevis": "Saint Kitts and Nevis",
    "Gambia": "Gambia, The",
    "St_lucia": "Saint Lucia",
    "Dr_congo": "Congo, Democratic Republic of the",
    "Congo": "Congo, Republic of the",
    "Sao_tome_and_principe": "São Tomé and Príncipe",
    "East_timor": "Timor-Leste",
    "United_states": "United States",
    "United_kingdom": "United Kingdom",
    "Bosnia_and_herzegovina": "Bosnia and Herzegovina",
    "San_marino": "San Marino",
    "South_ossetia": "South Ossetia",
    "North_korea": "North Korea",
    "North_macedonia": "North Macedonia",
    "South_korea": "South Korea",
    "Saudi_arabia": "Saudi Arabia",
    "United_arab_emirates": "United Arab Emirates",
    "Dominican_republic": "Dominican Republic",
    "Burkina_faso": "Burkina Faso",
    "El_salvador": "El Salvador",
    "Guinea_bissau": "Guinea-Bissau",
    "South_sudan": "South Sudan",
    "Costa_rica": "Costa Rica",
    "Central_african_republic": "Central African Republic",
    "Trinidad_and_tobago": "Trinidad and Tobago",
    "Ivory_coast": "Ivory Coast",
    "Sierra_leone": "Sierra Leone",
    "Sri_lanka": "Sri Lanka",
    "Papua_new_guinea": "Papua New Guinea",
    "Solomon_islands": "Solomon Islands",
    "South_africa": "South Africa",
    "New_zealand": "New Zealand",
}

SPECIAL_ENTITIES = {
    "Donetsk": {
        "leader_name": "Denis Pushilin",
        "wiki_title": "Denis_Pushilin",
    },
    "Luhansk": {
        "leader_name": "Leonid Pasechnik",
        "wiki_title": "Leonid_Pasechnik",
    },
    "Antartica": {
        "leader_name": "Benito Mussolini",
        "wiki_title": "Benito_Mussolini",
    },
}

EASTER_EGGS = {
    "ExodiaTheForbiddenOne",
    "GavGrub",
    "BenitoMussolini",
}

# Handcrafted real leaders already present
PREEXISTING_REAL_LEADERS = {
    "DonaldJohnTrump",
    "VladimirPutin",
    "XiJinping",
    "AlexanderLukashenko",
    "VolodymyrZelenskyy",
    "JonasGahrStore",
    "Keir_Starmer",
    "FriedrichMerz",
    "EmmanuelMacron",
    "SanaeTakaichi",
    "PedroSanchez",
    "KimJongUn",
    "LeeJaeMyung",
    "MohammedBenElHassan",
    "NarendraModi",
    "BenjaminNetanyahu",
    "ClaudiaSheinbaumPardo",
    "MohammedBinSalman",
    "IbrahimTraore",
    "LuizInacioLulaDaSilva",
}


def normalize_name(s: str) -> str:
    if not s:
        return ""
    nfkd = unicodedata.normalize("NFKD", s)
    ascii_clean = "".join([c for c in nfkd if not unicodedata.combining(c)])
    return re.sub(r"[^a-z0-9]", "", ascii_clean.lower())


def to_pascal_case(name: str) -> str:
    clean = re.sub(r"\[.*?\]", "", name).strip()
    nfkd = unicodedata.normalize("NFKD", clean)
    ascii_clean = "".join([c for c in nfkd if not unicodedata.combining(c)])
    ascii_clean = re.sub(r"[^a-zA-Z0-9\s]", "", ascii_clean)
    words = ascii_clean.split()
    return "".join(w.capitalize() for w in words)


def fetch_wikipedia_html(use_cache: bool = True) -> str:
    if use_cache and os.path.exists(CACHE_FILE):
        print(f"Loading cached Wikipedia HTML from {CACHE_FILE}")
        with open(CACHE_FILE, "r", encoding="utf-8") as f:
            return f.read()

    print("Fetching List_of_current_heads_of_state_and_government from Wikipedia API...")
    req = urllib.request.Request(
        WIKI_URL,
        headers={"User-Agent": BROWSER_UA},
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = json.loads(resp.read().decode("utf-8"))
        html = data["parse"]["text"]["*"]

    with open(CACHE_FILE, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"Cached Wikipedia HTML to {CACHE_FILE}")
    return html


def parse_wikipedia_leaders(html: str) -> dict:
    soup = BeautifulSoup(html, "html.parser")
    wiki_entries = {}
    tables = soup.find_all("table")

    for t_idx in [1, 2, 3, 4]:
        if t_idx >= len(tables):
            continue
        t = tables[t_idx]
        for row in t.find_all("tr"):
            th = row.find("th")
            if not th:
                continue
            state_clean = re.sub(r"\[.*?\]", "", th.get_text(strip=True)).strip()
            tds = row.find_all("td")
            if not tds:
                continue

            exec_cell = None
            for td in tds:
                style = (td.get("style") or "").lower()
                if "9eff9e" in style or "cef" in style:
                    exec_cell = td
                    break
            if not exec_cell:
                exec_cell = tds[0]

            raw_text = re.sub(r"\[.*?\]", "", exec_cell.get_text(strip=True)).strip()

            links = []
            for a in exec_cell.find_all("a"):
                txt = re.sub(r"\[.*?\]", "", a.get_text(strip=True)).strip()
                href = a.get("href", "")
                if (
                    txt
                    and not href.startswith("#")
                    and not any(
                        href.lower().endswith(x)
                        for x in [
                            "_of_state",
                            "presidency",
                            "prime_minister",
                            "president",
                            "chancellor",
                            "monarchy",
                            "monarch",
                        ]
                    )
                ):
                    links.append((txt, href))

            leader_name = ""
            wiki_title = ""
            if links:
                leader_name = links[-1][0]
                wiki_title = urllib.parse.unquote(links[-1][1].replace("/wiki/", ""))
            elif "–" in raw_text:
                leader_name = raw_text.split("–")[-1].strip()
            elif "-" in raw_text:
                leader_name = raw_text.split("-")[-1].strip()
            else:
                leader_name = raw_text

            # Secondary links in other tds as potential fallbacks for photos
            fallback_titles = []
            for other_td in tds:
                for a in other_td.find_all("a"):
                    href = a.get("href", "")
                    if href.startswith("/wiki/") and not any(
                        x in href.lower() for x in ["list_", "prime_minister", "president", "file:", "category:"]
                    ):
                        fallback_titles.append(urllib.parse.unquote(href.replace("/wiki/", "")))

            # Special curated fallbacks for states with unique leadership structures
            if "Afghanistan" in state_clean:
                fallback_titles.append("Hasan_Akhund")
            elif "Sudan" in state_clean:
                fallback_titles.extend(["Abdel_Fattah_al-Burhan", "Kamil_Idris"])
            elif "Bosnia" in state_clean:
                fallback_titles.extend(["Denis_Bećirović", "Željko_Komšić", "Željka_Cvijanović"])

            wiki_entries[state_clean] = {
                "leader_name": leader_name,
                "wiki_title": wiki_title,
                "raw_text": raw_text,
                "fallback_titles": fallback_titles,
            }

    return wiki_entries


def resolve_portrait_path(p_name: str, leader_id: str, real_name: str) -> str:
    target_country_norm = normalize_name(p_name)
    target_norms = {
        normalize_name(leader_id),
        normalize_name(real_name),
        normalize_name(to_pascal_case(real_name)),
    }

    if os.path.exists(PORTRAITS_DIR):
        for d in os.listdir(PORTRAITS_DIR):
            pdir = os.path.join(PORTRAITS_DIR, d)
            if os.path.isdir(pdir) and normalize_name(d) == target_country_norm:
                files = [f for f in os.listdir(pdir) if f.endswith(".png") and not f.startswith(".")]
                for fname in files:
                    f_norm = normalize_name(os.path.splitext(fname)[0])
                    if f_norm in target_norms:
                        return f"res://starts/ModernDay/assets/portraits/{d}/{fname}"
                if len(files) == 1:
                    return f"res://starts/ModernDay/assets/portraits/{d}/{files[0]}"

    return ""


def batch_fetch_thumbnail_urls(wiki_titles: list[str]) -> dict[str, str]:
    """Queries Wikipedia in batches of 50 to get high-res thumbnail image URLs."""
    results = {}
    cleaned_titles = list(set([urllib.parse.unquote(t).strip() for t in wiki_titles if t.strip()]))

    for i in range(0, len(cleaned_titles), 50):
        batch = cleaned_titles[i : i + 50]
        query_str = "|".join([urllib.parse.quote(t) for t in batch])
        api_url = (
            f"https://en.wikipedia.org/w/api.php?action=query&titles={query_str}"
            f"&prop=pageimages&pithumbsize=500&format=json&redirects=1"
        )
        try:
            req = urllib.request.Request(api_url, headers={"User-Agent": BROWSER_UA})
            with urllib.request.urlopen(req, timeout=20) as resp:
                data = json.loads(resp.read().decode("utf-8"))

                redirect_map = {}
                for r in data.get("query", {}).get("redirects", []):
                    redirect_map[r["to"]] = r["from"]
                    redirect_map[r["from"]] = r["to"]

                pages = data.get("query", {}).get("pages", {})
                for page in pages.values():
                    title = page.get("title", "")
                    thumb = page.get("thumbnail", {}).get("source")
                    if thumb:
                        results[normalize_name(title)] = thumb
                        if title in redirect_map:
                            results[normalize_name(redirect_map[title])] = thumb
        except Exception as e:
            print(f"Warning: Batch thumbnail query failed for chunk {i}: {e}")

    return results


def download_and_crop_image(url: str, dest_path: str, retries: int = 3) -> bool:
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": BROWSER_UA})
            time.sleep(0.05)
            with urllib.request.urlopen(req, timeout=20) as resp:
                raw_data = resp.read()
                img = Image.open(BytesIO(raw_data)).convert("RGBA")
                w, h = img.size
                min_dim = min(w, h)
                left = (w - min_dim) // 2
                top = max(0, int((h - min_dim) * 0.15))
                right = left + min_dim
                bottom = top + min_dim
                if bottom > h:
                    bottom = h
                    top = h - min_dim
                cropped = img.crop((left, top, right, bottom)).resize((512, 512), Image.Resampling.LANCZOS)
                os.makedirs(os.path.dirname(dest_path), exist_ok=True)
                cropped.save(dest_path, "PNG")
                return True
        except urllib.error.HTTPError as e:
            if e.code == 429 and attempt < retries - 1:
                time.sleep(1.5 * (attempt + 1))
                continue
            print(f"HTTP Error {e.code} downloading from {url}: {e.reason}")
            return False
        except Exception as e:
            if attempt < retries - 1:
                time.sleep(1.0)
                continue
            print(f"Failed to download/process image from {url}: {e}")
            return False
    return False


def main():
    parser = argparse.ArgumentParser(
        description="Scrape world leaders and portraits from Wikipedia and update ModernDay scenario."
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Simulate the update without modifying map data files or writing images.",
    )
    parser.add_argument(
        "--no-portraits",
        action="store_true",
        help="Skip downloading portraits from Wikipedia.",
    )
    parser.add_argument(
        "--force-all",
        action="store_true",
        help="Overwrite preexisting handcrafted leaders and easter eggs.",
    )
    parser.add_argument(
        "--no-cache",
        action="store_true",
        help="Bypass the local Wikipedia HTML cache and re-download fresh data.",
    )
    args = parser.parse_args()

    download_portraits = not args.no_portraits

    print("=== Spirits of Steel Rebirth: Modern Day World Leaders & Portraits Updater ===")
    print(f"Map data folder: {MAP_DATA_DIR}")
    print(f"Dry run: {args.dry_run}")
    print(f"Download portraits: {download_portraits}")
    print(f"Force all: {args.force_all}")

    for path in (POLITIES_PATH, FIGURES_PATH):
        if not os.path.exists(path):
            print(f"Error: {os.path.basename(path)} not found at {path}")
            sys.exit(1)

    html = fetch_wikipedia_html(use_cache=not args.no_cache)
    wiki_entries = parse_wikipedia_leaders(html)
    wiki_by_norm = {normalize_name(k): v for k, v in wiki_entries.items()}

    with open(POLITIES_PATH, "r", encoding="utf-8") as f:
        polities = json.load(f)
    with open(FIGURES_PATH, "r", encoding="utf-8") as f:
        figures_list = json.load(f)
    figures_map = {f["name"]: f for f in figures_list}

    # Step 1: Collect leader data for each polity
    leaders_to_process = []
    skipped_count = 0

    for polity in polities:
        p_name = polity["name"]
        curr_leader_id = polity.get("government_positions", {}).get("Leader", "")
        curr_fig = figures_map.get(curr_leader_id)

        # Check easter eggs
        if not args.force_all and curr_leader_id in EASTER_EGGS:
            print(f"[{p_name}] Preserving easter egg leader: {curr_leader_id}")
            skipped_count += 1
            continue

        # Check preexisting handcrafted real leaders
        if not args.force_all and curr_leader_id in PREEXISTING_REAL_LEADERS:
            found_portrait = resolve_portrait_path(p_name, curr_leader_id, curr_leader_id)
            if found_portrait and curr_fig:
                curr_fig["portrait_path"] = found_portrait
            print(f"[{p_name}] Preserving handcrafted real leader: {curr_leader_id}")
            skipped_count += 1
            continue

        wiki_info = None
        if p_name in SPECIAL_ENTITIES:
            wiki_info = SPECIAL_ENTITIES[p_name]
        else:
            target_name = POLITY_ALIASES.get(p_name, p_name)
            norm = normalize_name(target_name)
            if norm in wiki_by_norm:
                wiki_info = wiki_by_norm[norm]

        if not wiki_info:
            print(f"[{p_name}] WARNING: Could not find matching leader on Wikipedia!")
            skipped_count += 1
            continue

        real_name = wiki_info["leader_name"]
        wiki_title = wiki_info.get("wiki_title", "")
        fallback_titles = wiki_info.get("fallback_titles", [])
        pascal_id = to_pascal_case(real_name)

        if not pascal_id:
            pascal_id = to_pascal_case(wiki_title) or p_name + "Leader"

        leaders_to_process.append(
            {
                "polity": polity,
                "p_name": p_name,
                "curr_leader_id": curr_leader_id,
                "curr_fig": curr_fig,
                "real_name": real_name,
                "pascal_id": pascal_id,
                "wiki_title": wiki_title,
                "fallback_titles": fallback_titles,
            }
        )

    # Step 2: Query thumbnail URLs in batch
    thumb_urls = {}
    if download_portraits:
        print("\nQuerying Wikipedia API for leader portraits...")
        all_titles_to_query = []
        for item in leaders_to_process:
            if item["wiki_title"]:
                all_titles_to_query.append(item["wiki_title"])
            all_titles_to_query.extend(item["fallback_titles"])

        thumb_urls = batch_fetch_thumbnail_urls(all_titles_to_query)
        print(f"Found {len(thumb_urls)} thumbnail image URLs from Wikipedia.")

    # Step 3: Download images in parallel with ThreadPoolExecutor
    download_tasks = []
    for item in leaders_to_process:
        p_name = item["p_name"]
        pascal_id = item["pascal_id"]
        country_dir_name = p_name.replace("_", "")
        dest_dir = os.path.join(PORTRAITS_DIR, country_dir_name)
        dest_path = os.path.join(dest_dir, f"{pascal_id}.png")

        # Check existing local portrait first
        existing = resolve_portrait_path(p_name, pascal_id, item["real_name"])
        if existing and os.path.exists(existing.replace("res://", f"{REPO_ROOT}/")):
            item["portrait_rel"] = existing
            continue

        # Look for thumbnail in fetched URLs
        img_url = thumb_urls.get(normalize_name(item["wiki_title"]))
        if not img_url:
            for ft in item["fallback_titles"]:
                img_url = thumb_urls.get(normalize_name(ft))
                if img_url:
                    break

        if img_url and download_portraits:
            item["download_info"] = (img_url, dest_path)
            item["portrait_rel"] = f"res://starts/ModernDay/assets/portraits/{country_dir_name}/{pascal_id}.png"
            if not args.dry_run and not os.path.exists(dest_path):
                download_tasks.append((p_name, pascal_id, img_url, dest_path))
        else:
            item["portrait_rel"] = "res://assets/portraits/Fallback.png"

    if download_tasks:
        print(f"\nDownloading and cropping {len(download_tasks)} portraits to 512x512 PNG...")
        with ThreadPoolExecutor(max_workers=4) as executor:
            future_to_info = {
                executor.submit(download_and_crop_image, url, dest): (p_name, pid)
                for p_name, pid, url, dest in download_tasks
            }
            completed = 0
            for future in as_completed(future_to_info):
                p_name, pid = future_to_info[future]
                completed += 1
                try:
                    success = future.result()
                    if success:
                        print(f"[{completed}/{len(download_tasks)}] Saved {pid} ({p_name})")
                    else:
                        print(f"[{completed}/{len(download_tasks)}] Failed {pid} ({p_name})")
                except Exception as exc:
                    print(f"[{completed}/{len(download_tasks)}] Error downloading {pid}: {exc}")

    # Step 4: Apply updates to map_data figures and polities
    updated_count = 0
    for item in leaders_to_process:
        polity = item["polity"]
        p_name = item["p_name"]
        curr_leader_id = item["curr_leader_id"]
        curr_fig = item["curr_fig"]
        pascal_id = item["pascal_id"]
        real_name = item["real_name"]
        portrait_rel = item.get("portrait_rel", "res://assets/portraits/Fallback.png")

        # Verify portrait file actually exists on disk if not dry_run
        if not args.dry_run and portrait_rel != "res://assets/portraits/Fallback.png":
            disk_path = portrait_rel.replace("res://", f"{REPO_ROOT}/")
            if not os.path.exists(disk_path):
                portrait_rel = "res://assets/portraits/Fallback.png"

        skills = curr_fig.get("skills", {}) if curr_fig else {}
        traits = curr_fig.get("traits", []) if curr_fig else []
        ideology = curr_fig.get("ideology", [0, 0]) if curr_fig else [0, 0]
        legitimacy = curr_fig.get("legitimacy", 100) if curr_fig else 100

        new_figure = {
            "name": pascal_id,
            "allegiance": p_name,
            "occupation": "Leader",
            "ideology": ideology,
            "legitimacy": legitimacy,
            "skills": skills,
            "traits": traits,
            "portrait_path": portrait_rel,
            "status": 0,
        }

        print(f"[{p_name}] Leader: '{curr_leader_id}' -> '{pascal_id}' ({real_name}) [Portrait: {portrait_rel}]")

        if curr_leader_id and curr_leader_id in figures_map and curr_leader_id != pascal_id:
            if curr_leader_id not in EASTER_EGGS and curr_leader_id not in PREEXISTING_REAL_LEADERS:
                figures_list = [f for f in figures_list if f["name"] != curr_leader_id]

        figures_map[pascal_id] = new_figure
        figures_list = [f for f in figures_list if f["name"] != pascal_id] + [new_figure]

        polity.setdefault("government_positions", {})["Leader"] = pascal_id
        if "figures" not in polity:
            polity["figures"] = []
        if curr_leader_id in polity["figures"] and curr_leader_id != pascal_id:
            polity["figures"].remove(curr_leader_id)
        if pascal_id not in polity["figures"]:
            polity["figures"].append(pascal_id)

        updated_count += 1

    print(f"\nSummary: {updated_count} polities updated, {skipped_count} skipped/preserved.")

    if not args.dry_run:
        for path, data in ((POLITIES_PATH, polities), (FIGURES_PATH, figures_list)):
            bak_path = path + ".bak"
            print(f"Backing up original {os.path.basename(path)} to {bak_path}")
            shutil.copyfile(path, bak_path)
            with open(path, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=4, ensure_ascii=False)
                f.write("\n")
        print(f"Successfully saved updated data to {MAP_DATA_DIR}!")
    else:
        print("Dry-run complete. No files were modified.")


if __name__ == "__main__":
    main()
