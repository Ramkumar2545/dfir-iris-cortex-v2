#!/usr/bin/env python3

import re
import time
from typing import List

try:
    import cortex4py
    from cortex4py.api import Api as CortexApi
except ImportError:
    CortexApi = None

from jinja2 import Environment, BaseLoader, TemplateError


IOC_TYPE_MAP = {
    # IP
    "ip":"ip","ip-src":"ip","ip-dst":"ip","ipv4":"ip","ipv6":"ip",
    "ip-any":"ip","ip-src|port":"ip","ip-dst|port":"ip","ip|port":"ip",
    # Domain
    "domain":"domain","fqdn":"domain","hostname":"domain",
    "domain|ip":"ip","hostname|port":"domain","domain|port":"domain",
    # URL
    "url":"url","uri":"url","link":"url",
    # Hash
    "md5":"hash","sha1":"hash","sha224":"hash","sha256":"hash",
    "sha384":"hash","sha512":"hash","ssdeep":"hash","tlsh":"hash",
    "imphash":"hash","authentihash":"hash","sha3-256":"hash","sha3-512":"hash",
    "filename|md5":"hash","filename|sha1":"hash","filename|sha256":"hash",
    "filename|sha512":"hash","filename|ssdeep":"hash",
    # Mail
    "email":"mail","mail":"mail","email-src":"mail","email-dst":"mail",
    "email-reply-to":"mail","email-subject":"mail",
    # File
    "filename":"filename","filepath":"filename","file":"filename",
    # Registry
    "regkey":"registry","registry":"registry","regkey|value":"registry",
    # Other
    "user-agent":"user-agent","uri_path":"uri_path","uri-path":"uri_path",
    "asn":"autonomous-system","as":"autonomous-system",
    "mac-address":"mac-address","mac":"mac-address",
    "vulnerability":"other","cve":"other",
    "btc":"other","xmr":"other","crypto":"other",
    "text":"other","comment":"other","other":"other",
}

TYPE_PRIORITY = [
    "ip","domain","hash","url","mail",
    "filename","registry","user-agent","uri_path",
    "autonomous-system","mac-address","other"
]


def _normalize_url(url: str) -> str:
    url = url.strip()
    m = re.match(r'^(https?://[^/]+)', url)
    return m.group(1) if m else url.rstrip('/')


class CortexHandler:
    def __init__(self, mod_config, server_config, logger):
        self.mod_config    = mod_config
        self.server_config = server_config
        self.log           = logger
        self._client       = None

    def _conf(self, *keys, default=None):
        for k in keys:
            v = self.mod_config.get(k)
            if v is not None:
                return v
        return default

    def _get_client(self):
        if self._client:
            return self._client
        if CortexApi is None:
            raise ImportError("cortex4py not installed. Run: pip install cortex4py")
        url    = _normalize_url(self._conf("cortex_url", default="http://cortex:9001"))
        key    = self._conf("cortex_api_key")
        verify = self._conf("verify_ssl", default=False)
        self.log.info(f"Connecting to Cortex: {url}")
        self._client = CortexApi(url, key, verify_cert=verify)
        return self._client

    def _get_analyzers(self) -> List[str]:
        raw = self._conf("cortex_analyzers", default="VirusTotal_GetReport_3_1")
        return [
            p.strip() for p in
            str(raw).replace("\n", ",").split(",")
            if p.strip()
        ]

    def _discover_analyzers(self) -> List[str]:
        try:
            return [a.name for a in self._get_client().analyzers.find_all({}, range='all')]
        except Exception as e:
            self.log.warning(f"Could not fetch available analyzers: {e}")
            return []

    def _normalize_ioc_type(self, ioc_type: str) -> str:
        t = ioc_type.lower().strip()
        if t in IOC_TYPE_MAP:
            return IOC_TYPE_MAP[t]
        if "|" in t:
            candidates = [IOC_TYPE_MAP.get(p.strip()) for p in t.split("|") if IOC_TYPE_MAP.get(p.strip())]
            for preferred in TYPE_PRIORITY:
                if preferred in candidates:
                    return preferred
        self.log.warning(f"Unknown IOC type '{ioc_type}' — using 'other'")
        return "other"

    def _run_analyzer(self, client, name: str, value: str, data_type: str) -> dict:
        timeout = int(self._conf("job_timeout_seconds", default=300))
        poll    = int(self._conf("poll_interval_seconds", default=5))
        self.log.info(f"Submit: {value} → {name} (dataType={data_type})")
        job = client.analyzers.run_by_name(name, {"data": value, "dataType": data_type, "tlp": 2}, force=1)
        elapsed = 0
        while elapsed < timeout:
            job = client.jobs.get_by_id(job.id)
            if job.status in ("Success", "Failure"):
                break
            time.sleep(poll)
            elapsed += poll

        report = getattr(job, "report", {}) or {}
        if isinstance(report, dict):
            pass
        else:
            report = {}

        if job.status == "Success":
            return report.get("full", report)
        elif job.status == "Failure":
            return {"error": report.get("error", getattr(job, "errorMessage", "Analyzer failed"))}
        return {"error": f"Timed out after {timeout}s"}

    def _render_report(self, results: dict, name: str, value: str) -> str:
        import json
        tmpl_str = self._conf("report_template", default="<pre>{{ results | tojson(indent=2) }}</pre>")
        try:
            env = Environment(loader=BaseLoader())
            env.filters["tojson"] = lambda v, indent=None: json.dumps(v, indent=indent)
            return env.from_string(tmpl_str).render(
                results=results, analyzer_name=name, ioc_value=value
            )
        except TemplateError as e:
            self.log.warning(f"Template error: {e}")
            return f"<pre>{json.dumps(results, indent=2)}</pre>"

    def handle_iocs(self, data: list):
        import iris_interface.IrisInterfaceStatus as InterfaceStatus
        try:
            client = self._get_client()
        except Exception as e:
            self.log.error(f"Cortex connect failed: {e}")
            return InterfaceStatus.I2Error(message=str(e))

        configured = self._get_analyzers()
        available  = self._discover_analyzers()

        for ioc in data:
            try:
                value     = ioc.ioc_value
                raw_type  = ioc.ioc_type.type_name
                data_type = self._normalize_ioc_type(raw_type)
                self.log.info(f"IOC: {value} | type: {raw_type} → {data_type}")
            except Exception as e:
                self.log.error(f"Cannot read IOC: {e}")
                continue

            for analyzer in configured:
                if available and analyzer not in available:
                    self.log.warning(f"Analyzer '{analyzer}' not in Cortex. Available: {available}")
                    continue
                try:
                    results = self._run_analyzer(client, analyzer, value, data_type)
                    html    = self._render_report(results, analyzer, value)
                    if self._conf("report_as_attribute", default=True):
                        try:
                            ioc.add_attribute(f"CORTEX: {analyzer}", html)
                            self.log.info(f"Saved attribute for {analyzer}")
                        except Exception as ae:
                            self.log.warning(f"Could not save attribute: {ae}")
                except Exception as e:
                    self.log.error(f"Error running {analyzer} on {value}: {e}")

        return InterfaceStatus.I2Success()
