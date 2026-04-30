#!/usr/bin/env python3

module_name = "Cortex Analyzer"
module_description = "Future-proof integration with Cortex analyzers for DFIR-IRIS. Supports all enabled analyzers dynamically discovered from Cortex."
interface_version = 1.1
module_version = 1.0

pipeline_support = False
pipeline_info = {}

module_configuration = [
    {
        "param_name": "cortex_url",
        "param_human_name": "Cortex URL of Cortex Analyzer",
        "param_description": (
            "Base URL of your Cortex instance. Do NOT add /cortex or trailing slashes.\n\n"
            "Which URL to use:\n"
            "  • Same Docker stack  → http://cortex:9001          (container name, recommended)\n"
            "  • If 'cortex' DNS fails → http://host.docker.internal:9001  (host via bridge)\n"
            "  • External / LAN host  → http://192.168.x.x:9001   (host IP, port must be published)\n\n"
            "Trailing paths are stripped automatically."
        ),
        "default": "http://cortex:9001",
        "mandatory": False,
        "type": "string",
        "section": "Main",
        "editable": True,
    },
    {
        "param_name": "cortex_api_key",
        "param_human_name": "Cortex API Key",
        "param_description": "API key from Cortex UI → Organization → Users → your user → API Key → Reveal/Create.",
        "default": "CHANGE_ME",
        "mandatory": False,
        "type": "sensitive_string",
        "section": "Main",
        "editable": True,
    },
    {
        "param_name": "cortex_analyzers",
        "param_human_name": "Cortex Analyzers (one per line or comma-separated)",
        "param_description": (
            "One or more Cortex analyzer names. Copy exact name from Cortex UI → Analyzers → Enabled.\n\n"
            "Examples:\n"
            "  VirusTotal_GetReport_3_1\n"
            "  AbuseIPDB_1_0\n"
            "  Shodan_Host_1_0\n"
            "  MalwareBazaar_1_0\n"
            "  URLhaus_2_0\n"
            "  OTXQuery_2_0\n"
            "  OpenCTI_SearchObservables_1_0"
        ),
        "default": "VirusTotal_GetReport_3_1",
        "mandatory": False,
        "type": "textarea",
        "section": "Main",
        "editable": True,
    },
    {
        "param_name": "verify_ssl",
        "param_human_name": "Verify SSL",
        "param_description": "Set to False for internal/self-signed certificates.",
        "default": False,
        "mandatory": False,
        "type": "bool",
        "section": "Main",
        "editable": True,
    },
    {
        "param_name": "job_timeout_seconds",
        "param_human_name": "Job timeout seconds",
        "param_description": "Max seconds to wait per analyzer job. Default: 300.",
        "default": 300,
        "mandatory": False,
        "type": "int",
        "section": "Main",
        "editable": True,
    },
    {
        "param_name": "poll_interval_seconds",
        "param_human_name": "Poll interval seconds",
        "param_description": "How often to check job status. Default: 5.",
        "default": 5,
        "mandatory": False,
        "type": "int",
        "section": "Main",
        "editable": True,
    },
    {
        "param_name": "manual_hook_enabled",
        "param_human_name": "Manual triggers on IOCs",
        "param_description": "Show 'Run Cortex Analyzer' in IOC Action dropdown.",
        "default": True,
        "mandatory": False,
        "type": "bool",
        "section": "Triggers",
        "editable": True,
    },
    {
        "param_name": "on_create_hook_enabled",
        "param_human_name": "Auto-trigger on IOC create",
        "param_description": "Auto-run analyzers when a new IOC is added.",
        "default": False,
        "mandatory": False,
        "type": "bool",
        "section": "Triggers",
        "editable": True,
    },
    {
        "param_name": "on_update_hook_enabled",
        "param_human_name": "Auto-trigger on IOC update",
        "param_description": "Auto-run analyzers when an IOC is updated.",
        "default": False,
        "mandatory": False,
        "type": "bool",
        "section": "Triggers",
        "editable": True,
    },
    {
        "param_name": "report_as_attribute",
        "param_human_name": "Add report as IOC attribute",
        "param_description": "Save each result as IOC attribute tab: CORTEX: <AnalyzerName>",
        "default": True,
        "mandatory": False,
        "type": "bool",
        "section": "Insights",
        "editable": True,
    },
    {
        "param_name": "report_template",
        "param_human_name": "Report template",
        "param_description": "Jinja2 HTML template. Variables: {{ results }}, {{ analyzer_name }}, {{ ioc_value }}",
        "default": "<pre>{{ results | tojson(indent=2) }}</pre>",
        "mandatory": False,
        "type": "textarea",
        "section": "Insights",
        "editable": True,
    },
]
