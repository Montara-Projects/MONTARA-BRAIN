from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
agents = ("archi", "efrain", "eugenia", "compi", "quasimodo", "alfred")
required = ["README.md", "AGENTS.md", "MULTICONSULTING.md", "ARRANQUE.md", "MISION-001.md", "agents/README.md"] + [f"agents/{a}/HANDOVER.md" for a in agents]
errors = []
for rel in required:
    p = root / rel
    if not p.is_file():
        errors.append(f"Falta {rel}")
        continue
    s = p.read_text(encoding="utf-8")
    if not s.strip().startswith("# "):
        errors.append(f"Sin título: {rel}")
    if len(s.strip()) <= 80:
        errors.append(f"Documento incompleto: {rel}")
    if rel.endswith("HANDOVER.md"):
        agent = p.parent.name
        identity = rf"(?im)^\s*(?:-\s*)?(?:\*\*)?(?:identidad|generaci[oó]n)(?:\*\*)?:\s*(?:\*\*)?{re.escape(agent)}-\d{{3}}\b"
        if not re.search(identity, s):
            errors.append(f"Falta identidad/generación válida: {rel}")
        if not re.search(r"https://github\.com/Montara-Projects/(?:Montara|Montara-Core|MONTARA-BRAIN)/(?:issues|pull)/[0-9]+", s):
            errors.append(f"Falta referencia: {rel}")
if errors:
    for error in errors:
        print(f"FAIL: {error}")
    raise SystemExit(1)
print(f"PASS: {len(required)} documentos y {len(agents)} identidades")
