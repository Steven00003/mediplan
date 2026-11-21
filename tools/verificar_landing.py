#!/usr/bin/env python3
"""Verifica la landing estática de MediPlan antes de publicar.

Solo usa la biblioteca estándar. Comprueba metadatos, enlaces, anclas,
imágenes, recursos externos, CSP-compatibilidad y pesos máximos.
"""

from __future__ import annotations

import json
import re
import struct
import sys
import xml.etree.ElementTree as ET
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
BASE = "https://mediplan-35953.web.app"
MAX_FILE = 300 * 1024
MAX_HOME = 500 * 1024
PAGES = sorted(DOCS.glob("*.html"))
RESOURCE_RELS = {"stylesheet", "icon", "apple-touch-icon", "manifest"}

errors: list[str] = []
warnings: list[str] = []


class Page(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.html_attrs: dict[str, str] = {}
        self.title_parts: list[str] = []
        self._in_title = False
        self._title_captured = False
        self.metas: list[dict[str, str]] = []
        self.links: list[dict[str, str]] = []
        self.anchors: list[tuple[str, int]] = []
        self.images: list[tuple[dict[str, str], int]] = []
        self.sources: list[tuple[dict[str, str], int]] = []
        self.headings: list[tuple[int, int]] = []
        self.ids: list[str] = []
        self.scripts = 0
        self.style_tags = 0
        self.style_attrs: list[int] = []
        self.event_attrs: list[int] = []
        self.forbidden_tags: list[tuple[str, int]] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        tag = tag.lower()
        values = {k.lower(): (v or "") for k, v in attrs}
        line = self.getpos()[0]
        if tag == "html":
            self.html_attrs = values
        if "id" in values:
            self.ids.append(values["id"])
        if tag == "title" and not self._title_captured:
            self._in_title = True
        elif tag == "meta":
            self.metas.append(values)
        elif tag == "link":
            self.links.append(values)
        elif tag == "a":
            if values.get("name"):
                self.ids.append(values["name"])
            if "href" in values:
                self.anchors.append((values["href"], line))
        elif tag == "img":
            self.images.append((values, line))
        elif tag == "source":
            self.sources.append((values, line))
        elif tag == "script":
            self.scripts += 1
        elif tag == "style":
            self.style_tags += 1
        elif tag in {"iframe", "object", "embed", "base", "form"}:
            self.forbidden_tags.append((tag, line))
        if re.fullmatch(r"h[1-6]", tag):
            self.headings.append((int(tag[1]), line))
        if "style" in values:
            self.style_attrs.append(line)
        if any(k.startswith("on") for k in values):
            self.event_attrs.append(line)

    def handle_startendtag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        self.handle_starttag(tag, attrs)

    def handle_endtag(self, tag: str) -> None:
        if tag.lower() == "title" and self._in_title:
            self._in_title = False
            self._title_captured = True

    def handle_data(self, data: str) -> None:
        if self._in_title:
            self.title_parts.append(data)


def read_page(path: Path) -> Page:
    parser = Page()
    parser.feed(path.read_text(encoding="utf-8"))
    parser.close()
    return parser


def first_meta(page: Page, *, name: str | None = None, prop: str | None = None) -> str:
    for meta in page.metas:
        if name is not None and meta.get("name", "").lower() == name.lower():
            return meta.get("content", "").strip()
        if prop is not None and meta.get("property", "").lower() == prop.lower():
            return meta.get("content", "").strip()
    return ""


def first_link(page: Page, rel: str) -> str:
    for link in page.links:
        if rel.lower() in link.get("rel", "").lower().split():
            return link.get("href", "").strip()
    return ""


def split_srcset(srcset: str) -> list[str]:
    urls: list[str] = []
    for candidate in srcset.split(","):
        candidate = candidate.strip()
        if candidate:
            urls.append(candidate.split()[0])
    return urls


def local_path(path: str) -> Path | None:
    parsed = urlsplit(path)
    if parsed.scheme or parsed.netloc:
        return None
    return DOCS / unquote(parsed.path.lstrip("/"))


def target_for_href(current: Path, href: str) -> tuple[Path | None, str]:
    parsed = urlsplit(href)
    if parsed.scheme and parsed.scheme not in {"http", "https"}:
        return None, ""
    if parsed.netloc and parsed.netloc not in {"mediplan-35953.web.app"}:
        return None, ""
    if parsed.scheme == "http":
        return None, ""

    raw_path = unquote(parsed.path)
    if not raw_path:
        return current, parsed.fragment
    if raw_path.startswith("/"):
        relative = raw_path.lstrip("/")
    else:
        relative = raw_path

    candidates: list[Path] = []
    if not relative or relative.endswith("/"):
        candidates.append(DOCS / relative / "index.html")
    candidates.append(DOCS / relative)
    if not Path(relative).suffix:
        candidates.append(DOCS / f"{relative}.html")
        candidates.append(DOCS / relative / "index.html")
    for candidate in candidates:
        if candidate.is_file():
            return candidate, parsed.fragment
    return None, parsed.fragment


def png_dimensions(data: bytes) -> tuple[int, int] | None:
    if data[:8] != b"\x89PNG\r\n\x1a\n" or len(data) < 24:
        return None
    return struct.unpack(">II", data[16:24])


def check_page_resources(page: Page, path: Path) -> None:
    seen_urls: list[str] = []
    for attrs, line in page.images:
        seen_urls.append(attrs.get("src", ""))
        seen_urls.extend(split_srcset(attrs.get("srcset", "")))
    for attrs, _line in page.sources:
        seen_urls.extend(split_srcset(attrs.get("srcset", "")))
    for link in page.links:
        rel = link.get("rel", "").lower().split()
        if any(item in RESOURCE_RELS for item in rel):
            seen_urls.append(link.get("href", ""))

    for url in seen_urls:
        if not url or url.startswith("data:"):
            continue
        parsed = urlsplit(url)
        if parsed.scheme or parsed.netloc or url.startswith("//"):
            errors.append(f"{path.name}: recurso externo en {url!r}")
            continue
        target = local_path(url)
        if target is None or not target.is_file():
            errors.append(f"{path.name}: recurso no encontrado {url!r}")


def check_page(path: Path, parsed: Page, pages: dict[Path, Page], titles: dict[str, Path]) -> None:
    name = path.name
    title = " ".join(parsed.title_parts).strip()
    description = first_meta(parsed, name="description")
    canonical = first_link(parsed, "canonical")
    lang = parsed.html_attrs.get("lang", "").strip()
    theme = first_meta(parsed, name="theme-color")
    color_scheme = first_meta(parsed, name="color-scheme")

    if not title:
        errors.append(f"{name}: falta <title>")
    elif title in titles:
        errors.append(f"{name}: <title> repetido con {titles[title].name}")
    else:
        titles[title] = path
    if not description:
        errors.append(f"{name}: falta meta description")
    if not lang:
        errors.append(f"{name}: falta lang en <html>")
    if canonical != BASE + "/" and not canonical.startswith(BASE + "/"):
        errors.append(f"{name}: canonical ausente o fuera de {BASE}")
    if canonical.startswith("http://"):
        errors.append(f"{name}: canonical usa http://")
    if theme.lower() != "#a8e6b0":
        errors.append(f"{name}: theme-color debe ser #A8E6B0")
    if color_scheme != "light dark":
        warnings.append(f"{name}: falta meta color-scheme='light dark'")

    # Open Graph y Twitter.
    for prop, expected in {
        "og:title": title,
        "og:description": description,
        "og:image": f"{BASE}/img/og.png",
        "og:locale": "es_CO",
    }.items():
        value = first_meta(parsed, prop=prop)
        if not value:
            errors.append(f"{name}: falta {prop}")
        elif expected and value != expected:
            errors.append(f"{name}: {prop} no coincide con {expected!r}")
    for prop in ("twitter:card", "twitter:title", "twitter:description", "twitter:image"):
        if not first_meta(parsed, name=prop):
            errors.append(f"{name}: falta {prop}")

    if parsed.scripts:
        errors.append(f"{name}: contiene {parsed.scripts} etiqueta(s) <script>")
    if parsed.style_tags:
        errors.append(f"{name}: contiene {parsed.style_tags} etiqueta(s) <style>")
    if parsed.style_attrs:
        errors.append(f"{name}: contiene atributo(s) style en línea")
    if parsed.event_attrs:
        errors.append(f"{name}: contiene atributo(s) de evento en línea")
    for tag, line in parsed.forbidden_tags:
        errors.append(f"{name}:{line}: etiqueta no permitida <{tag}>")

    raw = path.read_text(encoding="utf-8")
    if "http://" in raw:
        errors.append(f"{name}: contiene una URL http://")

    duplicate_ids = sorted({item for item in parsed.ids if parsed.ids.count(item) > 1})
    if duplicate_ids:
        errors.append(f"{name}: ids duplicados: {', '.join(duplicate_ids)}")

    headings = [level for level, _line in parsed.headings]
    if not headings or headings[0] != 1:
        errors.append(f"{name}: debe empezar con un h1")
    if headings.count(1) != 1:
        errors.append(f"{name}: debe tener exactamente un h1")
    for previous, current in zip(headings, headings[1:]):
        if current - previous > 1:
            errors.append(f"{name}: salto de encabezado h{previous} a h{current}")
            break

    # Imágenes: alt, width, height y archivos existentes.
    for attrs, line in parsed.images:
        if "alt" not in attrs or not attrs.get("alt", "").strip():
            errors.append(f"{name}:{line}: imagen sin alt")
        for dimension in ("width", "height"):
            value = attrs.get(dimension, "")
            if not value.isdigit() or int(value) <= 0:
                errors.append(f"{name}:{line}: imagen sin {dimension} válido")
        src = attrs.get("src", "")
        if not src:
            errors.append(f"{name}:{line}: imagen sin src")
        if attrs.get("width") == "360" and attrs.get("loading") != "lazy":
            errors.append(f"{name}:{line}: la captura debe usar loading='lazy'")

    # Enlaces internos y anclas.
    for href, line in parsed.anchors:
        if href.startswith(("mailto:", "tel:", "javascript:")):
            errors.append(f"{name}:{line}: enlace no permitido {href!r}")
            continue
        if href.startswith("http://"):
            errors.append(f"{name}:{line}: enlace http:// no permitido")
            continue
        target, fragment = target_for_href(path, href)
        if target is None:
            if href.startswith("https://") and not href.startswith(BASE):
                errors.append(f"{name}:{line}: enlace externo {href!r}")
            else:
                errors.append(f"{name}:{line}: enlace interno roto {href!r}")
            continue
        if fragment:
            target_page = pages.get(target)
            if target_page is None:
                errors.append(f"{name}:{line}: no se pudo leer {target.name} para el ancla #{fragment}")
            elif fragment not in target_page.ids:
                errors.append(f"{name}:{line}: ancla inexistente {href!r}")

    check_page_resources(parsed, path)


def main() -> int:
    if not PAGES:
        errors.append("No se encontraron páginas HTML en docs/")
    pages = {path: read_page(path) for path in PAGES}
    titles: dict[str, Path] = {}
    for path, parsed in pages.items():
        check_page(path, parsed, pages, titles)

    # Archivos obligatorios.
    required = [
        "favicon.ico",
        "favicon.svg",
        "apple-touch-icon.png",
        "icon-192.png",
        "icon-512.png",
        "manifest.webmanifest",
        "robots.txt",
        "sitemap.xml",
        "img/og.png",
    ]
    for relative in required:
        if not (DOCS / relative).is_file():
            errors.append(f"Falta docs/{relative}")

    # Iconos y Open Graph.
    icon_sizes = {
        "apple-touch-icon.png": (180, 180),
        "icon-192.png": (192, 192),
        "icon-512.png": (512, 512),
        "img/og.png": (1200, 630),
    }
    for relative, expected in icon_sizes.items():
        path = DOCS / relative
        if path.is_file():
            dimensions = png_dimensions(path.read_bytes())
            if dimensions != expected:
                errors.append(f"docs/{relative}: dimensiones {dimensions}, se esperaban {expected}")

    # Manifiesto.
    manifest_path = DOCS / "manifest.webmanifest"
    if manifest_path.is_file():
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            errors.append(f"manifest.webmanifest: JSON inválido ({exc})")
        else:
            for key in ("name", "short_name", "theme_color", "background_color", "icons"):
                if key not in manifest:
                    errors.append(f"manifest.webmanifest: falta {key}")
            icon_sources = {icon.get("src") for icon in manifest.get("icons", [])}
            for size in ("192", "512"):
                if f"icon-{size}.png" not in icon_sources:
                    errors.append(f"manifest.webmanifest: falta icon-{size}.png")

    # Sitemap: páginas indexables (404 queda fuera por noindex).
    sitemap_path = DOCS / "sitemap.xml"
    if sitemap_path.is_file():
        try:
            root = ET.fromstring(sitemap_path.read_text(encoding="utf-8"))
            locs = {node.text.strip() for node in root.iter() if node.tag.endswith("loc") and node.text}
        except ET.ParseError as exc:
            errors.append(f"sitemap.xml: XML inválido ({exc})")
        else:
            for loc in (f"{BASE}/", f"{BASE}/privacidad"):
                if loc not in locs:
                    errors.append(f"sitemap.xml: falta {loc}")
            if f"{BASE}/404" in locs:
                warnings.append("sitemap.xml: incluye la página 404 (noindex)")

    robots_path = DOCS / "robots.txt"
    if robots_path.is_file():
        robots = robots_path.read_text(encoding="utf-8")
        if f"Sitemap: {BASE}/sitemap.xml" not in robots:
            errors.append("robots.txt: falta la línea Sitemap")

    # CSS: un solo archivo cargado, sin @import ni URL externas.
    css_files = sorted(DOCS.glob("*.css"))
    for css in css_files:
        text = css.read_text(encoding="utf-8")
        if "@import" in text:
            errors.append(f"{css.name}: contiene @import")
        if re.search(r"url\(\s*['\"]?(?:https?:)?//", text, flags=re.I):
            errors.append(f"{css.name}: contiene url() externa")
    linked_styles = set()
    for page in pages.values():
        for link in page.links:
            if "stylesheet" in link.get("rel", "").lower().split():
                linked_styles.add(link.get("href", ""))
    if linked_styles != {"styles.min.css"}:
        errors.append(f"Las páginas deben cargar solo styles.min.css; se encontró {sorted(linked_styles)}")

    # Ningún archivo de docs/ supera 300 KB.
    largest: tuple[int, Path] | None = None
    for path in DOCS.rglob("*"):
        if not path.is_file():
            continue
        size = path.stat().st_size
        if largest is None or size > largest[0]:
            largest = (size, path)
        if size > MAX_FILE:
            errors.append(f"{path.relative_to(ROOT)}: {size} bytes (> 300 KB)")

    # Peso de la portada: HTML + CSS + todas las variantes de imagen referenciadas.
    home_weight = 0
    home_files: set[Path] = set()
    index_path = DOCS / "index.html"
    if index_path in pages:
        home_files.add(index_path)
        index = pages[index_path]
        for link in index.links:
            if "stylesheet" in link.get("rel", "").lower().split():
                target = local_path(link.get("href", ""))
                if target and target.is_file():
                    home_files.add(target)
        urls: list[str] = []
        for attrs, _line in index.images:
            urls.append(attrs.get("src", ""))
            urls.extend(split_srcset(attrs.get("srcset", "")))
        for attrs, _line in index.sources:
            urls.extend(split_srcset(attrs.get("srcset", "")))
        for url in urls:
            target = local_path(url)
            if target and target.is_file() and target.is_relative_to(DOCS):
                home_files.add(target)
        home_weight = sum(path.stat().st_size for path in home_files)
        if home_weight > MAX_HOME:
            errors.append(f"Portada: {home_weight} bytes (> 500 KB)")

    # Informe.
    print("Verificación de la landing de MediPlan")
    print(f"Páginas: {', '.join(path.name for path in PAGES)}")
    print(f"Peso de la portada (HTML + CSS + imágenes): {home_weight} bytes ({home_weight / 1024:.1f} KB)")
    if largest:
        print(f"Archivo más pesado en docs/: {largest[1].relative_to(ROOT)} ({largest[0]} bytes)")
    print(f"CSS cargado: {', '.join(sorted(linked_styles)) or 'ninguno'}")
    print()
    if warnings:
        print("Advertencias:")
        for warning in warnings:
            print(f"  - {warning}")
        print()
    if errors:
        print(f"Errores ({len(errors)}):")
        for error in errors:
            print(f"  - {error}")
        return 1
    print("Resultado: OK. No se encontraron errores.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
