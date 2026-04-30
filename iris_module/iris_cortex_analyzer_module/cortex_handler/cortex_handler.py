#!/usr/bin/env python3

import time
import re
from typing import List, Optional, Tuple

import requests
from jinja2 import Environment, BaseLoader, TemplateError


IOC_TYPE_MAP = {
    "ip": "ip", "ip-src": "ip", "ip-dst": "ip", "ipv4": "ip", "ipv6": "ip",
    "ip-any": "ip", "ip-src|port": "ip", "ip-dst|port": "ip", "ip|port": "ip",
    "domain": "domain", "fqdn": "domain", "hostname": "domain",
    "domain|ip": "ip", "hostname|port": "domain", "domain|port": "domain",
    "url": "url", "uri": "url", "link": "url",
    "md5": "hash", "sha1": "hash", "sha224": "hash", "sha256": "hash",
    "sha384": "hash", "sha512": "hash", "ssdeep": "hash", "tlsh": "hash",
    "imphash": "hash", "authentihash": "hash", "sha3-256": "hash", "sha3-512": "hash",
    "filename|md5": "hash", "filename|sha1": "hash", "filename|sha256": "hash",
    "filename|sha512": "hash", "filename|ssdeep": "hash",
    "email": "mail", "mail": "mail", "email-src": "mail", "email-dst": "mail",
    "email-reply-to": "mail", "email-subject": "mail",
    "filename": "filename", "filepath": "filename", "file": "filename",
    "regkey": "registry", "registry": "registry", "regkey|value": "registry",
    "user-agent": "user-agent",
    "uri_path": "uri_path", "uri-path": "uri_path",
    "asn": "autonomous-system", "as": "autonomous-system",
    "mac-address": "mac-address", "mac": "mac-address",
    "vulnerability": "other", "cve": "other",
    "btc": "other", "xmr": "other", "crypto": "other",
    "text": "other", "comment": "other", "other": "other",
}

CORTEX_TYPE_PRIORITY = [
    "ip", "domain", "hash", "url", "mail",
    "filename", "registry", "user-agent", "uri_path",
    "autonomous-system", "mac-address", "other"
]


def _normalize_base_url(url: str) -> str:
    """Strip any path from the URL — only keep scheme + host + port."""
    url = url.strip()
    match = re.match(r'^(https?://[^/]+)', url)
    if match:
        return match.group(1)
    return url.rstrip('/')


class CortexHandler:
    """
    CortexHandler uses the Cortex 4.x REST API directly via `requests`.
    cortex4py only supports Cortex 3.x and is NOT used here.

    Cortex 4.x REST API endpoints used:
      GET  /api/analyzer                     list all enabled analyzers
      GET  /api/analyzer?dataTypeList=<type> filter analyzers by data type
      POST /api/analyzer/<id>/run            submit a job
      GET  /api/job/<id>                     poll job status
      GET  /api/job/<id>/report              fetch full report after Success
    """

    def __init__(self, mod_config: dict, server_config: dict, logger):
        self.mod_config = mod_config
        self.server_config = server_config
        self.log = logger
        self._base_url: Optional[str] = None
        self._session: Optional[requests.Session] = None

    # ------------------------------------------------------------------ #
    #  Internal helpers                                                    #
    # ------------------------------------------------------------------ #

    def _conf(self, *keys, default=None):
        for k in keys:
            v = self.mod_config.get(k)
            if v is not None:
                return v
        return default

    def _get_session(self) -> Tuple[requests.Session, str]:
        """Return (session, base_url), creating them once."""
        if self._session and self._base_url:
            return self._session, self._base_url

        base = _normalize_base_url(
            self._conf("cortex_url", default="http://cortex:9001")
        )
        api_key = self._conf("cortex_api_key", default="")
        verify = bool(self._conf("verify_ssl", default=False))

        if not base:
            raise ValueError("cortex_url is not configured")
        if not api_key or api_key == "CHANGE_ME":
            raise ValueError("cortex_api_key is not configured")

        s = requests.Session()
        s.headers.update({
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        })
        s.verify = verify

        self._session = s
        self._base_url = base
        self.log.info(f"Cortex session ready: {base}")
        return s, base

    def _get(self, path: str, params: dict = None) -> dict:
        s, base = self._get_session()
        url = f"{base}{path}"
        resp = s.get(url, params=params, timeout=10)
        self.log.debug(f"GET {url} -> {resp.status_code}")
        resp.raise_for_status()
        return resp.json()

    def _post(self, path: str, payload: dict) -> dict:
        s, base = self._get_session()
        url = f"{base}{path}"
        resp = s.post(url, json=payload, timeout=10)
        self.log.debug(f"POST {url} -> {resp.status_code}")
        if resp.status_code not in (200, 201):
            self.log.error(f"Cortex POST {url} failed {resp.status_code}: {resp.text[:500]}")
        resp.raise_for_status()
        return resp.json()

    # ------------------------------------------------------------------ #
    #  Config helpers                                                      #
    # ------------------------------------------------------------------ #

    def _get_configured_analyzers(self) -> List[str]:
        raw = self._conf("cortex_analyzers", default="VirusTotal_GetReport_3_1")
        entries = []
        for part in str(raw).replace("\n", ",").split(","):
            part = part.strip()
            if part:
                entries.append(part)
        return entries

    def _normalize_ioc_type(self, ioc_type: str) -> str:
        ioc_type_lower = ioc_type.lower().strip()
        if ioc_type_lower in IOC_TYPE_MAP:
            return IOC_TYPE_MAP[ioc_type_lower]
        if "|" in ioc_type_lower:
            parts = ioc_type_lower.split("|")
            candidates = [IOC_TYPE_MAP.get(p.strip()) for p in parts if IOC_TYPE_MAP.get(p.strip())]
            for preferred in CORTEX_TYPE_PRIORITY:
                if preferred in candidates:
                    return preferred
        self.log.warning(f"Unknown IOC type '{ioc_type}' — sending as 'other'")
        return "other"

    # ------------------------------------------------------------------ #
    #  Cortex 4.x REST operations                                         #
    # ------------------------------------------------------------------ #

    def _discover_analyzers(self) -> List[dict]:
        """
        GET /api/analyzer — returns list of all enabled analyzer objects.
        Each object has: id, name, dataTypeList, ...
        """
        try:
            result = self._get("/api/analyzer")
            if isinstance(result, list):
                return result
            return result.get("data", result.get("analyzers", []))
        except Exception as e:
            self.log.warning(f"Could not discover analyzers from Cortex: {e}")
            return []

    def _find_analyzer_id(self, name: str, available: List[dict]) -> Optional[str]:
        """Resolve analyzer name to its id field (used for POST /run)."""
        for a in available:
            if a.get("name") == name:
                return a.get("id") or a.get("_id")
        return None

    def _submit_job(self, analyzer_id: str, ioc_value: str, data_type: str) -> str:
        """
        POST /api/analyzer/<id>/run
        Returns job id string.
        """
        payload = {
            "data": ioc_value,
            "dataType": data_type,
            "tlp": 2,
            "message": "Submitted by DFIR-IRIS Cortex Analyzer module",
        }
        job = self._post(f"/api/analyzer/{analyzer_id}/run", payload)
        job_id = job.get("id") or job.get("_id")
        if not job_id:
            raise ValueError(f"Cortex did not return a job id. Response: {job}")
        self.log.info(f"Job submitted: id={job_id} analyzer={analyzer_id} data={ioc_value}")
        return job_id

    def _poll_job(self, job_id: str, timeout: int, poll: int) -> dict:
        """
        Poll GET /api/job/<id> until status is Success/Failure or timeout.
        """
        elapsed = 0
        while elapsed < timeout:
            job = self._get(f"/api/job/{job_id}")
            status = job.get("status", "")
            self.log.debug(f"Job {job_id} status: {status} ({elapsed}s elapsed)")
            if status in ("Success", "Failure"):
                return job
            time.sleep(poll)
            elapsed += poll
        return {"status": "Timeout", "id": job_id}

    def _get_report(self, job_id: str) -> dict:
        """
        GET /api/job/<id>/report — returns full analyzer report.
        """
        try:
            result = self._get(f"/api/job/{job_id}/report")
            report = result.get("report", result)
            return report.get("full", report)
        except Exception as e:
            self.log.warning(f"Could not fetch report for job {job_id}: {e}")
            return {"error": str(e)}

    def _run_analyzer(self, analyzer_id: str, analyzer_name: str,
                      ioc_value: str, data_type: str) -> dict:
        timeout = int(self._conf("job_timeout_seconds", default=300))
        poll = int(self._conf("poll_interval_seconds", default=5))

        self.log.info(f"Running analyzer '{analyzer_name}' on '{ioc_value}' (dataType={data_type})")
        job_id = self._submit_job(analyzer_id, ioc_value, data_type)
        job = self._poll_job(job_id, timeout, poll)
        status = job.get("status", "")

        if status == "Success":
            return self._get_report(job_id)
        elif status == "Failure":
            err = job.get("errorMessage") or job.get("report", {}).get("errorMessage", "Analyzer job failed")
            return {"error": err}
        else:
            return {"error": f"Analyzer timed out after {timeout}s (job={job_id})"}

    # ------------------------------------------------------------------ #
    #  Jinja2 report renderer                                             #
    # ------------------------------------------------------------------ #

    def _render_report(self, results: dict, analyzer_name: str, ioc_value: str) -> str:
        import json
        template_str = self._conf(
            "report_template", default="<pre>{{ results | tojson(indent=2) }}</pre>"
        )
        try:
            env = Environment(loader=BaseLoader())
            env.filters["tojson"] = lambda v, indent=None: json.dumps(v, indent=indent)
            tmpl = env.from_string(template_str)
            return tmpl.render(results=results, analyzer_name=analyzer_name, ioc_value=ioc_value)
        except TemplateError as e:
            self.log.warning(f"Template render failed: {e}")
            return f"<pre>{json.dumps(results, indent=2)}</pre>"

    # ------------------------------------------------------------------ #
    #  IOC entry-point                                                     #
    # ------------------------------------------------------------------ #

    def handle_iocs(self, data: list):
        import iris_interface.IrisInterfaceStatus as InterfaceStatus

        try:
            self._get_session()
        except Exception as e:
            self.log.error(f"Cannot initialise Cortex session: {e}")
            return InterfaceStatus.I2Error(message=str(e))

        configured_analyzers = self._get_configured_analyzers()
        available = self._discover_analyzers()
        available_names = {a.get("name") for a in available}

        if available:
            self.log.info(f"Cortex reports {len(available)} analyzer(s) available")
        else:
            self.log.warning("No analyzers returned by Cortex — check your org has analyzers enabled")

        for ioc in data:
            try:
                ioc_value = ioc.ioc_value
                raw_type = ioc.ioc_type.type_name
                data_type = self._normalize_ioc_type(raw_type)
                self.log.info(f"IOC: {ioc_value} | IRIS type: {raw_type} | Cortex dataType: {data_type}")
            except Exception as e:
                self.log.error(f"Cannot read IOC fields: {e}")
                continue

            for analyzer_name in configured_analyzers:
                if available_names and analyzer_name not in available_names:
                    self.log.warning(
                        f"Analyzer '{analyzer_name}' not found in Cortex. "
                        f"Available: {sorted(available_names)}"
                    )
                    continue

                analyzer_id = self._find_analyzer_id(analyzer_name, available)
                if not analyzer_id:
                    self.log.warning(
                        f"Could not resolve analyzer id for '{analyzer_name}'. Skipping."
                    )
                    continue

                try:
                    results = self._run_analyzer(analyzer_id, analyzer_name, ioc_value, data_type)
                    report_html = self._render_report(results, analyzer_name, ioc_value)
                    if self._conf("report_as_attribute", default=True):
                        self._save_attribute(ioc, analyzer_name, report_html)
                except Exception as e:
                    self.log.error(f"Error running {analyzer_name} on {ioc_value}: {e}")
                    continue

        return InterfaceStatus.I2Success()

    def _save_attribute(self, ioc, analyzer_name: str, report_html: str):
        try:
            ioc.add_attribute(
                attribute_name=f"CORTEX: {analyzer_name}",
                attribute_value=report_html
            )
            self.log.info(f"Saved report for {analyzer_name} as IOC attribute")
        except Exception as e:
            self.log.warning(f"Could not save attribute for {analyzer_name}: {e}")
