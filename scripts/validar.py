from pathlib import Path
import re
root = Path(__file__).resolve().parents[1]
agents = ("archi", "efrain", "eugenia", "compi", "quasimodo")
required = ["README.md", "AGENTS.md", "MULTICONSULTING.md", "ARRANQUE.md", "MISION-001.md", "agents/README.md"] + [f"agents/{a}/HANDOVER.md" for a in agents]
for rel in required:
    p = root / rel
    assert p.is_file(), f"Falta {rel}"
    s = p.read_text(encoding="utf-8")
    assert s.strip().startswith("# "), f"Sin título: {rel}"
    assert len(s.strip()) > 80, f"Documento incompleto: {rel}"
    if rel.endswith("HANDOVER.md"):
        assert re.search(r"(?i)generaci[oó]n", s), f"Falta generación: {rel}"
        assert re.search(r"https://github.com/Montara-Projects/Montara/(issues|pull)/[0-9]+", s), f"Falta referencia: {rel}"
print(f"PASS: {len(required)} documentos y {len(agents)} identidades")
