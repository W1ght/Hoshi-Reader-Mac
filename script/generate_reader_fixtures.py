#!/usr/bin/env python3
"""Generate small deterministic EPUB fixtures for Reader regression testing."""

from __future__ import annotations

import argparse
import html
import textwrap
import zipfile
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = ROOT / "testdata" / "reader-fixtures"


JAPANESE_SENTENCES = [
    "星を編む読書室では、静かな午後にページの音だけが残ります。",
    "優斗はノートを開き、社会のしくみとお金の流れについて考えました。",
    "麗子は小さく笑って、次の問いをゆっくり読み上げました。",
    "この文章は縦書き、横書き、ルビ、画像、リンクの検証に使います。",
]


@dataclass(frozen=True)
class Chapter:
    filename: str
    title: str
    body: str


@dataclass(frozen=True)
class Fixture:
    name: str
    title: str
    language: str
    css: str
    chapters: list[Chapter]
    extra_files: dict[str, bytes]


def paragraph(text: str) -> str:
    return f"<p>{html.escape(text)}</p>"


def repeated_paragraphs(count: int) -> str:
    lines = []
    for index in range(count):
        sentence = JAPANESE_SENTENCES[index % len(JAPANESE_SENTENCES)]
        lines.append(paragraph(f"{index + 1:03d}. {sentence}"))
    return "\n".join(lines)


def svg_bytes(label: str, width: int = 900, height: int = 1200) -> bytes:
    escaped = html.escape(label)
    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">
  <rect width="100%" height="100%" fill="#f4ead8"/>
  <rect x="48" y="48" width="{width - 96}" height="{height - 96}" fill="none" stroke="#4d4639" stroke-width="8"/>
  <text x="50%" y="50%" dominant-baseline="middle" text-anchor="middle" font-size="64" fill="#2b2418">{escaped}</text>
</svg>
"""
    return svg.encode("utf-8")


def base_css(extra: str = "") -> str:
    return textwrap.dedent(
        f"""
        body {{
          font-family: serif;
          line-height: 1.75;
        }}
        p {{
          margin: 1em 0;
        }}
        img {{
          max-width: 100%;
          height: auto;
        }}
        ruby {{
          ruby-position: over;
        }}
        {extra}
        """
    ).strip()


def fixture_catalog() -> list[Fixture]:
    cover_svg = svg_bytes("Cover Fixture")
    image_a = svg_bytes("Image A", 1200, 800)
    image_b = svg_bytes("Image B", 800, 1200)

    ruby_body = """
    <p><ruby>星<rt>ほし</rt></ruby>を<ruby>編<rt>あ</rt></ruby>む<ruby>読書室<rt>どくしょしつ</rt></ruby>で、<ruby>優斗<rt>ゆうと</rt></ruby>は<ruby>社会<rt>しゃかい</rt></ruby>の<ruby>仕組<rt>しく</rt></ruby>みを<ruby>考<rt>かんが</rt></ruby>えました。</p>
    <p><ruby>麗子<rt>れいこ</rt></ruby>は<ruby>静<rt>しず</rt></ruby>かに<ruby>頷<rt>うなず</rt></ruby>き、<ruby>言葉<rt>ことば</rt></ruby>の<ruby>意味<rt>いみ</rt></ruby>を<ruby>確<rt>たし</rt></ruby>かめます。</p>
    """ + repeated_paragraphs(16)

    weird_css = base_css(
        """
        body.fixture-weird {
          margin: 12vw !important;
          padding: 4rem !important;
          letter-spacing: 0.08em;
        }
        .oversized {
          width: 180vw;
          border: 4px solid #d66;
          padding: 2rem;
        }
        table {
          width: 140%;
          border-collapse: collapse;
        }
        td {
          border: 1px solid #777;
          padding: 0.5rem;
        }
        pre {
          white-space: pre;
        }
        """
    )

    return [
        Fixture(
            name="plain-horizontal",
            title="Reader Fixture Plain Horizontal",
            language="ja",
            css=base_css(),
            chapters=[
                Chapter("chapter-1.xhtml", "Plain Horizontal", repeated_paragraphs(26)),
                Chapter("chapter-2.xhtml", "Plain Horizontal End", repeated_paragraphs(12)),
            ],
            extra_files={},
        ),
        Fixture(
            name="plain-vertical",
            title="Reader Fixture Plain Vertical",
            language="ja",
            css=base_css("html, body { writing-mode: vertical-rl; }"),
            chapters=[
                Chapter("chapter-1.xhtml", "Plain Vertical", repeated_paragraphs(30)),
                Chapter("chapter-2.xhtml", "Plain Vertical End", repeated_paragraphs(10)),
            ],
            extra_files={},
        ),
        Fixture(
            name="long-chapter",
            title="Reader Fixture Long Chapter",
            language="ja",
            css=base_css(),
            chapters=[Chapter("chapter-1.xhtml", "Long Chapter", repeated_paragraphs(140))],
            extra_files={},
        ),
        Fixture(
            name="chapter-boundary",
            title="Reader Fixture Chapter Boundary",
            language="ja",
            css=base_css(),
            chapters=[
                Chapter("chapter-1.xhtml", "Boundary Start", repeated_paragraphs(4) + "<p id=\"chapter-end\">CHAPTER_ONE_END_MARKER</p>"),
                Chapter("chapter-2.xhtml", "Boundary Next", "<p id=\"chapter-start\">CHAPTER_TWO_START_MARKER</p>" + repeated_paragraphs(6)),
            ],
            extra_files={},
        ),
        Fixture(
            name="ruby-heavy",
            title="Reader Fixture Ruby Heavy",
            language="ja",
            css=base_css(),
            chapters=[Chapter("chapter-1.xhtml", "Ruby Heavy", ruby_body)],
            extra_files={},
        ),
        Fixture(
            name="multi-image",
            title="Reader Fixture Multi Image",
            language="ja",
            css=base_css(),
            chapters=[
                Chapter(
                    "chapter-1.xhtml",
                    "Multi Image",
                    repeated_paragraphs(4)
                    + "<figure><img src=\"images/image-a.svg\" alt=\"Image A\"/><figcaption>Image A caption</figcaption></figure>"
                    + repeated_paragraphs(4)
                    + "<figure><img src=\"images/image-b.svg\" alt=\"Image B\"/><figcaption>Image B caption</figcaption></figure>"
                    + repeated_paragraphs(4),
                )
            ],
            extra_files={"OEBPS/images/image-a.svg": image_a, "OEBPS/images/image-b.svg": image_b},
        ),
        Fixture(
            name="cover-image",
            title="Reader Fixture Cover Image",
            language="ja",
            css=base_css(
                """
                body > h1 {
                  display: none;
                }
                figure {
                  margin: 0;
                  text-align: center;
                }
                """
            ),
            chapters=[
                Chapter("cover.xhtml", "Cover", "<figure><img src=\"images/cover.svg\" alt=\"Cover Fixture\"/></figure>"),
                Chapter("chapter-1.xhtml", "After Cover", repeated_paragraphs(10)),
            ],
            extra_files={"OEBPS/images/cover.svg": cover_svg},
        ),
        Fixture(
            name="weird-css",
            title="Reader Fixture Weird CSS",
            language="ja",
            css=weird_css,
            chapters=[
                Chapter(
                    "chapter-1.xhtml",
                    "Weird CSS",
                    "<div class=\"oversized\">Oversized block that should not break Reader constraints.</div>"
                    + "<table><tr><td>Very long cell content without natural breaks 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ</td><td>短いセル</td></tr></table>"
                    + "<pre>preformatted-content-with-a-very-long-line-that-should-wrap-inside-reader-without-overflow</pre>"
                    + repeated_paragraphs(10),
                )
            ],
            extra_files={},
        ),
        Fixture(
            name="internal-links",
            title="Reader Fixture Internal Links",
            language="ja",
            css=base_css(),
            chapters=[
                Chapter("chapter-1.xhtml", "Links", "<p><a href=\"chapter-2.xhtml#target\">Jump to target</a></p>" + repeated_paragraphs(8)),
                Chapter("chapter-2.xhtml", "Target", "<p id=\"target\">INTERNAL_LINK_TARGET</p><p><a href=\"chapter-1.xhtml\">Back to first chapter</a></p>" + repeated_paragraphs(8)),
            ],
            extra_files={},
        ),
        Fixture(
            name="mixed-content",
            title="Reader Fixture Mixed Content",
            language="ja",
            css=base_css("blockquote { border-inline-start: 4px solid #999; padding-inline-start: 1em; }"),
            chapters=[
                Chapter(
                    "chapter-1.xhtml",
                    "Mixed Content",
                    ruby_body
                    + "<blockquote>Quoted text with mixed punctuation, ruby, and images.</blockquote>"
                    + "<figure><img src=\"images/image-a.svg\" alt=\"Mixed Image\"/></figure>"
                    + "<p><a href=\"#mixed-anchor\">Jump inside chapter</a></p>"
                    + repeated_paragraphs(12)
                    + "<p id=\"mixed-anchor\">MIXED_CONTENT_ANCHOR</p>",
                )
            ],
            extra_files={"OEBPS/images/image-a.svg": image_a},
        ),
    ]


def chapter_xhtml(title: str, body: str, css_class: str = "") -> bytes:
    class_attr = f' class="{css_class}"' if css_class else ""
    content = f"""<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" lang="ja">
<head>
  <meta charset="utf-8"/>
  <title>{html.escape(title)}</title>
  <link rel="stylesheet" href="styles/fixture.css"/>
</head>
<body{class_attr}>
  <h1>{html.escape(title)}</h1>
  {body}
</body>
</html>
"""
    return content.encode("utf-8")


def content_opf(fixture: Fixture) -> bytes:
    manifest_items = [
        '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>',
        '<item id="toc" href="toc.ncx" media-type="application/x-dtbncx+xml"/>',
        '<item id="css" href="styles/fixture.css" media-type="text/css"/>',
    ]
    spine_items = []
    for index, chapter in enumerate(fixture.chapters, start=1):
        manifest_items.append(f'<item id="chapter-{index}" href="{chapter.filename}" media-type="application/xhtml+xml"/>')
        spine_items.append(f'<itemref idref="chapter-{index}"/>')
    for path in sorted(fixture.extra_files):
        if path.endswith(".svg"):
            href = path.removeprefix("OEBPS/")
            item_id = href.replace("/", "-").replace(".", "-")
            manifest_items.append(f'<item id="{item_id}" href="{href}" media-type="image/svg+xml"/>')

    content = f"""<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" unique-identifier="bookid" version="3.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="bookid">urn:uuid:hoshi-reader-fixture-{fixture.name}</dc:identifier>
    <dc:title>{html.escape(fixture.title)}</dc:title>
    <dc:language>{fixture.language}</dc:language>
    <meta property="dcterms:modified">2026-05-25T00:00:00Z</meta>
  </metadata>
  <manifest>
    {chr(10).join(manifest_items)}
  </manifest>
  <spine toc="toc">
    {chr(10).join(spine_items)}
  </spine>
</package>
"""
    return content.encode("utf-8")


def nav_xhtml(fixture: Fixture) -> bytes:
    items = "\n".join(
        f'<li><a href="{chapter.filename}">{html.escape(chapter.title)}</a></li>'
        for chapter in fixture.chapters
    )
    return f"""<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" lang="ja">
<head><title>{html.escape(fixture.title)} Navigation</title></head>
<body>
  <nav epub:type="toc" xmlns:epub="http://www.idpf.org/2007/ops">
    <h1>Contents</h1>
    <ol>{items}</ol>
  </nav>
</body>
</html>
""".encode("utf-8")


def toc_ncx(fixture: Fixture) -> bytes:
    points = []
    for index, chapter in enumerate(fixture.chapters, start=1):
        points.append(
            f"""<navPoint id="navPoint-{index}" playOrder="{index}">
  <navLabel><text>{html.escape(chapter.title)}</text></navLabel>
  <content src="{chapter.filename}"/>
</navPoint>"""
        )
    return f"""<?xml version="1.0" encoding="utf-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head>
    <meta name="dtb:uid" content="urn:uuid:hoshi-reader-fixture-{fixture.name}"/>
    <meta name="dtb:depth" content="1"/>
    <meta name="dtb:totalPageCount" content="0"/>
    <meta name="dtb:maxPageNumber" content="0"/>
  </head>
  <docTitle><text>{html.escape(fixture.title)}</text></docTitle>
  <navMap>
    {chr(10).join(points)}
  </navMap>
</ncx>
""".encode("utf-8")


def write_fixture(fixture: Fixture, output_dir: Path) -> Path:
    output_dir.mkdir(parents=True, exist_ok=True)
    epub_path = output_dir / f"{fixture.name}.epub"
    css_bytes = fixture.css.encode("utf-8")
    weird_class = "fixture-weird" if fixture.name == "weird-css" else ""

    with zipfile.ZipFile(epub_path, "w") as archive:
        archive.writestr(zipfile.ZipInfo("mimetype"), "application/epub+zip", compress_type=zipfile.ZIP_STORED)
        archive.writestr("META-INF/container.xml", b"""<?xml version="1.0" encoding="utf-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
""")
        archive.writestr("OEBPS/content.opf", content_opf(fixture))
        archive.writestr("OEBPS/nav.xhtml", nav_xhtml(fixture))
        archive.writestr("OEBPS/toc.ncx", toc_ncx(fixture))
        archive.writestr("OEBPS/styles/fixture.css", css_bytes)
        for chapter in fixture.chapters:
            archive.writestr(f"OEBPS/{chapter.filename}", chapter_xhtml(chapter.title, chapter.body, weird_class))
        for path, data in sorted(fixture.extra_files.items()):
            archive.writestr(path, data)

    return epub_path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help=f"Directory for generated EPUBs. Default: {DEFAULT_OUTPUT}",
    )
    args = parser.parse_args()

    for fixture in fixture_catalog():
        path = write_fixture(fixture, args.output)
        print(path)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
