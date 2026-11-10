"""Stand-in for the import-extract and import-load images when example2 runs on Floci.

The template ships no application code. The stub only proves that each function exists, starts from its image and
sees the environment the operation stack gives it.
"""

import os
from typing import Any


def handler(event: dict[str, Any], _context: Any) -> dict[str, Any]:
    names = sorted(k for k in os.environ if k.startswith(("DB_", "IMPORT_", "EMBEDDING_")))
    return {"function": os.environ.get("AWS_LAMBDA_FUNCTION_NAME", ""), "environment": names}
