---
library_name: transformers
license: apache-2.0
datasets:
- HuggingFaceM4/the_cauldron
- HuggingFaceM4/Docmatix
pipeline_tag: video-text-to-text
language:
- en
base_model:
- HuggingFaceTB/SmolLM2-360M-Instruct
- google/siglip-base-patch16-512
- HuggingFaceTB/SmolVLM2-500M-Video-Instruct
tags:
- mlx
---

# HuggingFaceTB/SmolVLM2-500M-Video-Instruct-mlx
This model was converted to MLX format from [`HuggingFaceTB/SmolVLM2-500M-Video-Instruct`]() using mlx-vlm version **0.1.13**.
Refer to the [original model card](https://huggingface.co/HuggingFaceTB/SmolVLM2-500M-Video-Instruct) for more details on the model.
## Use with mlx

```bash
pip install -U mlx-vlm
```

```bash
python -m mlx_vlm.generate --model mlx-community/SmolVLM2-500M-Video-Instruct-mlx --image https://huggingface.co/datasets/huggingface/documentation-images/resolve/main/bee.jpg --prompt "Can you describe this image?"
```
