# Requirements
Before using Cygon Link, make sure the following requirements are met.

## Software Requirements
| Software | Minimum Version | Notes                                                        |
|----------|-----------------|--------------------------------------------------------------|
| Godot    | 4.6+            | Earlier 4.x versions may work but are untested               |
| Cygon    | 0.3.3+          | Earlier versions do not support the required export pipeline |

> New to Cygon? See [What is Cygon?](WhatIsCygon.md).

## No extra plugins required
Unlike some USD workflows, Cygon Link does **not** depend on the OpenUSD library or any third-party addon. It is written entirely in GDScript and ships with its own `EditorImportPlugin`, so there is nothing else to install, compile, or enable.

Materials are created as `ShaderMaterial` (a small built-in spatial shader) and embedded directly in the imported scene, they work the same across the Forward+, Mobile, and Compatibility renderers, so there is no render-pipeline setup to worry about.

## Platform Support
Because Cygon Link is pure GDScript with no native code, it runs anywhere the Godot editor runs:

| Platform       | Supported                                  |
|----------------|--------------------------------------------|
| Windows 64-bit | ✅                                         |
| macOS          | ✅                                         |
| Linux          | ✅ (Cygon isn't really available on Linux) |

> Cygon Link is an **editor-only** tool: it converts `.usda` files while you work in the Godot editor and adds no runtime code to your exported games.
