@tool
extends EditorScript

func _run() -> void:
    print("EDITOR_SCRIPT_RUN")
    if Engine.has_singleton("McpClientConfigurator") or true:
        var result: Dictionary = McpClientConfigurator.configure("deepseek-harness")
        print("CONFIG_RESULT=", JSON.stringify(result))
