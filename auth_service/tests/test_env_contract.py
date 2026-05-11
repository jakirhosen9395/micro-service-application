from pathlib import Path

from app.config.settings import ENV_KEY_ORDER, INFRA_BOOLEAN_GATES, assert_env_files_have_same_keys, parse_env_keys

ROOT = Path(__file__).resolve().parents[1]
FILES = [ROOT / ".env.dev", ROOT / ".env.stage", ROOT / ".env.prod", ROOT / ".env.example"]


def test_env_files_have_identical_keys_and_order():
    assert_env_files_have_same_keys(FILES)
    for path in FILES:
        assert parse_env_keys(path) == ENV_KEY_ORDER


def test_env_files_do_not_use_forbidden_infrastructure_gates():
    for path in FILES:
        assert not (set(parse_env_keys(path)) & INFRA_BOOLEAN_GATES)
