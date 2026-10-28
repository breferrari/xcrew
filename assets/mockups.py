"""Draws the README's mockups as SVG, in the social preview's frame and Catppuccin Mocha colours.

Drawn rather than captured, so they stay sharp and readable at any width. Run from assets/, then
render each at 2x: python3 mockups.py && for f in band test-result failures-pane architecture; do
rsvg-convert -z 2 $f.svg -o $f.png; done
"""
import sys
from xml.sax.saxutils import escape

OUT = sys.argv[1] if len(sys.argv) > 1 else "."
FONT = "JetBrains Mono, JetBrainsMono Nerd Font Mono, SF Mono, Menlo, monospace"
SIZE = 17
CW = SIZE * 0.6  # monospace advance
LH = 27

C = {
    "bg": "#0b0e12", "glow": "#161c25", "term": "#1e1e2e", "bar": "#181825", "border": "#313244",
    "text": "#cdd6f4", "subtle": "#7f849c", "inactive": "#45475a", "success": "#a6e3a1", "error": "#f38ba8",
    "warning": "#f9e2af", "orange": "#ec501d", "blue": "#89b4fa", "label": "#a9afb9",
}


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


def frame(width, height, title):
    c = Canvas(width, height)
    c.add('<defs><radialGradient id="glow" cx="0.3" cy="0.3" r="0.9"><stop offset="0" stop-color="#161c25"/><stop offset="1" stop-color="#0b0e12"/></radialGradient>'
          '<filter id="shadow" x="-10%" y="-10%" width="120%" height="130%"><feGaussianBlur in="SourceAlpha" stdDeviation="14"/><feOffset dy="10"/>'
          '<feComponentTransfer><feFuncA type="linear" slope="0.55"/></feComponentTransfer><feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter></defs>')
    c.add(f'<rect width="{width}" height="{height}" rx="18" fill="url(#glow)"/>')
    x0, y0, w, h = 40, 36, width - 80, height - 72
    c.add(f'<g filter="url(#shadow)"><rect x="{x0}" y="{y0}" width="{w}" height="{h}" rx="12" fill="{C["term"]}" stroke="{C["border"]}"/></g>')
    c.add(f'<path d="M{x0} {y0 + 40} v-28 a12 12 0 0 1 12 -12 h{w - 24} a12 12 0 0 1 12 12 v28 z" fill="{C["bar"]}"/>')
    for i, dot in enumerate(["#f38ba8", "#f9e2af", "#a6e3a1"]):
        c.add(f'<circle cx="{x0 + 22 + i * 20}" cy="{y0 + 20}" r="6" fill="{dot}"/>')
    c.text(x0 + w / 2 - len(title) * 7.2 / 2, y0 + 25, title, "subtle", size=12, font="Helvetica Neue")
    return c, x0 + 28, y0 + 74


def prompt_box(c, x, y, width):
    c.add(f'<rect x="{x - 8:.1f}" y="{y:.1f}" width="{width:.1f}" height="38" rx="8" fill="none" stroke="{C["inactive"]}" stroke-width="1.3"/>')
    c.text(x + 6, y + 25, ">", "subtle")


def band():
    c, x, y = frame(1280, 700, "claude — ~/Developer/MyApp")
    rows = [
        ("WHILE IT RUNS", [("●", "orange"), (" ", "text"), ("test_sim", "text", "600"), (" · 0:41", "subtle"), (" ", "text"),
                           ("@gauge", 8, 6.5, "success"), (" ~0:04 left", "subtle"), (" · testing 431 of 959", "subtle"), (" · MyApp on iPhone 17", "subtle")]),
        ("WHEN IT PASSES", [("✓", "success"), (" ", "text"), ("test_sim", "text", "600"), (" · 1:12", "subtle"), (" (avg 1:05)", "orange"), (" · 959 passed", "subtle")]),
        ("WHEN IT FAILS", [("✗", "error"), (" ", "text"), ("test_sim", "text", "600"), (" · 2:03", "subtle"), (" (avg 1:58)", "orange"),
                           (" · 3 of 961 failed · PaymentsTests/test_refund()", "error")]),
        ("WHEN A BUILD FAILS", [("✗", "error"), (" ", "text"), ("build_sim", "text", "600"), (" · 0:48", "subtle"),
                                (" · CheckoutView.swift:12 Cannot find 'total' in scope", "error")]),
    ]
    for label, segs in rows:
        c.text(x, y, label, "label", "600", size=12, font="Helvetica Neue", spacing="2.5")
        c.run(x, y + 34, segs)
        prompt_box(c, x, y + 50, 1280 - 2 * x)
        y += 142
    return c


def result():
    c, x, y = frame(1280, 720, "claude — ~/Developer/MyApp")
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
    c.add('<defs><radialGradient id="glow" cx="0.3" cy="0.3" r="0.9"><stop offset="0" stop-color="#161c25"/><stop offset="1" stop-color="#0b0e12"/></radialGradient>'
          '<marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto"><path d="M0 0 L10 5 L0 10 z" fill="#7f849c"/></marker></defs>')
    c.add(f'<rect width="{W}" height="{H}" rx="18" fill="url(#glow)"/>')
    sans = "Helvetica Neue"

    def box(x, y, w, h, title, sub=None, accent=None, fill=None):
        c.add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="10" fill="{fill or C["term"]}" stroke="{accent or C["border"]}" stroke-width="{1.6 if accent else 1}"/>')
        ty = y + (h / 2 + 6 if not sub else h / 2 - 4)
        c.text(x + 18, ty, title, "text", "600", size=17, font=FONT)
        if sub:
            c.text(x + 18, ty + 22, sub, "subtle", size=14, font=FONT)

    def line(x1, y1, x2, y2, arrow=True, dash=False):
        d = ' stroke-dasharray="5 5"' if dash else ""
        m = ' marker-end="url(#arrow)"' if arrow else ""
        c.add(f'<path d="M{x1} {y1} L{x2} {y2}" stroke="#7f849c" stroke-width="1.4" fill="none"{d}{m}/>')

    def elbow(x1, y1, x2, y2):
        c.add(f'<path d="M{x1} {y1} H{(x1 + x2) / 2} V{y2} H{x2}" stroke="#7f849c" stroke-width="1.4" fill="none" marker-end="url(#arrow)"/>')

    c.text(60, 64, "HOW IT FITS TOGETHER", "label", "600", size=13, font=sans, spacing="2.5")
    # Claude Code and the four plugin pieces.
    box(60, 250, 190, 70, "Claude Code", accent=C["orange"])
    pieces = [
        (".mcp.json", "MobileBuildMCP · Xcode MCP · Sosumi", False),
        ("hooks.json", "session briefing", True),
        ("mod (TypeScript)", "guard · timing · results · band · pane", True),
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
    box(sx, 100, 360, 64, "three MCP servers", "builds, previews, documentation", accent=C["blue"])
    line(px + pw, 132, sx - 4, 132)
    # The Swift CLI everything else calls.
    cy = 470
    box(860, cy, 360, 80, "Swift CLI (bin/xcrew)", "setup · doctor · hook · xcode-skills", accent=C["success"])
    for i in (1, 2, 3):
        py = 100 + i * 92 + ph / 2
        c.add(f'<path d="M{px + pw} {py} H830 V{cy + 26} H856" stroke="#7f849c" stroke-width="1.4" fill="none" marker-end="url(#arrow)"/>')
    c.text(870, cy + 112, "built from source on first use, once per version", "subtle", size=13, font=sans)
    # mcs, the other way in.
    box(330, 486, pw, 64, "mcs techpack", "configure.sh · one script per doctor check", fill=C["bar"])
    line(px + pw, 518, 856, 518)
    c.text(330, 590, "optional: installs the Homebrew package and the plugin together", "subtle", size=13, font=sans)
    return c


for name, make in [("band", band), ("test-result", result), ("failures-pane", pane), ("architecture", arch)]:
    with open(f"{OUT}/{name}.svg", "w") as f:
        f.write(make().svg())
