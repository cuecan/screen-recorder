# Third-party notices

CueCan for Mac is licensed under the GNU General Public License, version 3 (see `LICENSE`). It builds on the work below. Each is under its own license, which stays with it.

## Code built into the app

| Project | Used for | License |
| --- | --- | --- |
| [FluidAudio](https://github.com/FluidInference/FluidAudio) | Speech to text on Core ML | Apache-2.0. Its own third-party licenses are in its `ThirdPartyLicenses` folder; CueCan builds only its `NemoTextProcessing` trait. |
| [Sparkle](https://github.com/sparkle-project/Sparkle) | Updates | MIT, with the further notices in its `LICENSE` file |
| [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk) | The `cuecan mcp` server | MIT, moving to Apache-2.0: see its `LICENSE` file |
| [EventSource](https://github.com/mattt/eventsource) | Used by the MCP SDK | MIT |
| [swift-nio](https://github.com/apple/swift-nio), [swift-log](https://github.com/apple/swift-log), [swift-collections](https://github.com/apple/swift-collections), [swift-atomics](https://github.com/apple/swift-atomics), [swift-system](https://github.com/apple/swift-system) | Used by the MCP SDK | Apache-2.0 |

The exact versions are in `Packages/CueCanKit/Package.resolved`.

## Speech models

The app doesn't contain these. It downloads them from Hugging Face the first time they're needed, and they stay under their publishers' licenses.

| Model | Used for | Published by |
| --- | --- | --- |
| Parakeet TDT v3, as Core ML | Transcription | FluidInference, from NVIDIA's model |
| Parakeet CTC 110M, as Core ML | Vocabulary | FluidInference, from NVIDIA's model |
| [Nemotron 3.5 Transcribe Lite, as Core ML](https://huggingface.co/FluidInference/nemotron-3.5-transcribe-lite-coreml) | Word timing | FluidInference, from NVIDIA's model |

VERIFY: each model's license, as stated on its Hugging Face page, before this file is published.

## In this repository, not in the app

| Item | License |
| --- | --- |
| `.agents/skills/swiftui-pro`, from [twostraws/swiftui-agent-skill](https://github.com/twostraws/swiftui-agent-skill) by Paul Hudson | MIT |
