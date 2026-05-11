from __future__ import annotations

import json

from app.config import load_settings
from app.logging.logger import configure_logging


def main() -> None:
    settings = load_settings()
    configure_logging(settings)
    print(json.dumps({"status": "ok", "event": "application.config.validated", "service": settings.service_name, "environment": settings.environment}, indent=2))


if __name__ == "__main__":
    main()
