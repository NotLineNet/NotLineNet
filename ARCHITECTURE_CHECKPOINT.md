## 2026-02-05
- Step 0.1: Added `EventBus` singleton (`scripts/core/EventBus.gd`) with subscribe/unsubscribe/emit API and registered it in `project.godot` autoload.
- Step 0.2: Added stub `UIWindowQueue` singleton (`scripts/ui/UIWindowQueue.gd`) and empty `WindowRegistry.tres`; registered `UIWindowQueue` in `project.godot` autoload. Currently returns immediate closed handles as placeholder.