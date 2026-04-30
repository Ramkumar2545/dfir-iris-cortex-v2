#!/usr/bin/env python3

import iris_interface.IrisInterfaceStatus as InterfaceStatus
from iris_interface.IrisModuleInterface import IrisModuleInterface, IrisModuleTypes

import iris_cortex_analyzer_module.IrisCortexAnalyzerConfig as interface_conf
from iris_cortex_analyzer_module.cortex_handler.cortex_handler import CortexHandler


class IrisCortexAnalyzerInterface(IrisModuleInterface):
    name = "IrisCortexAnalyzerInterface"
    _module_name          = interface_conf.module_name
    _module_description   = interface_conf.module_description
    _interface_version    = interface_conf.interface_version
    _module_version       = interface_conf.module_version
    _pipeline_support     = interface_conf.pipeline_support
    _pipeline_info        = interface_conf.pipeline_info
    _module_configuration = interface_conf.module_configuration
    _module_type          = IrisModuleTypes.module_processor

    def is_ready(self) -> bool:
        return True

    def _conf(self, *keys, default=None):
        for k in keys:
            v = self.module_dict_conf.get(k)
            if v is not None:
                return v
        return default

    def register_hooks(self, module_id: int):
        self.module_id = module_id
        hook_map = [
            (self._conf("on_create_hook_enabled", default=False), "on_postload_ioc_create", None),
            (self._conf("on_update_hook_enabled", default=False), "on_postload_ioc_update", None),
            (self._conf("manual_hook_enabled",    default=True),  "on_manual_trigger_ioc",  "Run Cortex Analyzer"),
        ]
        for enabled, iris_hook, manual_name in hook_map:
            if enabled:
                status = self.register_to_hook(
                    module_id, iris_hook_name=iris_hook, manual_hook_name=manual_name
                )
                if status.is_failure():
                    self.log.error(f"Failed to register hook {iris_hook}: {status.get_message()}")
                else:
                    self.log.info(f"Registered: {iris_hook}")
            else:
                self.deregister_from_hook(module_id=module_id, iris_hook_name=iris_hook)

    def hooks_handler(self, hook_name: str, hook_ui_name: str, data):
        self.log.info(f"Hook: {hook_name}")
        supported = {"on_postload_ioc_create", "on_postload_ioc_update", "on_manual_trigger_ioc"}
        if hook_name not in supported:
            self.log.critical(f"Unsupported hook: {hook_name}")
            return InterfaceStatus.I2Error(data=data, logs=list(self.message_queue))

        if not self._conf("cortex_api_key") or self._conf("cortex_api_key") == "CHANGE_ME":
            self.log.warning("cortex_api_key not configured.")
            return InterfaceStatus.I2Error(
                data=data,
                logs=["cortex_api_key not set. Go to Advanced > Modules > Cortex Analyzer > Configure"]
            )

        handler = CortexHandler(
            mod_config=self.module_dict_conf,
            server_config=self.server_dict_conf,
            logger=self.log
        )
        status = handler.handle_iocs(data)
        if status.is_failure():
            return InterfaceStatus.I2Error(data=data, logs=list(self.message_queue))
        return InterfaceStatus.I2Success(data=data, logs=list(self.message_queue))
