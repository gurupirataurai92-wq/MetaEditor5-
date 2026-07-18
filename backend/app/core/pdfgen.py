"""Minimal, dependency-free PDF writer for receipts and simple documents.

Produces a valid single-page PDF 1.4 with Helvetica/Courier text lines —
enough for thermal-style receipts and simple invoices without pulling in a
heavy rendering stack. Rich, styled PDF output is an adapter concern
(see ``app/adapters``) and can be swapped for WeasyPrint/reportlab in
production without touching the domain.
"""


def _escape(text: str) -> str:
    return text.replace("\\", r"\\").replace("(", r"\(").replace(")", r"\)")


def text_pdf(lines: list[str], *, title: str = "SIMS AI Document",
             font_size: int = 10, leading: int = 14,
             page_width: int = 320, margin: int = 20) -> bytes:
    """Render text lines to PDF bytes (narrow page ≈ 80 mm receipt roll)."""
    page_height = max(200, margin * 2 + leading * (len(lines) + 2))

    content = [f"BT /F1 {font_size} Tf {margin} {page_height - margin - leading} Td {leading} TL"]
    for line in lines:
        content.append(f"({_escape(line)}) Tj T*")
    content.append("ET")
    stream = "\n".join(content).encode("latin-1", "replace")

    objects: list[bytes] = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        (f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {page_width} {page_height}] "
         f"/Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>").encode(),
        b"<< /Length " + str(len(stream)).encode() + b" >>\nstream\n" + stream + b"\nendstream",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>",
    ]

    out = bytearray(b"%PDF-1.4\n")
    offsets = [0]
    for i, obj in enumerate(objects, start=1):
        offsets.append(len(out))
        out += f"{i} 0 obj\n".encode() + obj + b"\nendobj\n"

    xref_pos = len(out)
    out += f"xref\n0 {len(objects) + 1}\n".encode()
    out += b"0000000000 65535 f \n"
    for off in offsets[1:]:
        out += f"{off:010d} 00000 n \n".encode()
    out += (f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\n"
            f"startxref\n{xref_pos}\n%%EOF\n").encode()
    return bytes(out)
