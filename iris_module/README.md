# iris_cortex_analyzer_module

DFIR-IRIS module for Cortex Analyzer integration — IOC enrichment via [cortex4py](https://github.com/TheHive-Project/cortex4py).

## Overview

This module bridges [DFIR-IRIS](https://github.com/dfir-iris/iris-web) and [Cortex](https://github.com/TheHive-Project/Cortex),
enabling automated IOC enrichment by triggering Cortex analyzers directly from IRIS cases and alerts.

## Installation

```bash
bash scripts/install_module.sh
```

## Configuration (IRIS UI)

1. **Advanced → Modules → Add Module**
2. Module name: `iris_cortex_analyzer_module`
3. Click **Save** then **Configure**
4. Set the following:

| Parameter | Value |
|---|---|
| `cortex_url` | `http://cortex:9001` |
| `cortex_api_key` | API key from Cortex UI |
| `cortex_analyzers` | e.g. `VirusTotal_GetReport_3_1` (one per line) |
| `manual_hook_enabled` | `true` |

## License

MIT — see [LICENSE](../LICENSE)
