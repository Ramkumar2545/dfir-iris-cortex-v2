#!/usr/bin/env python3

import requests

import iris_interface.IrisInterfaceStatus as InterfaceStatus
from iris_interface.IrisModuleInterface import IrisModuleInterface, IrisModuleTypes

import iris_cortex_analyzer_module.IrisCortexAnalyzerConfig as interface_conf
from iris_cortex_analyzer_module.cortex_handler.cortex_handler import CortexHandler


class IrisCortexAnalyzerInterface(IrisModuleInterface):
    name = "IrisCortexAnalyzerInterface"
    _module_name = interface_conf.module_name
    _module_description = interface_conf.module_description
    _interface_version = interface_conf.interface_version
    _module_version = interface_conf.module_version
    _pipeline_support = interface_conf.pipeline_support
    _pipeline_info = interface_conf.pipeline_info
    _module_configuration = interface_conf.module_configuration
    _module_type = IrisModuleTypes.module_processor

    def _conf(self, key, *aliases, default=None):
        conf = self.module_dict_conf
        if not isinstance(conf, dict):
            return default
        for candidate in (key, *aliases):
            value = conf.get(candidate)
            if value is not None:
                return value
        return default

    def is_ready(self) -> bool:
        return True

    def _probe_cortex(self):
        url = (self._conf("cortex_url", default="http://cortex:9001") or "").rstrip("/")
        probe = f"{url}/api/status"
        try:
            resp = requests.get(probe, timeout=5, verify=False)
            if resp.status_code in (200, 520):
                self.log.info(f"Cortex reachable at {url} (HTTP {resp.status_code})")
                return True, url
            self.log.warning(f"Cortex at {url} returned HTTP {resp.status_code}")
            return False, url
        except requests.exceptions.ConnectionError:
            self.log.error(
                f"Cannot connect to Cortex at {url}. "
                "Fix cortex_url: http://cortex:9001 or http://host.docker.internal:9001 or http://<HOST_IP>:9001"
            )
            return False, url
        except requests.exceptions.Timeout:
            self.log.error(f"Cortex connection timed out at {url}")
            return False, url

    def _logs(self):
        """Return message_queue as a list of plain strings."""
        return [str(m) for m in self.message_queue]

    def register_hooks(self, module_id: int):
        self.module_id = module_id
        hook_map = [
            (self._conf("on_create_hook_enabled", default=False), "on_postload_ioc_create", None),
            (self._conf("on_update_hook_enabled", default=False), "on_postload_ioc_update", None),
            (self._conf("manual_hook_enabled", default=True), "on_manual_trigger_ioc", "Run Cortex Analyzer"),
        ]
        for enabled, iris_hook, manual_name in hook_map:
            if enabled:
                status = self.register_to_hook(
                    module_id, iris_hook_name=iris_hook, manual_hook_name=manual_name
                )
                if status.is_failure():
                    self.log.error(f"Failed to register hook {iris_hook}: {status.get_message()}")
                else:
                    self.log.info(f"Registered hook: {iris_hook}")
            else:
                self.deregister_from_hook(module_id=module_id, iris_hook_name=iris_hook)

    def hooks_handler(self, hook_name: str, hook_ui_name: str, data: any):
        self.log.info(f"Hook received: {hook_name}")
        supported = {"on_postload_ioc_create", "on_postload_ioc_update", "on_manual_trigger_ioc"}

        if hook_name not in supported:
            self.log.critical(f"Unsupported hook: {hook_name}")
            return InterfaceStatus.I2Error(data=data, logs=self._logs())

        cortex_api_key = self._conf("cortex_api_key", default="")
        if not cortex_api_key or str(cortex_api_key).strip() == "CHANGE_ME":
            msg = "cortex_api_key not set. Go to Advanced > Modules > Cortex Analyzer > Configure"
            self.log.warning(msg)
            return InterfaceStatus.I2Error(data=data, logs=[msg])

        reachable, url = self._probe_cortex()
        if not reachable:
            msg = f"Cannot reach Cortex at {url}. Check cortex_url in module config."
            return InterfaceStatus.I2Error(data=data, logs=[msg])

        handler = CortexHandler(
            mod_config=self.module_dict_conf,
            server_config=self.server_dict_conf,
            logger=self.log
        )
        status = handler.handle_iocs(data)
        if status.is_failure():
            return InterfaceStatus.I2Error(data=data, logs=self._logs())
        return InterfaceStatus.I2Success(data=data, logs=self._logs())
