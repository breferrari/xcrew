"""Draws the README's mockups as SVG, in the banner's frame and colours.

Drawn rather than captured, so they stay sharp and readable at any width. Run from assets/, then
render each at 2x: python3 mockups.py && for f in band test-result failures-pane architecture; do
rsvg-convert -z 2 $f.svg -o $f.png; done
"""
import sys
from xml.sax.saxutils import escape

# `--light` draws every picture in a light theme's colours, as <name>-light.svg, for readers on a light theme.
IS_LIGHT = "--light" in sys.argv
OUT = next((arg for arg in sys.argv[1:] if not arg.startswith("--")), ".")
FONT = "JetBrains Mono, JetBrainsMono Nerd Font Mono, SF Mono, Menlo, monospace"
SIZE = 17
CW = SIZE * 0.6  # monospace advance
LH = 27

# The banner's graphite and orange, with GitHub's dark-mode accents, as the README's badges use.
C = {
    "term": "#11151b", "bar": "#0d1015", "border": "#262c35",
    "text": "#e6e8eb", "subtle": "#8b929c", "inactive": "#323944", "success": "#3fb950", "error": "#f85149",
    "warning": "#d29922", "orange": "#ec501d", "blue": "#58a6ff", "label": "#a9afb9",
    "glowInner": "#151a22", "glowOuter": "#0c0f13", "wordmark": "#f3f4f6",
}


# A light theme's equivalents, for the band drawn as a light terminal shows it.
LIGHT = {
    "term": "#ffffff", "bar": "#f6f8fa", "border": "#d0d7de",
    "text": "#1f2328", "subtle": "#6e7781", "inactive": "#d0d7de", "success": "#1a7f37", "error": "#cf222e",
    "warning": "#9a6700", "orange": "#ec501d", "blue": "#0969da", "label": "#57606a",
    "glowInner": "#ffffff", "glowOuter": "#eef0f3", "wordmark": "#1f2328",
}

if IS_LIGHT:
    C.update(LIGHT)

SEP = (" · ", "subtle")


class Canvas:
    def __init__(self, width, height):
        self.w, self.h, self.parts = width, height, []

    def add(self, s):
        self.parts.append(s)

    def text(self, x, y, s, color="text", weight=None, size=SIZE, font=FONT, spacing=None):
        w = f' font-weight="{weight}"' if weight else ""
        ls = f' letter-spacing="{spacing}"' if spacing else ""
        self.add(f'<text x="{x:.1f}" y="{y:.1f}" font-family="{font}" font-size="{size}"{w}{ls} fill="{C.get(color, color)}" xml:space="preserve">{escape(s)}</text>')

    def run(self, x, y, segments):
        """Segments of (text, colour, weight) or ('@shape', …) laid out on a monospace grid."""
        for seg in segments:
            if seg[0] == "@gauge":
                _, cells, filled, colour = seg
                top = y - SIZE * 0.36
                self.add(f'<rect x="{x:.1f}" y="{top:.1f}" width="{cells * CW:.1f}" height="2" fill="{C["inactive"]}"/>')
                self.add(f'<rect x="{x:.1f}" y="{top - 1:.1f}" width="{filled * CW:.1f}" height="4" rx="1" fill="{C[colour]}"/>')
                x += cells * CW
            elif seg[0] == "@skip":
                cy = y - SIZE * 0.35
                self.add(f'<rect x="{x + 1:.1f}" y="{cy - 8:.1f}" width="16" height="16" rx="4" fill="{C["blue"]}"/>')
                self.add(f'<path d="M{x + 4:.1f} {cy - 4:.1f} l4 4 l-4 4z M{x + 8:.1f} {cy - 4:.1f} l4 4 l-4 4z" fill="{C["term"]}"/>')
                self.add(f'<rect x="{x + 12.5:.1f}" y="{cy - 4:.1f}" width="1.6" height="8" fill="{C["term"]}"/>')
                x += 2 * CW
            elif seg[0] == "@cross":
                cy = y - SIZE * 0.35
                self.add(f'<path d="M{x + 3:.1f} {cy - 6:.1f} l12 12 M{x + 15:.1f} {cy - 6:.1f} l-12 12" stroke="{C["error"]}" stroke-width="3.2" stroke-linecap="round"/>')
                x += 2 * CW
            else:
                s, colour, *rest = seg
                self.text(x, y, s, colour, rest[0] if rest else None)
                x += len(s) * CW
        return x

    def svg(self):
        return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.w}" height="{self.h}" viewBox="0 0 {self.w} {self.h}">\n'
                + "\n".join(self.parts) + "\n</svg>\n")


def backdrop(c, width, height):
    """Shared definitions. The background stays transparent, so the image sits on GitHub's own page colour."""
    c.add('<defs><filter id="shadow" x="-10%" y="-10%" width="120%" height="130%" color-interpolation-filters="sRGB"><feGaussianBlur in="SourceAlpha" stdDeviation="10"/><feOffset dy="6"/>'
          '<feComponentTransfer><feFuncA type="linear" slope="0.35"/></feComponentTransfer><feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter>'
          '<marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto"><path d="M0 0 L10 5 L0 10 z" fill="#6e7681"/></marker></defs>')


def frame(width, height, title):
    c = Canvas(width, height)
    backdrop(c, width, height)
    x0, y0, w, h = 16, 12, width - 32, height - 36
    c.add(f'<g filter="url(#shadow)"><rect x="{x0}" y="{y0}" width="{w}" height="{h}" rx="8" fill="{C["term"]}" stroke="{C["border"]}"/></g>')
    c.add(f'<path d="M{x0 + 0.5} {y0 + 38} v-30 a7.5 7.5 0 0 1 7.5 -7.5 h{w - 16} a7.5 7.5 0 0 1 7.5 7.5 v30 z" fill="{C["bar"]}"/>')
    c.add(f'<line x1="{x0}" y1="{y0 + 38}" x2="{x0 + w}" y2="{y0 + 38}" stroke="{C["border"]}"/>')
    # macOS's own window-button colours, as the social preview draws them.
    for i, dot in enumerate(["#ff5f57", "#febc2e", "#28c840"]):
        c.add(f'<circle cx="{x0 + 20 + i * 18}" cy="{y0 + 19}" r="5.5" fill="{dot}"/>')
    c.text(x0 + w / 2 - len(title) * 7.2 / 2, y0 + 24, title, "subtle", size=12, font="Helvetica Neue")
    return c, x0 + 28, y0 + 74


def prompt_box(c, x, y, width):
    c.add(f'<rect x="{x - 8:.1f}" y="{y:.1f}" width="{width:.1f}" height="38" rx="8" fill="none" stroke="{C["inactive"]}" stroke-width="1.3"/>')
    c.text(x + 6, y + 25, ">", "subtle")


def banner():
    """The README's banner: the screw render beside the wordmark, in a frame with the X's orange corners."""
    return f"""<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="2080" height="400" viewBox="0 0 2080 400">
  <defs>
    <radialGradient id="glow" cx="0.22" cy="0.5" r="0.6">
      <stop offset="0" stop-color="{C['glowInner']}"/>
      <stop offset="1" stop-color="{C['glowOuter']}"/>
    </radialGradient>
  </defs>
  <rect width="2080" height="400" fill="url(#glow)"/>
  <!-- Hairline frame, then heavier corner brackets, all in the X's orange. -->
  <rect x="5" y="5" width="2070" height="390" fill="none" stroke="{C['orange']}" stroke-opacity="0.35" stroke-width="2"/>
  <g fill="none" stroke="{C['orange']}" stroke-width="6" stroke-linecap="square">
    <path d="M7 55 V7 H55"/>
    <path d="M2025 7 H2073 V55"/>
    <path d="M7 345 V393 H55"/>
    <path d="M2025 393 H2073 V345"/>
  </g>
  <image x="70" y="30" width="340" height="340" xlink:href="screw.png"/>
  <text x="430" y="272" font-family="Helvetica Neue" font-weight="bold" font-size="196" letter-spacing="-4" fill="{C['wordmark']}">Xcrew</text>
  <line x1="1150" y1="200" x2="1440" y2="200" stroke="{C['orange']}" stroke-opacity="0.75" stroke-width="2"/>
  <g font-family="Helvetica Neue" font-weight="500" font-size="33" letter-spacing="7" fill="{C['label']}" text-anchor="end">
    <text x="1975" y="186">XCODE TOOLING</text>
    <text x="1975" y="242">FOR CLAUDE CODE</text>
  </g>
</svg>
"""


class Text:
    """A drawing already written as SVG text, with the same `svg()` as a Canvas."""
    def __init__(self, svg):
        self.text = svg

    def svg(self):
        return self.text


def band():
    c, x, y = frame(1280, 650, "claude — ~/Developer/MyApp")
    rows = [
        # Only the separators are faint, as in hooks/mod/band.ts: every value reads in the theme's text colour.
        ("WHILE IT RUNS", [("●", "orange"), (" ", "text"), ("test_sim", "text", "600"), SEP, ("0:41", "text"), (" ", "text"),
                           ("@gauge", 8, 5, "success"), (" ", "text"), ("~0:24 left", "text"), SEP, ("testing 575 of 959", "text"), SEP, ("MyApp on iPhone 17", "text")]),
        ("WHEN IT PASSES", [("✓", "success"), (" ", "text"), ("test_sim", "text", "600"), SEP, ("1:12", "text"), (" (avg 1:05)", "orange"), SEP, ("959 passed", "text")]),
        ("WHEN IT FAILS", [("✗", "error"), (" ", "text"), ("test_sim", "text", "600"), SEP, ("2:03", "text"), (" (avg 1:58)", "orange"), SEP,
                           ("3 of 961 failed · PaymentsTests/test_refund()", "error")]),
        ("WHEN A BUILD FAILS", [("✗", "error"), (" ", "text"), ("build_sim", "text", "600"), SEP, ("0:48", "text"), SEP,
                                ("CheckoutView.swift:12 Cannot find 'total' in scope", "error")]),
    ]
    for label, segs in rows:
        c.text(x, y, label, "label", "600", size=12, font="Helvetica Neue", spacing="2.5")
        c.run(x, y + 34, segs)
        prompt_box(c, x, y + 50, 1280 - 2 * x)
        y += 142
    return c


def result():
    c, x, y = frame(1280, 650, "claude — ~/Developer/MyApp")
    c.run(x, y, [("⏺", "success"), (" ", "text"), ("MobileBuildMCP - test_sim", "text", "600"), (" (MCP)", "subtle")])
    y += LH
    ind = x + 3 * CW
    c.text(x + CW, y, "⎿", "subtle")
    lines = [
        [("Test Failures (2):", "text", "600")],
        [],
        [("  ✗ PaymentsTests / test_crashes(): Crash: xctest at PaymentsTests.test_crashes()", "error")],
        [("      crashed: EXC_BREAKPOINT (SIGTRAP)", "warning")],
        [("      libswiftCore.dylib  Array._checkSubscript(_:wasNativeTypeChecked:)", "subtle")],
        [("      Payments            PaymentsTests.test_crashes()", "subtle")],
        [],
        [("  ✗ PaymentsTests / test_refund(): XCTAssertEqual failed: (\"1\") is not equal to (\"2\")", "error")],
        [("    /Users/you/MyApp/Tests/PaymentsTests/PaymentsTests.swift:42", "blue")],
        [],
        [("Test Results:", "text", "600")],
        [("  (959 passing tests left out; failing tests are listed in full above)", "subtle")],
        [("  ", "text"), ("@skip",), (" PaymentsTests/test_wallet() (0.006s)", "text")],
        [("      skipped: waiting on the new API", "warning")],
        [],
        [("@cross",), (" 2 tests failed, 959 passed, 1 skipped (54.6s)", "text", "600")],
    ]
    for segs in lines:
        if segs:
            c.run(ind, y, segs)
        y += LH
    y += 14
    c.add(f'<line x1="{x}" y1="{y - 4}" x2="{1280 - x}" y2="{y - 4}" stroke="{C["border"]}"/>')
    c.run(x, y + 24, [("+ a note for Claude:", "label"), (" 1 test also ran as an expected failure; 962 tests ran in all.", "subtle")])
    return c


def pane():
    c, x, y = frame(1280, 470, "claude — ~/Developer/MyApp")
    split = 700
    c.add(f'<line x1="{split}" y1="{y - 36}" x2="{split}" y2="{470 - 40}" stroke="{C["border"]}"/>')
    c.run(x, y, [(">", "subtle"), (" /xcrew failures", "text")])
    c.run(x, y + LH, [("  ⎿  ", "subtle"), ("2 failures from test_sim, in the pane.", "subtle")])
    c.run(x, y + 3 * LH, [("⏺", "text"), (" Two failures: test_refund compares the wrong", "text")])
    c.text(x + 2 * CW, y + 4 * LH, "currency, and test_crashes reads past the end of", "text")
    c.text(x + 2 * CW, y + 5 * LH, "an empty array. Fixing the subscript first.", "text")
    prompt_box(c, x, y + 7 * LH, split - x - 20)
    px = split + 26
    c.text(px, y, "Failures", "text", "600")
    c.add(f'<line x1="{px}" y1="{y + 12}" x2="{1280 - 66}" y2="{y + 12}" stroke="{C["border"]}"/>')
    yy = y + 44
    for title, where, message in [
        ("PaymentsTests/test_crashes()", "PaymentsTests.swift:57", "Crash: xctest at PaymentsTests.test_crashes()"),
        ("PaymentsTests/test_refund()", "PaymentsTests.swift:42", 'XCTAssertEqual failed: ("1") is not equal to ("2")'),
    ]:
        c.text(px, yy, title, "error", "600")
        c.text(px, yy + LH, where, "subtle")
        words, line, lines = message.split(" "), "", []
        for word in words:
            if len(line) + len(word) + 1 > 44:
                lines.append(line); line = word
            else:
                line = f"{line} {word}".strip()
        lines.append(line)
        for i, part in enumerate(lines):
            c.text(px, yy + (2 + i) * LH, part, "text")
        yy += (3 + len(lines)) * LH
    return c


def arch():
    W, H = 1280, 640
    c = Canvas(W, H)
    backdrop(c, W, H)
    sans = "Helvetica Neue"

    def box(x, y, w, h, title, sub=None, accent=None, fill=None):
        c.add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="6" fill="{fill or C["term"]}" stroke="{accent or C["border"]}" stroke-width="{1.6 if accent else 1}"/>')
        ty = y + (h / 2 + 6 if not sub else h / 2 - 4)
        c.text(x + 18, ty, title, "text", "600", size=17, font=FONT)
        if sub:
            c.text(x + 18, ty + 22, sub, "subtle", size=14, font=FONT)

    def line(x1, y1, x2, y2, arrow=True, dash=False):
        d = ' stroke-dasharray="5 5"' if dash else ""
        m = ' marker-end="url(#arrow)"' if arrow else ""
        c.add(f'<path d="M{x1} {y1} L{x2} {y2}" stroke="#6e7681" stroke-width="1.4" fill="none"{d}{m}/>')

    def elbow(x1, y1, x2, y2):
        c.add(f'<path d="M{x1} {y1} H{(x1 + x2) / 2} V{y2} H{x2}" stroke="#6e7681" stroke-width="1.4" fill="none" marker-end="url(#arrow)"/>')

    c.text(60, 64, "HOW IT FITS TOGETHER", "label", "600", size=13, font=sans, spacing="2.5")
    # Claude Code and the four plugin pieces.
    box(60, 250, 190, 70, "Claude Code", accent=C["orange"])
    pieces = [
        ("plugin.json", "MobileBuildMCP · Xcode MCP · Sosumi", False),
        ("hooks.json", "session briefing", True),
        ("mod (TypeScript)", "guard · timing · band · pane · /xcrew", True),
        ("skills/", "setup · reference", True),
    ]
    px, pw, ph = 330, 470, 64
    for i, (title, sub, cli) in enumerate(pieces):
        py = 100 + i * 92
        elbow(250, 285, px - 4, py + ph / 2)
        box(px, py, pw, ph, title, sub)
    c.text(px, 92, "THE PLUGIN", "label", "600", size=12, font=sans, spacing="2")
    # The servers the plugin starts.
    sx = 860
    box(sx, 100, 384, 64, "three MCP servers", "builds, previews, documentation", accent=C["blue"])
    line(px + pw, 132, sx - 4, 132)
    # The Swift CLI everything else calls.
    cy = 470
    box(860, cy, 384, 80, "Swift CLI (bin/xcrew)", "report · phase · project · doctor · setup", accent=C["success"])
    for i in (1, 2, 3):
        py = 100 + i * 92 + ph / 2
        c.add(f'<path d="M{px + pw} {py} H830 V{cy + 26} H856" stroke="#6e7681" stroke-width="1.4" fill="none" marker-end="url(#arrow)"/>')
    c.text(870, cy + 112, "built from source on first use, once per version", "subtle", size=13, font=sans)
    # mcs, the other way in.
    box(330, 486, pw, 64, "mcs techpack", "configure.sh · one script per doctor check", fill=C["bar"])
    line(px + pw, 518, 856, 518)
    c.text(330, 590, "optional: installs the Homebrew package and the plugin together", "subtle", size=13, font=sans)
    return c


DRAWINGS = [("banner", lambda: Text(banner())), ("band", band), ("test-result", result), ("failures-pane", pane), ("architecture", arch)]
drawings = [(f"{name}-light", make) for name, make in DRAWINGS] if IS_LIGHT else DRAWINGS
for name, make in drawings:
    with open(f"{OUT}/{name}.svg", "w") as f:
        f.write(make().svg())
