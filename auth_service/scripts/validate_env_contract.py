from __future__ import annotations

from pathlib import Path

from app.config.settings import ENV_KEY_ORDER, INFRA_BOOLEAN_GATES, assert_env_files_have_same_keys, parse_env_keys

ROOT = Path(__file__).resolve().parents[1]
FILES = [ROOT / ".env.dev", ROOT / ".env.stage", ROOT / ".env.prod", ROOT / ".env.example"]


def main() -> None:
    assert_env_files_have_same_keys(FILES)
    for path in FILES:
        keys = parse_env_keys(path)
        if keys != ENV_KEY_ORDER:
            raise SystemExit(f"{path.name} keys do not match canonical AUTH env order")
        forbidden = sorted(set(keys) & INFRA_BOOLEAN_GATES)
        if forbidden:
            raise SystemExit(f"{path.name} contains forbidden infrastructure gates: {', '.join(forbidden)}")
    print("env contract ok")


if __name__ == "__main__":
    main()
